########################################################################

# This file is part of the UNAM telescope control system.

# $Id: mount.tcl 3594 2020-06-10 14:55:51Z Alan $

########################################################################

# Copyright © 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2017, 2018, 2019 Alan M. Watson <alan@astro.unam.mx>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
# WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
# AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
# DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR
# PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
# TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.

########################################################################

config::setdefaultvalue "mount" "configuration" "equatorial"

config::setdefaultvalue "mount" "settlinglimit"        "1as"
config::setdefaultvalue "mount" "settlingdelayseconds" "0"

namespace eval "mount" {

  ######################################################################

  variable configuration [config::getvalue "mount" "configuration"]
  
  variable settlinglimit        [astrometry::parseoffset [config::getvalue "mount" "settlinglimit"]]
  variable settlingdelayseconds [config::getvalue "mount" "settlingdelayseconds"]
  
  ######################################################################

  server::setdata "configuration" $configuration

  ######################################################################

  proc updaterequestedpositiondata {{updaterequestedrotation false}} {
  
    variable configuration
    variable usemountcoordinates

    log::debug "updating requested position."

    set seconds [utcclock::seconds]

    if {[catch {client::update "target"} message]} {
      error "unable to update target data: $message"
    }
    set targetstatus   [client::getstatus "target"]
    set targetactivity [client::getdata "target" "activity"]
    log::debug "target status is \"$targetstatus\"."
    log::debug "target activity is \"$targetactivity\"."

    set activity [server::getactivity]
    set requestedactivity [server::getrequestedactivity]
    log::debug "continuing to update requested position for activity \"$activity\" and requested activity \"$requestedactivity\"."

    set requestedmountha                ""
    set requestedmountalpha             ""
    set requestedmountdelta             ""
    set requestedmountharate            ""
    set requestedmountalpharate         ""
    set requestedmountdeltarate         ""

    set mounthaerror                    ""
    set mountalphaerror                 ""
    set mountdeltaerror                 ""

    if {
      [string equal $requestedactivity "tracking"] &&
      [string equal $targetstatus "ok"] &&
      [string equal $targetactivity "tracking"]
    } {

      log::debug "updating requested position in the tracking/ok/tracking branch."

      set requestedtimestamp              [client::getdata "target" "timestamp"]

      set requestedstandardalpha          [client::getdata "target" "standardalpha"]
      set requestedstandarddelta          [client::getdata "target" "standarddelta"]
      set requestedstandardalpharate      [client::getdata "target" "standardalpharate"]
      set requestedstandarddeltarate      [client::getdata "target" "standarddeltarate"]
      set requestedstandardequinox        [client::getdata "target" "standardequinox"]

      set requestedobservedha             [client::getdata "target" "observedha"]
      set requestedobservedalpha          [client::getdata "target" "observedalpha"]
      set requestedobserveddelta          [client::getdata "target" "observeddelta"]
      set requestedobservedharate         [client::getdata "target" "observedharate"]
      set requestedobservedalpharate      [client::getdata "target" "observedalpharate"]
      set requestedobserveddeltarate      [client::getdata "target" "observeddeltarate"]
      set requestedobservedazimuth        [client::getdata "target" "observedazimuth"]
      set requestedobservedzenithdistance [client::getdata "target" "observedzenithdistance"]
      
      if {$updaterequestedrotation} {
        set requestedmountrotation [mountrotation $requestedobservedha $requestedobservedalpha]
      } else {
        set requestedmountrotation [server::getdata "mountrotation"]
      }

      if {$usemountcoordinates} {
      
        set seconds [utcclock::scan $requestedtimestamp]
        set dseconds 60
        set futureseconds [expr {$seconds + $dseconds}]

        set mountha       [server::getdata "mountha"      ]
        set mountalpha    [server::getdata "mountalpha"   ]
        set mountdelta    [server::getdata "mountdelta"   ]

        set mountdha    [mountdha    $requestedobservedha    $requestedobserveddelta $requestedmountrotation]
        set mountdalpha [mountdalpha $requestedobservedalpha $requestedobserveddelta $requestedmountrotation $seconds]
        set mountddelta [mountddelta $requestedobservedalpha $requestedobserveddelta $requestedmountrotation $seconds]

        set requestedmountha    [astrometry::foldradsymmetric [expr {$requestedobservedha + $mountdha}]]
        set requestedmountalpha [astrometry::foldradpositive [expr {$requestedobservedalpha + $mountdalpha}]]
        set requestedmountdelta [expr {$requestedobserveddelta + $mountddelta}]

        set futurerequestedmountrotation $requestedmountrotation
        set futurerequestedobservedha    [astrometry::foldradsymmetric [expr {
          $requestedobservedha + $dseconds * $requestedobservedharate
        }]]
        set futurerequestedobservedalpha [astrometry::foldradpositive [expr {
          $requestedobservedalpha + $dseconds * $requestedobservedalpharate / cos($requestedobserveddelta)
        }]]
        set futurerequestedobserveddelta [expr {
          $requestedobserveddelta + $dseconds * $requestedobserveddeltarate
        }]

        set futuremountdha    [mountdha    $futurerequestedobservedha    $futurerequestedobserveddelta $futurerequestedmountrotation]
        set futuremountdalpha [mountdalpha $futurerequestedobservedalpha $futurerequestedobserveddelta $futurerequestedmountrotation $futureseconds]
        set futuremountddelta [mountddelta $futurerequestedobservedalpha $futurerequestedobserveddelta $futurerequestedmountrotation $futureseconds]

        set futurerequestedmountha    [astrometry::foldradsymmetric [expr {$futurerequestedobservedha + $futuremountdha}]]
        set futurerequestedmountalpha [astrometry::foldradpositive [expr {$futurerequestedobservedalpha + $futuremountdalpha}]]
        set futurerequestedmountdelta [expr {$futurerequestedobserveddelta + $futuremountddelta}]

        set requestedmountharate      [astrometry::foldradsymmetric [expr {
          ($futurerequestedmountha - $requestedmountha) / $dseconds
        }]]
        set requestedmountalpharate   [astrometry::foldradsymmetric [expr {
          ($futurerequestedmountalpha - $requestedmountalpha) / $dseconds * cos($requestedobserveddelta)
        }]]
        set requestedmountdeltarate   [expr {
          ($futurerequestedmountdelta - $requestedmountdelta) / $dseconds
        }]

        set mounthaerror    ""
        set mountalphaerror [astrometry::foldradsymmetric [expr {$mountalpha - $requestedmountalpha}]]
        set mountdeltaerror [expr {$mountdelta - $requestedmountdelta}]
        
      }

    } elseif {
      [string equal $requestedactivity "idle"] &&
      [string equal $targetstatus "ok"] &&
      [string equal $targetactivity "idle"]
    } {

      log::debug "updating requested position in the idle/ok/idle equatorial branch."

      set requestedtimestamp              [client::getdata "target" "timestamp"]

      set requestedstandardalpha          ""
      set requestedstandarddelta          ""
      set requestedstandardalpharate      ""
      set requestedstandarddeltarate      ""
      set requestedstandardequinox        ""

      set requestedobservedha             [client::getdata "target" "observedha"]
      set requestedobservedalpha          [client::getdata "target" "observedalpha"]
      set requestedobserveddelta          [client::getdata "target" "observeddelta"]
      set requestedobservedharate         ""
      set requestedobservedalpharate      ""
      set requestedobserveddeltarate      ""
      set requestedobservedazimuth        [client::getdata "target" "observedazimuth"]
      set requestedobservedzenithdistance [client::getdata "target" "observedzenithdistance"]

      if {$updaterequestedrotation} {
        set requestedmountrotation [mountrotation $requestedobservedha $requestedobservedalpha]
      } else {
        set requestedmountrotation [server::getdata "mountrotation"]
      }
      
      if {$usemountcoordinates} {
      
        set mountha       [server::getdata "mountha"      ]
        set mountalpha    [server::getdata "mountalpha"   ]
        set mountdelta    [server::getdata "mountdelta"   ]

        set mountdha    [mountdha    $requestedobservedha    $requestedobserveddelta $requestedmountrotation]
        set mountddelta [mountddelta $requestedobservedalpha $requestedobserveddelta $requestedmountrotation]

        set requestedmountha         [astrometry::foldradsymmetric [expr {$requestedobservedha + $mountdha}]]
        set requestedmountalpha      ""
        set requestedmountdelta      [expr {$requestedobserveddelta + $mountddelta}]

        set requestedmountharate     ""
        set requestedmountalpharate  ""
        set requestedmountdeltarate  ""

        set mounthaerror    [astrometry::foldradsymmetric [expr {$mountha    - $requestedmountha   }]]
        set mountalphaerror ""
        set mountdeltaerror [expr {$mountdelta - $requestedmountdelta}]
    
      }

    } else {

      log::debug "updating requested position in the last branch."

      set requestedtimestamp              ""

      set requestedstandardalpha          ""
      set requestedstandarddelta          ""
      set requestedstandardalpharate      ""
      set requestedstandarddeltarate      ""
      set requestedstandardequinox        ""

      set requestedmountrotation          ""
      set requestedobservedha             ""
      set requestedobservedalpha          ""
      set requestedobserveddelta          ""
      set requestedobservedharate         ""
      set requestedobservedalpharate      ""
      set requestedobserveddeltarate      ""
      set requestedobservedazimuth        ""
      set requestedobservedzenithdistance ""

      set requestedmountha                ""
      set requestedmountalpha             ""
      set requestedmountdelta             ""
      set requestedmountharate            ""
      set requestedmountalpharate         ""
      set requestedmountdeltarate         ""

      set mounthaerror                    ""
      set mountalphaerror                 ""
      set mountdeltaerror                 ""

    }

    server::setdata "requestedtimestamp"              $requestedtimestamp
    server::setdata "requestedmountrotation"          $requestedmountrotation
    server::setdata "requestedstandardalpha"          $requestedstandardalpha
    server::setdata "requestedstandarddelta"          $requestedstandarddelta
    server::setdata "requestedstandardalpharate"      $requestedstandardalpharate
    server::setdata "requestedstandarddeltarate"      $requestedstandarddeltarate
    server::setdata "requestedstandardequinox"        $requestedstandardequinox
    server::setdata "requestedobservedha"             $requestedobservedha
    server::setdata "requestedobservedalpha"          $requestedobservedalpha
    server::setdata "requestedobserveddelta"          $requestedobserveddelta
    server::setdata "requestedobservedharate"         $requestedobservedharate
    server::setdata "requestedobservedalpharate"      $requestedobservedalpharate
    server::setdata "requestedobserveddeltarate"      $requestedobserveddeltarate
    server::setdata "requestedobservedazimuth"        $requestedobservedazimuth
    server::setdata "requestedobservedzenithdistance" $requestedobservedzenithdistance
    server::setdata "requestedmountha"                $requestedmountha
    server::setdata "requestedmountalpha"             $requestedmountalpha
    server::setdata "requestedmountdelta"             $requestedmountdelta
    server::setdata "requestedmountharate"            $requestedmountharate
    server::setdata "requestedmountalpharate"         $requestedmountalpharate
    server::setdata "requestedmountdeltarate"         $requestedmountdeltarate
    server::setdata "mounthaerror"                    $mounthaerror
    server::setdata "mountalphaerror"                 $mountalphaerror
    server::setdata "mountdeltaerror"                 $mountdeltaerror

    log::debug "finished updating requested position."
  }
  
  ######################################################################
  
  variable tracking          false
  variable trackingtimestamp ""
  variable forcenottracking  false
  variable settlingtimestamp ""
  variable waittracking

  proc checktracking {maybetracking trackingerror} {

    variable tracking
    variable forcenottracking
    variable settlingtimestamp
    variable settlingdelay
    variable waittracking
    
    variable settlinglimit
    variable settlingdelayseconds
    
    set lasttracking $tracking
    
    if {$forcenottracking} {

      log::info "forcing: tracking is false."
      set tracking false
      set forcenottracking false

    } elseif {![string equal [server::getrequestedactivity] "tracking"]} {

      log::info "requestedactivity: tracking is false."
      set tracking false

    } elseif {!$maybetracking} {

      log::info "maybetracking: tracking is false."
      set tracking false
      
    } elseif {$lasttracking} {

      log::info "continuing: tracking is true."
      set tracking true

    } elseif {$trackingerror > $settlinglimit} {

      log::info "large error: tracking is false."
      set tracking false
      
    } elseif {$settlingdelayseconds == 0} {
    
      log::info "no settling delay: tracking is true."
      set tracking true

    } elseif {[string equal $settlingtimestamp ""]} {

      log::info "starting settling: tracking is false"
      set settlingtimestamp [utcclock::combinedformat "now"]

    } elseif {[utcclock::diff "now" $settlingtimestamp] < $settlingdelayseconds} {

      log::info "settling: tracking is false."
      set tracking false

    } else {

      log::info "else: tracking is true."
      set tracking true

    }
    
    if {!$lasttracking && $tracking} {
      log::info "started tracking."
      set trackingtimestamp [utcclock::combinedformat]
    } elseif {$lasttracking && !$tracking} {
      log::info "stopped tracking."
      set trackingtimestamp ""
    }

    set waittracking $tracking
  }

  proc waituntiltracking {} {
    log::debug "waituntiltracking: starting."
    variable waittracking
    set waittracking false
    while {!$waittracking} {
      log::debug "waituntiltracking: yielding."
      coroutine::yield
    }
    log::debug "waituntiltracking: finished."
  }

  proc waituntilnottracking {} {
    log::debug "waituntilnottracking: starting."
    variable tracking
    while {$tracking} {
      log::debug "waituntilnottracking: yielding."
      coroutine::yield
    }
    log::debug "waituntilnottracking: finished."
  }

  ######################################################################

  proc mountdha {ha delta rotation} {
    variable pointingmodelpolarhole 
    if {0.5 * [astrometry::pi] - abs($delta) <= $pointingmodelpolarhole} {
      set dha 0
    } else {
      set dha [pointing::modeldha [pointingmodelparameters $rotation] $ha $delta]
    }
    return $dha
  }

  proc mountdalpha {alpha delta rotation {seconds "now"}} {
    variable pointingmodelpolarhole 
    if {0.5 * [astrometry::pi] - abs($delta) <= $pointingmodelpolarhole} {
      set dalpha 0
    } else {
      set ha [astrometry::ha $alpha $seconds]
      set dalpha [pointing::modeldalpha  [pointingmodelparameters $rotation] $ha $delta]
    }
    return $dalpha
  }

  proc mountdha {ha delta rotation} {
    variable pointingmodelpolarhole 
    if {0.5 * [astrometry::pi] - abs($delta) <= $pointingmodelpolarhole} {
      set dha 0
    } else {
      set dha [pointing::modeldha [pointingmodelparameters $rotation] $ha $delta]
    }
    return $dha
  }

  proc mountdalpha {alpha delta rotation {seconds "now"}} {
    variable pointingmodelpolarhole 
    if {0.5 * [astrometry::pi] - abs($delta) <= $pointingmodelpolarhole} {
      set dalpha 0
    } else {
      set ha [astrometry::ha $alpha $seconds]
      set dalpha [pointing::modeldalpha  [pointingmodelparameters $rotation] $ha $delta]
    }
    return $dalpha
  }

  proc mountddelta {alpha delta rotation {seconds "now"}} {
    variable pointingmodelpolarhole 
    if {0.5 * [astrometry::pi] - abs($delta) <= $pointingmodelpolarhole} {
      set ddelta 0
    } else {
      set ha [astrometry::ha $alpha $seconds]
      set ddelta [pointing::modelddelta [pointingmodelparameters $rotation] $ha $delta]
    }
    return $ddelta
  }

  proc pointingmodelparameters {rotation} {
    variable pointingmodelparameters0
    variable pointingmodelparameters180
    if {$rotation == 0} {
      return $pointingmodelparameters0
    } else {
      return $pointingmodelparameters180
    }
  }

  proc setpointingmodelparameters {rotation newpointingmodelparameters} {
    variable pointingmodelparameters0
    variable pointingmodelparameters180
    if {$rotation == 0} {
      set pointingmodelparameters0 $newpointingmodelparameters
      config::setvarvalue "mount" "pointingmodelID0" [pointing::getparameter $pointingmodelparameters0 "ID"]
      config::setvarvalue "mount" "pointingmodelIH0" [pointing::getparameter $pointingmodelparameters0 "IH"]
    } else {
      set pointingmodelparameters180 $newpointingmodelparameters
      config::setvarvalue "mount" "pointingmodelID180" [pointing::getparameter $pointingmodelparameters180 "ID"]
      config::setvarvalue "mount" "pointingmodelIH180" [pointing::getparameter $pointingmodelparameters180 "IH"]
    }
  }

  proc updatepointingmodel {dIH dID rotation} {
    setpointingmodelparameters $rotation [pointing::updateabsolutemodel [pointingmodelparameters $rotation] $dIH $dID]
  }
  
  proc setMAtozero {} {
    log::info "setting MA to zero in the pointing model parameters."
    variable pointingmodelparameters0
    variable pointingmodelparameters180
    set pointingmodelparameters0   [pointing::setparameter $pointingmodelparameters0   MA 0]
    set pointingmodelparameters180 [pointing::setparameter $pointingmodelparameters180 MA 0]
    log::info "the pointing model parameters for mount rotation 0 are: $pointingmodelparameters0:"
    log::info "the pointing model parameters for mount rotation 180 are: $pointingmodelparameters180:"
  }

  proc setMEtozero {} {
    log::info "setting ME to zero in the pointing model parameters."
    variable pointingmodelparameters0
    variable pointingmodelparameters180
    set pointingmodelparameters0   [pointing::setparameter $pointingmodelparameters0   ME 0]
    set pointingmodelparameters180 [pointing::setparameter $pointingmodelparameters180 ME 0]
    log::info "the pointing model parameters for mount rotation 0 are: $pointingmodelparameters0:"
    log::info "the pointing model parameters for mount rotation 180 are: $pointingmodelparameters180:"
  }

  ######################################################################

  variable emergencystopped false

  proc checklimits {} {

    variable emergencystopped  
    if {$emergencystopped} {
      return
    }

    set requestedactivity [server::getactivity]
    if {
      ![string equal $requestedactivity "moving"  ] &&
      ![string equal $requestedactivity "tracking"]
    } {
      return
    }

    variable easthalimit
    variable westhalimit
    variable meridianhalimit
    variable polardeltalimit
    variable southdeltalimit
    variable northdeltalimit
    variable zenithdistancelimit
    
    set mountha       [server::getdata "mountha"]
    set mountdelta    [server::getdata "mountdelta"]
    set mountrotation [server::getdata "mountrotation"]

    set mountzenithdistance [astrometry::equatorialtozenithdistance $mountha $mountdelta]
    
    if {$mountha < $easthalimit && $mountdelta < $polardeltalimit} {
      log::warning "HA exceeds eastern limit."
      set withinlimits false
    } elseif {$mountha > $westhalimit && $mountdelta < $polardeltalimit} {
      log::warning "HA exceeds western limit."
      set withinlimits false
    } elseif {$mountdelta < $southdeltalimit} {
      log::warning "δ exceeds southern limit."
      set withinlimits false
    } elseif {$mountdelta > $northdeltalimit} {
      log::warning "δ exceeds northern limit."
      set withinlimits false
    } elseif {$mountzenithdistance > $zenithdistancelimit} {
      log::warning "zenith distance exceeds limit."
      set withinlimits false
    } elseif {$mountrotation == 0 && $mountha <= -$meridianhalimit && $mountdelta < $polardeltalimit} {
      log::warning "HA exceeds eastern meridian limit."
      set withinlimits false
    } elseif {$mountrotation != 0 && $mountha >= +$meridianhalimit && $mountdelta < $polardeltalimit} {
      log::warning "HA exceeds western meridian limit."
      set withinlimits false
    } else {
      set withinlimits true
    }
    
    if {$withinlimits} {
      return
    }
    
    log::error "mount is moving and not within the limits."
    log::error "mount position is [astrometry::formatha $mountha] [astrometry::formatdelta $mountdelta]."
    log::error [format "mount rotation is %.0f°." [astrometry::radtodeg $mountrotation]]

    log::error "starting emergency stop."

    emergencystophardware

    server::setdata "mounttracking" false
    set emergencystopped true

    server::erroractivity

  }

  ######################################################################


  proc initialize {} {
    server::checkstatus
    server::checkactivityforinitialize
    server::newactivitycommand "initializing" "idle" mount::initializeactivitycommand 1200000
  }

  proc open {} {
    server::checkstatus
    server::checkactivityformove
    server::newactivitycommand "opening" "idle" mount::openactivitycommand 1200000
  }

  proc stop {} {
    server::checkstatus
    server::checkactivityforstop
    server::newactivitycommand "stopping" [server::getstoppedactivity] mount::stopactivitycommand
  }

  proc reset {} {
    server::checkstatus
    server::checkactivityforreset
    server::newactivitycommand "resetting" [server::getstoppedactivity] mount::resetactivitycommand
  }

  proc reboot {} {
    server::checkstatus
    server::checkactivityforreset
    server::newactivitycommand "rebooting" [server::getstoppedactivity] mount::rebootactivitycommand
  }

  proc preparetomove {} {
    server::checkstatus
    server::checkactivityformove
    server::newactivitycommand "preparingtomove" "preparedtomove" mount::preparetomoveactivitycommand
  }

  proc move {} {
    server::checkstatus
    server::checkactivity "preparedtomove"
    if {[catch {client::checkactivity "target" "idle"} message]} {
      stop
      error "move cancelled because $message"
    }
    server::newactivitycommand "moving" "idle" mount::moveactivitycommand
  }

  proc park {} {
    server::checkstatus
    server::checkactivity "preparedtomove"
    if {[catch {client::checkactivity "target" "idle"} message]} {
      stop
      error "parking cancelled because $message"
    }
    server::newactivitycommand "parking" "idle" mount::parkactivitycommand
  }

  proc unpark {} {
    server::checkstatus
    server::checkactivity "preparedtomove"
    if {[catch {client::checkactivity "target" "idle"} message]} {
      stop
      error "unparking cancelled because $message"
    }
    server::newactivitycommand "unparking" "idle" mount::unparkactivitycommand
  }

  proc preparetotrack {} {
    server::checkstatus
    server::checkactivityformove
    server::newactivitycommand "preparingtotrack" "preparedtotrack" mount::preparetotrackactivitycommand
  }

  proc track {} {
    server::checkstatus
    server::checkactivity "preparedtotrack"
    if {[catch {client::checkactivity "target" "tracking"} message]} {
      stop
      error "move cancelled because $message"
    }
    server::newactivitycommand "moving" "tracking" mount::trackactivitycommand
  }

  proc offset {} {
    server::checkstatus
    server::checkactivity "preparedtotrack"
    if {[catch {client::checkactivity "target" "tracking"} message]} {
      stop
      error "move cancelled because $message"
    }
    server::newactivitycommand "offsetting" "tracking" mount::offsetactivitycommand
  }

  proc guide {alphaoffset deltaoffset} {
    server::checkstatus
    server::checkactivity "tracking"
    set alphaoffset [astrometry::parseangle $alphaoffset dms]
    set deltaoffset [astrometry::parseangle $deltaoffset dms]
    log::debug [format "offsetting %s E and %s N to correct guiding." [astrometry::formatoffset $alphaoffset] [astrometry::formatoffset $deltaoffset]]
    offsetcommand push $alphaoffset $deltaoffset
    return
    
    set totaloffset [expr {sqrt($alphaoffset * $alphaoffset + $deltaoffset * $deltaoffset)}]
    variable allowedguideoffset
    if {$totaloffset > $allowedguideoffset} {
      log::warning "requested guide offset is too large."
      return
    } else {
      offsetcommand push $alphaoffset $deltaoffset
    }
    return
  }
  
  proc correct {solvedmountalpha solvedmountdelta equinox} {
    server::checkstatus
    server::checkactivity "tracking"
    set solvedmountalpha [astrometry::parsealpha $solvedmountalpha]
    set solvedmountdelta [astrometry::parsedelta $solvedmountdelta]
    set start [utcclock::seconds]
    log::info "solved position is [astrometry::formatalpha $solvedmountalpha] [astrometry::formatdelta $solvedmountdelta] $equinox"
    if {[string equal $equinox "observed"]} {
      set solvedmountobservedalpha $solvedmountalpha
      set solvedmountobserveddelta $solvedmountdelta
    } else {
      set solvedmountobservedalpha [astrometry::observedalpha $solvedmountalpha $solvedmountdelta $equinox]
      set solvedmountobserveddelta [astrometry::observeddelta $solvedmountalpha $solvedmountdelta $equinox]    
    }
    log::info "solved mount observed position is [astrometry::formatalpha $solvedmountobservedalpha] [astrometry::formatdelta $solvedmountobserveddelta]."
    set requestedobservedalpha [server::getdata "requestedobservedalpha"]
    set requestedobserveddelta [server::getdata "requestedobserveddelta"]
    log::info "requested mount observed position is [astrometry::formatalpha $requestedobservedalpha] [astrometry::formatdelta $requestedobserveddelta]."
    set mountalphaerror [server::getdata "mountalphaerror"]
    set mountdeltaerror [server::getdata "mountdeltaerror"]
    set mountobservedalpha [astrometry::foldradpositive  [expr {$requestedobservedalpha + $mountalphaerror}]]
    set mountobserveddelta [astrometry::foldradsymmetric [expr {$requestedobserveddelta + $mountdeltaerror}]]
    log::info "mount observed position is [astrometry::formatalpha $mountobservedalpha] [astrometry::formatdelta $mountobserveddelta]."
    set d [astrometry::distance $mountobservedalpha $mountobserveddelta $solvedmountobservedalpha $solvedmountobserveddelta]
    log::info [format "correction is %s." [astrometry::formatdistance $d]]
    set dalpha [astrometry::foldradsymmetric [expr {$mountobservedalpha - $solvedmountobservedalpha}]]
    set ddelta [astrometry::foldradsymmetric [expr {$mountobserveddelta - $solvedmountobserveddelta}]]
    set alphaoffset [expr {$dalpha * cos($solvedmountobserveddelta)}]
    set deltaoffset $ddelta
    log::info [format "correction is %s E and %s N." [astrometry::formatoffset $alphaoffset] [astrometry::formatoffset $deltaoffset]]
    variable maxcorrection
    if {$d >= $maxcorrection} {
      log::warning [format "ignoring corrction: the correction distance of %s is larger than the maximum allowed of %s." [astrometry::formatdistance $d] [astrometry::formatdistance $maxcorrection]]
    } else {
      server::setdata "lastcorrectiontimestamp" [utcclock::format]
      server::setdata "lastcorrectiondalpha"    $dalpha
      server::setdata "lastcorrectionddelta"    $ddelta
      set dha [expr {-($dalpha)}]
      updatepointingmodel $dha $ddelta [server::getdata "mountrotation"]
      updaterequestedpositiondata
      set requestedobservedalpha [server::getdata "requestedobservedalpha"]
      set requestedobserveddelta [server::getdata "requestedobserveddelta"]
      log::info "requested mount observed position is [astrometry::formatalpha $requestedobservedalpha] [astrometry::formatdelta $requestedobserveddelta]."  
    }
    log::info [format "finished correcting after %.1f seconds." [utcclock::diff now $start]]
    return
  }

  ######################################################################

  proc start {} {
    variable initialcommand
    controller::startcommandloop $initialcommand
    controller::startstatusloop
    server::newactivitycommand "starting" "started" mount::startactivitycommand
  }

}
