########################################################################

# This file is part of the UNAM telescope control system.

# $Id: telescope.tcl 3601 2020-06-11 03:20:53Z Alan $

########################################################################

# Copyright © 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019 Alan M. Watson <alan@astro.unam.mx>
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

package require "astrometry"
package require "config"
package require "directories"
package require "client"
package require "pointing"
package require "safetyswitch"
package require "coroutine"
package require "server"
package require "utcclock"

namespace eval "telescope" {

  variable svnid {$Id}

  ######################################################################
  
  variable closeexplicitly [config::getvalue "telescope" "closeexplicitly"]
  variable idleha          [astrometry::formatha    [config::getvalue "target" "idleha"   ]]
  variable idledelta       [astrometry::formatdelta [config::getvalue "target" "idledelta"]]
  
  ######################################################################

  variable catalogdirectory [file join [directories::share] "catalogs"]
  
  variable finders [config::getvalue "telescope" "finders"]
  
  variable mechanisms

  ######################################################################
  
  variable withmount
  if {[lsearch $mechanisms "mount"] == -1} {
    set withmount false
  } else {
    set withmount true
  }

  variable withcovers
  if {[lsearch $mechanisms "covers"] == -1} {
    set withcovers false
  } else {
    set withcovers true
  }

  variable withsecondary
  if {[lsearch $mechanisms "secondary"] == -1} {
    set withsecondary false
  } else {
    set withsecondary true
  }

  variable withdome
  if {[lsearch $mechanisms "dome"] == -1} {
    set withdome false
  } else {
    set withdome true
  }

  variable withenclosure
  if {[lsearch $mechanisms "enclosure"] == -1} {
    set withenclosure false
  } else {
    set withenclosure true
  }

  variable withguider
  if {[lsearch $mechanisms "guider"] == -1} {
    set withguider false
  } else {
    set withguider true
  }
  
  ######################################################################

  proc switchlights {state} {
    client::waituntilstarted "lights"
    log::info "switching lights $state."
    client::request "lights" "switch$state"
    client::wait "lights"
  }
  
  ######################################################################
  
  proc switchheater {state} {
    client::waituntilstarted "heater"
    log::info "switching heater $state."
    client::request "heater" "switch$state"
    client::wait "heater"
  }
  
  ######################################################################

  proc getpowercontacts {} {
    client::update "shutters"
    if {[string equal "error" [client::getdata "shutters" "activity"]]} {
      error "shutters activity is \"error\"."
    }
    return [client::getdata "shutters" "powercontacts"]
  }
  
  proc movedomeforshutter {} {
    set i 0
    while {true} {
      log::info "moving dome for shutter."
      client::request "dome" "preparetomove"
      client::wait "dome"
      client::request "dome" "move contacts"
      client::wait "dome"
      if {[string equal [getpowercontacts] "closed"]} {
        return
      }
      if {$i == 3} {
        error "unable to close the shutters power contacts."
      }
      incr i
      log::warning "reinitializing the dome as the shutters power contacts did not close."
      client::request "dome" "initialize"
      client::wait "dome"
    }
  }

  ######################################################################

  proc movesecondaryactivitycommand {z0 setasinitial} {
    set start [utcclock::seconds]  
    log::info "moving the secondary to $z0."
    client::request "secondary" "move $z0 $setasinitial"
    client::wait "secondary"
    log::info [format "finished moving the secondary after %.1f seconds." [utcclock::diff now $start]]
  }
  
  proc setsecondaryoffsetactivitycommand {dz} {
    set start [utcclock::seconds]  
    log::info "setting the secondary offset to $dz."
    client::request "secondary" "setoffset $dz"
    client::wait "secondary"
    log::info [format "finished setting the secondary offset after %.1f seconds." [utcclock::diff now $start]]
  }
  
  ######################################################################

  proc maybecorrectpointing {} {
    variable finders
    set pointingmode [server::getdata "pointingmode"]
    if {[string equal $pointingmode "finder"]} {
      set servers [concat guider $finders]
      foreach server $servers {
        client::request $server "stop"
      }
      foreach server $servers {
        client::wait $server
      }
      log::info "attemping to correct the pointing model."
      finders::getfinderastrometry
      set finder $finders::solvedfinder
      if {[string equal $finder ""]} {
        log::warning "unable to correct pointing."
      } else {
        log::info "correcting pointing with $finder."
        set solvedmountobservedalpha [client::getdata $finder "mountobservedalpha"]
        set solvedmountobserveddelta [client::getdata $finder "mountobserveddelta"]
        log::info "solved $finder mount observed position is [astrometry::formatalpha $solvedmountobservedalpha] [astrometry::formatdelta $solvedmountobserveddelta]."
        client::request "mount" "correct $solvedmountobservedalpha $solvedmountobserveddelta observed"
        client::update "mount"
        set alphaoffset [expr {[client::getdata "mount" "lastcorrectiondalpha"] * cos($solvedmountobserveddelta)}]
        set deltaoffset [client::getdata "mount" "lastcorrectionddelta"]
        log::info [format "pointing error was %+.1fas E and %+.1fas N." [astrometry::radtoarcsec $alphaoffset] [astrometry::radtoarcsec $deltaoffset]]
        set totaloffset [expr {sqrt($alphaoffset * $alphaoffset + $deltaoffset * $deltaoffset)}]
        if {$totaloffset > [server::getdata "pointingtolerance"]} {
          client::request "mount" "preparetotrack"
          client::wait "mount"
          client::request "mount" "track"
          client::wait "mount"
        }
      }  
      foreach server [concat guider $finders] {
        client::request $server "stop"
      }
    }
  }
  
  proc maybeguide {} {
    set guidingmode [server::getdata "guidingmode"]
    variable finders
    if {![string equal $guidingmode "none"]} {
      set servers [concat guider $finders]
      foreach server $servers {
        client::request $server "stop"
      }
      foreach server $servers {
        client::wait $server
      }
      log::info "starting guiding."
      client::request "guider" "guide $guidingmode"
    }
  }

  ######################################################################


  proc startactivitycommand {} {
    set start [utcclock::seconds]
    log::info "starting."
    server::setdata "timestamp" [utcclock::combinedformat now]
    log::info [format "finished starting after %.1f seconds." [utcclock::diff now $start]]
  }
  
  proc stopactivitycommand {} {
    set start [utcclock::seconds]
    log::info "stopping."
    variable mechanisms
    variable finders
    set servers [concat $mechanisms $finders "target"]
    foreach server $servers {
      client::request $server "stop"
    }
    foreach server $servers {
      client::wait $server
    }
    log::info [format "finished stopping after %.1f seconds." [utcclock::diff now $start]]
  }

  proc resetactivitycommand {} {
    set start [utcclock::seconds]
    log::info "resetting."
    variable mechanisms
    variable finders
    set servers [concat $mechanisms $finders "target"]
    foreach server $servers {
      client::waituntilstarted $server
      client::request $server "reset"
    }
    foreach server $server {
      client::wait $server
    }
    client::wait "target"
    log::info [format "finished resetting after %.1f seconds." [utcclock::diff now $start]]
  }
  
  proc recoveractivitycommand {} {
    set start [utcclock::seconds]
    log::info "recovering."
    variable mechanisms
    variable finders
    set servers [concat $mechanisms $finders "target"]
    foreach server $servers {
      client::waituntilstarted $server
      client::request $server "reset"
    }
    foreach server $servers {
      client::wait $server
    }
    set mustinitialize false
    foreach server $servers {
      if {[string equal [client::getdata $server "activity"] "started"]} {
        set mustinitialize true
      }
    }
    if {$mustinitialize} {
      initializeactivitycommand
    }
    log::info [format "finished recovering after %.1f seconds." [utcclock::diff now $start]]
  }
  
  proc initializeactivitycommand {} {
    set start [utcclock::seconds]
    log::info "initializing."
    variable withlights
    variable withheater
    if {[catch {
      server::setdata "timestamp" [utcclock::combinedformat now]
      if {$withlights} {
        switchlights "on"
      }
      if {$withheater} {
        switchheater "automatically"
      }
      initializeprolog
      variable mechanisms
      variable finders
      set servers [concat $mechanisms $finders "target"]
      foreach server $servers {
        client::waituntilstarted $server
        client::resetifnecessary $server
        initializemechanismprolog $server
        client::request $server "stop"
        client::wait $server
        client::request $server "initialize"
        client::wait $server
        initializemechanismepilog $server
      }
      initializeepilog
      if {$withlights} {
        switchlights "off"
      }
      server::setdata "timestamp" [utcclock::combinedformat now]   
      log::info [format "finished initializing after %.1f seconds." [utcclock::diff now $start]]
    } message]} {
      log::error "unable to initialize: $message"
      emergencyclose
      error "unable to initialize."
    }
  }
  
  proc openactivitycommand {} {
    set start [utcclock::seconds]    
    log::info "opening."
    variable withlights
    variable withheater
    variable withmount
    variable withdome
    variable withenclosure
    variable withcovers
    variable withguider
    variable finders
    variable idleha
    variable idledelta
    if {[catch {
      if {$withlights} {
        switchlights "on"
      }
      if {$withheater} {
        switchheater "off"
      }
      openprolog
      if {$withguider} {
        log::info "stopping guider."
        client::request "guider" "stop"
      }
      foreach finder $finders {
        log::info "cooling $finder."
        client::request $finder "setcooler open"
      }
      if {$withmount} {
        log::info "parking mount."
        client::request "mount" "preparetomove"
        client::wait "mount"
      }
      client::request "target" "move $idleha $idledelta"
      client::wait "target"
      if {$withmount} {
        client::request "mount" "park"
        client::wait "mount"
      }
      foreach finder $finders {
        log::info "cooling $finder."
        client::request $finder "setcooler open"
      }
      if {$withdome} {
        movedomeforshutter
        log::info "opening shutters."
        client::request "shutters" "open"
        client::wait "shutters"  
      }
      if {$withenclosure} {
        log::info "opening enclosure."
        client::request "enclosure" "open"
        client::wait "enclosure"
      }
      if {$withcovers} {
        log::info "opening covers."
        client::request "covers" "open"
        client::wait "covers"
      }
      if {$withmount} {
        log::info "unparking mount."
        client::request "mount" "preparetomove"
        client::wait "mount"
      }
      client::request "target" "move $idleha $idledelta"
      client::wait "target"
      if {$withmount} {      
        client::request "mount" "unpark"
        client::wait "mount"
      }
      openepilog
      if {$withlights} {
        switchlights "off"
      }
      server::setdata "timestamp" [utcclock::combinedformat now]    
      log::info [format "finished opening after %.1f seconds." [utcclock::diff now $start]]
    } message]} {
      log::error "unable to open: $message"
      emergencyclose
      error "unable to open."
    }
  }

  proc opentocoolactivitycommand {} {
    set start [utcclock::seconds]    
    log::info "opening to cool."
    variable withlights
    variable withheater
    variable withmount
    variable withdome
    variable withenclosure
    variable withcovers
    variable withguider
    variable finders
    variable idleha
    variable idledelta
    if {[catch {
      if {$withlights} {
        switchlights "on"
      }
      if {$withheater} {
        switchheater "off"
      }
      openprolog
      if {$withguider} {
        log::info "stopping guider."
        client::request "guider" "stop"
      }
      foreach finder $finders {
        log::info "cooling $finder."
        client::request $finder "setcooler open"
      }
      if {$withmount} {
        log::info "parking mount."
        client::request "mount" "preparetomove"
        client::wait "mount"
      }
      client::request "target" "move $idleha $idledelta"
      client::wait "target"
      if {$withmount} {
        client::request "mount" "park"
        client::wait "mount"
      }
      foreach finder $finders {
        log::info "cooling $finder."
        client::request $finder "setcooler open"
      }
      if {$withdome} {
        movedomeforshutter
        log::info "opening shutters."
        client::request "shutters" "open"
        client::wait "shutters"
        log::info "parking dome."
        client::request "dome" "preparetomove"
        client::request "dome" "park"
        client::wait "dome"
      }
      if {$withenclosure} {
        log::info "opening enclosure to cool."
        client::request "enclosure" "opentocool"
        client::wait "enclosure"
      }
      if {$withcovers} {
        log::info "opening covers."
        client::request "covers" "open"
        client::wait "covers"
      }
      openepilog
      if {$withlights} {
        switchlights "off"
      }
      server::setdata "timestamp" [utcclock::combinedformat now]    
      log::info [format "finished opening to cool after %.1f seconds." [utcclock::diff now $start]]
    } message]} {
      log::error "unable to open to cool: $message"
      emergencyclose
      error "unable to open to cool"
    }
  }

  proc closeactivitycommand {} {
    set start [utcclock::seconds]        
    log::info "closing."
    variable withlights
    variable withheater
    variable withmount
    variable withdome
    variable withenclosure
    variable withcovers
    variable withguider
    variable finders
    variable idleha
    variable idledelta
    if {[catch {
      if {$withlights} {
        switchlights "on"
      }
      closeprolog
      if {$withguider} {
        log::info "stopping guider."
        client::request "guider" "stop"
      }
      foreach finder $finders {
        log::info "stopping cooling $finder."
        client::request $finder "setcooler closed"
      }
      if {$withmount} {
        log::info "parking mount."
        client::request "mount" "preparetomove"
        client::wait "mount"
      }
      client::request "target" "move $idleha $idledelta"
      client::wait "target"
      if {$withmount} {
        client::request "mount" "park"
        client::wait "mount"
      }
      if {$withcovers} {
        log::info "closing covers."
        client::request "covers" "close"
        client::wait "covers" 
      }
      variable closeexplicitly
      if {$closeexplicitly} {
        if {$withdome} {
          movedomeforshutter
          log::info "closing shutters."
          client::request "shutters" "close"
          client::wait "shutters"
          log::info "parking dome."
          client::request "dome" "preparetomove"
          client::request "dome" "park"
          client::wait "dome"
        }
        if {$withenclosure} {
          log::info "closing enclosure."
          client::request "enclosure" "close"
          client::wait "enclosure"
        }
      }
      closeepilog
      if {$withheater} {
        switchheater "automatically"
      }
      if {$withlights} {
        switchlights "off"
      }
      server::setdata "timestamp" [utcclock::combinedformat now]
      log::info [format "finished closing after %.1f seconds." [utcclock::diff now $start]]
    } message]} {
      log::error "unable to close: $message"
      emergencyclose
      error "unable to close."
    }
  }
  
  proc emergencycloseactivitycommand {} {
    set start [utcclock::seconds]
    log::info "emergency closing."
    variable withdome
    variable withenclosure
    variable closeexplicitly
    catch {
      if {$closeexplicitly} {
        if {$withdome} {
          catch {client::request "dome" "reset"}
          movedomeforshutter
          log::info "closing shutters."
          catch {client::request "shutters" "reset"}
          client::request "shutters" "emergencyclose"
          client::wait "shutters"  
        }
        if {$withenclosure} {
          log::info "closing enclosure."
          catch {client::request "enclosure" "reset"}
          client::request "enclosure" "emergencyclose"
          client::wait "enclosure"
        }
      }
    }
    closeactivitycommand
    server::setdata "timestamp" [utcclock::combinedformat now]
    log::info [format "finished emergency closing after %.1f seconds." [utcclock::diff now $start]]
  }

  proc moveactivitycommand {ha delta} {
    set start [utcclock::seconds]
    log::info [format \
      "moving to %s %s." \
      [astrometry::formatha $ha] \
      [astrometry::formatdelta $delta] \
    ]
    variable withmount
    variable withdome
    variable withguider
    if {$withguider} {
      log::info "stopping guider."
      client::request "guider" "stop"
    }
    if {$withmount} {
      client::request "mount" "preparetomove"
      client::wait "mount"
    }
    if {$withdome} {
      client::request "dome" "preparetomove"
      client::wait "dome"
    }
    client::request "target" "move $ha $delta"
    client::wait "target"
    if {![client::getdata "target" "withinlimits"]} {
      log::error "the target is not within the limits."
      if {$withmount} {
        client::request "mount" "stop"
        client::wait "mount"
      }
      if {$withdome} {
        client::request "dome" "stop"
        client::wait "dome"
      }
      return
    }
    if {$withmount} {
      client::request "mount" "move"
    }
    if {$withdome} {
      client::request "dome" "move"
    }
    variable withsecondary
    if {$withsecondary} {
      client::request "secondary" "movewithoutcheck z0"
    }
    if {$withmount} {
      client::wait "mount"
    }
    if {$withsecondary} {
      client::wait "secondary"
      client::request "secondary" "move z0"
      client::wait "secondary"
    }
    if {$withdome} {
        client::wait "dome"
    }
    log::info [format "finished moving after %.1f seconds." [utcclock::diff now $start]]
  }

  proc parkactivitycommand {} {
    set start [utcclock::seconds]
    log::info "parking."
    variable withmount
    variable withdome
    variable withguider
    variable idleha
    variable idledelta
    if {$withguider} {
      log::info "stopping guider."
      client::request "guider" "stop"
    }
    if {$withmount} {
      client::request "mount" "preparetomove"
      client::wait "mount"
    }
    if {$withdome} {
      client::request "dome" "preparetomove"
      client::wait "dome"  
    }
    client::request "target" "move $idleha $idledelta"
    client::wait "target"
    if {$withmount} {
      log::info "parking mount."
      client::request "mount" "park"
    }
    if {$withdome} {
      log::info "parking dome."
      client::request "dome" "park"
      client::wait "dome"
    }
    if {$withmount} {
      client::wait "mount"
    }
    log::info [format "finished parking after %.1f seconds." [utcclock::diff now $start]]
  }

  proc unparkactivitycommand {} {
    set start [utcclock::seconds]
    log::info "unparking."
    variable withmount
    variable withdome
    variable withguider
    variable idleha
    variable idledelta
    if {$withguider} {
      log::info "stopping guider."
      client::request "guider" "stop"
    }
    if {$withdome} {
      client::request "dome" "stop"
      client::wait "dome"  
    }
    if {$withmount} {
      client::request "mount" "preparetomove"
      client::wait "mount"
    }
    client::request "target" "move $idleha $idledelta"
    client::wait "target"
    if {$withmount} {
      client::request "mount" "unpark"
      client::wait "mount"
    }
    log::info [format "finished unparking after %.1f seconds." [utcclock::diff now $start]]
  }

  variable lastalphaoffset
  variable lastdeltaoffset
  variable lastaperture
  variable lastguidingmode  
  
  proc trackactivitycommand {alpha delta equinox alphaoffset deltaoffset epoch alpharate deltarate aperture} {
    set start [utcclock::seconds]
    log::info [format \
      "moving to track %s %s %s %s %s %s %s %s at aperture %s." \
      [astrometry::formatalpha $alpha] \
      [astrometry::formatdelta $delta] \
      $equinox \
      [astrometry::formatoffset $alphaoffset] \
      [astrometry::formatoffset $deltaoffset] \
      $epoch \
      [astrometry::formatrate $alpharate] \
      [astrometry::formatrate $deltarate] \
      $aperture \
    ]
    variable withmount
    variable withdome
    variable withguider
    set pointingmode [server::getdata "pointingmode"]
    set guidingmode  [server::getdata "guidingmode"]
    if {$withguider} {
      log::info "stopping guider."
      client::request "guider" "stop"
    }
    if {$withmount} {
      client::request "mount" "preparetotrack"
      client::wait "mount"
    }
    if {$withdome} {
      client::request "dome" "preparetotrack"
      client::wait "dome"
    }
    client::request "target" "track $alpha $delta $equinox $alphaoffset $deltaoffset $epoch $alpharate $deltarate $aperture"
    client::wait "target"
    if {![client::getdata "target" "withinlimits"]} {
      log::warning "the target is not within the limits."
      if {$withmount} {
        client::request "mount" "stop"
        client::wait "mount"
      }
      if {$withdome} {
        client::request "dome" "stop"
        client::wait "dome"
      }
      return
    }
    if {$withmount} {
      client::request "mount" "track"
    }
    if {$withdome} {
      client::request "dome" "track"
    }
    variable withsecondary
    if {$withsecondary} {
      client::request "secondary" "movewithoutcheck z0"
    }
    if {$withmount} {
      client::wait "mount"
    }
    if {$withsecondary} {
      client::wait "secondary"
      client::request "secondary" "move z0"
      client::wait "secondary"
    }
    if {$withdome} {
        client::wait "dome"
    }
    if {$withmount} {
      maybecorrectpointing
      maybeguide
    }
    variable lastalphaoffset
    variable lastdeltaoffset
    variable lastaperture
    variable lastguidingmode
    set lastalphaoffset $alphaoffset
    set lastdeltaoffset $deltaoffset
    set lastaperture    $aperture
    set lastguidingmode $guidingmode
    log::info [format "finished moving and started tracking after %.1f seconds." [utcclock::diff now $start]]
    log::info "tracking."
  }
  
  proc offsetactivitycommand {alphaoffset deltaoffset aperture} {
    set start [utcclock::seconds]
    log::info [format \
      "offsetting to %s %s at aperture %s." \
      [astrometry::formatoffset $alphaoffset] \
      [astrometry::formatoffset $deltaoffset] \
      $aperture \
    ]
    variable withmount
    variable withguider
    variable withsecondary
    set pointingmode [server::getdata "pointingmode"]
    set guidingmode  [server::getdata "guidingmode"]
    if {$withguider} {
      log::info "stopping guider."
      client::request "guider" "stop"
    }
    if {$withmount} {
      client::request "mount" "preparetotrack"
      client::wait "mount"
    }
    client::request "target" "offset $alphaoffset $deltaoffset $aperture"
    client::wait "target"
    if {![client::getdata "target" "withinlimits"]} {
      log::warning "the target is not within the limits."
      if {$withmount} {
        client::request "mount" "stop"
        client::wait "mount"
      }
      return
    }
    if {$withmount} {
      client::request "mount" "offset"
    }
    if {$withsecondary} {
      client::request "secondary" "move z0"
    }
    client::wait "mount"
    if {$withsecondary} {
      client::wait "secondary"
    }
    if {$withmount} {
      maybeguide
    }
    variable lastalphaoffset
    variable lastdeltaoffset
    variable lastaperture
    variable lastguidingmode
    set lastalphaoffset $alphaoffset
    set lastdeltaoffset $deltaoffset
    set lastaperture    $aperture
    set lastguidingmode $guidingmode
    log::info [format "finished offsetting and started tracking after %.1f seconds." [utcclock::diff now $start]]
    log::info "tracking."
  }
  
  ######################################################################

  proc focusfindersactivitycommand {exposuretime range step} {
    set start [utcclock::seconds]
    log::info "focusing finders."
    variable finders
    client::request "guider" "stop"
    foreach finder $finders {
      client::request $finder "stop"
    }
    foreach finder $finders {
      client::wait $finder
    }
    foreach finder $finders {
      client::request $finder "focus $exposuretime $range $step"
    }
    foreach finder $finders {
      client::wait $finder
    }
    set guidingmode [server::getdata "guidingmode"]
    if {![string equal $guidingmode "none"]} {
      client::request "guider" "guide $guidingmode"
    }
    log::info [format "finished focusing finders after %.1f seconds." [utcclock::diff now $start]]
  }
  
  ######################################################################

  proc focusfinders {exposuretime range step} {
    server::checkstatus
    server::checkactivity "tracking"
    server::newactivitycommand "focusing" "tracking" \
      "telescope::focusfindersactivitycommand $exposuretime $range $step" false
  }
  
  proc setpointingmode {mode} {
set mode "none"
    server::checkstatus
    variable validpointingmodes
    if {[lsearch $validpointingmodes $mode] == -1} {
      error "invalid pointing mode \"$mode\"."
    }
    set start [utcclock::seconds]
    log::info "setting pointing mode to \"$mode\"."
    server::setdata "pointingmode" $mode
    server::setdata "timestamp" [utcclock::combinedformat now]
    log::info [format "finished setting pointing aperture after %.1f seconds." [utcclock::diff now $start]]
    return
  }
  
  proc setpointingtolerance {tolerance} {
    server::checkstatus
    set start [utcclock::seconds]
    log::info "setting pointing tolerance to $tolerance."
    server::setdata "pointingtolerance" [astrometry::parseangle $tolerance dms]
    server::setdata "timestamp" [utcclock::combinedformat now]
    log::info [format "finished setting pointing tolerance after %.1f seconds." [utcclock::diff now $start]]
    return
  }
  
  proc setguidingmode {mode} {
    server::checkstatus
    variable validguidingmodes
    if {[lsearch $validguidingmodes $mode] == -1} {
      error "invalid guiding mode $mode."
    }
    set start [utcclock::seconds]
    log::info "setting guiding mode to \"$mode\"."
    server::setdata "guidingmode" $mode
    server::setdata "timestamp" [utcclock::combinedformat now]
    log::info [format "finished setting guiding mode after %.1f seconds." [utcclock::diff now $start]]
    return
  }
  
  proc track {alpha delta equinox alphaoffset deltaoffset {epoch "now"} {alpharate 0} {deltarate 0} {aperture "default"}} {
    server::checkstatus
    server::checkactivity "moving" "idle" "tracking"
    astrometry::parsealpha   $alpha
    astrometry::parsedelta   $delta
    astrometry::parseequinox $equinox
    astrometry::parseoffset  $alphaoffset
    astrometry::parseoffset  $deltaoffset
    astrometry::parseepoch   $epoch
    astrometry::parserate    $alpharate
    astrometry::parserate    $deltarate
    pointing::checkaperture $aperture
    server::newactivitycommand "moving" "tracking" \
      "telescope::trackactivitycommand $alpha $delta $equinox $alphaoffset $deltaoffset $epoch $alpharate $deltarate $aperture"
  }
  
  proc trackcatalogobject {catalogname objectname aperture} {
    variable catalogdirectory
    set channel [::open "|[directories::bin]/tcs getcatalogobject -d \"$catalogdirectory\" -- \"$catalogname\" \"$objectname\"" "r"]
    set line [coroutine::gets $channel]
    catch {::close $channel}
    if {[string equal $line ""]} {
      error "object \"$objectname\" not found in catalog \"$catalogname\"."
    }
    eval track $line 0 0 now 0 0 $aperture
  }
  
  proc tracktopocentric {ha delta aperture} {
    set ha    [astrometry::parseha $ha]
    set alpha [astrometry::formatalpha [astrometry::alpha $ha]]
    set delta [astrometry::formatdelta [astrometry::parsedelta $delta]]
    track $alpha $delta now 0 0 now 0 0 $aperture  
  }
  
  proc offset {alphaoffset deltaoffset aperture} {
    server::checkstatus
    server::checkactivity "tracking"
    astrometry::parseoffset $alphaoffset
    astrometry::parseoffset $deltaoffset
    pointing::checkaperture $aperture
    server::newactivitycommand "moving" "tracking" \
      "telescope::offsetactivitycommand $alphaoffset $deltaoffset $aperture"
  }
  
  proc correct {truemountalpha truemountdelta equinox} {
    server::checkstatus
    astrometry::parsealpha $truemountalpha
    astrometry::parsedelta $truemountdelta
    astrometry::parseequinox $equinox
    log::info "correcting the pointing model."
    set start [utcclock::seconds]
    variable withmount
    if {$withmount} {
      client::request "mount" "correct $truemountalpha $truemountdelta $equinox"
    }
    log::info [format "finished correcting the pointing model after %.1f seconds." [utcclock::diff now $start]]
  }

  ######################################################################

  proc reset {} {
    server::checkstatus
    server::checkactivitynot "starting"
    server::newactivitycommand "resetting" [server::getstoppedactivity] \
      "telescope::resetactivitycommand" 1200e3
  }
  
  proc recover {} {
    server::checkstatus
    server::checkactivitynot "starting"
    server::newactivitycommand "recovering" "idle" \
      "telescope::recoveractivitycommand" 1200e3
  }
  
  proc stop {} {
    server::checkstatus
    server::checkactivitynot "starting" "error"
    server::newactivitycommand "stopping" [server::getstoppedactivity] \
      "telescope::stopactivitycommand"
  }
  
  proc initialize {} {
    server::checkstatus
    server::checkactivitynot "starting" "error"
    safetyswitch::checksafetyswitch
    server::newactivitycommand "initializing" "idle" \
      "telescope::initializeactivitycommand" 1200e3
  }
  
  proc open {} {
    server::checkstatus
    server::checkactivity "idle"
    safetyswitch::checksafetyswitch
    server::newactivitycommand "opening" "idle" \
      "telescope::openactivitycommand" 1200e3
  }
  
  proc opentocool {} {
    server::checkstatus
    server::checkactivity "idle"
    safetyswitch::checksafetyswitch
    server::newactivitycommand "opening" "idle" \
      "telescope::opentocoolactivitycommand" 1200e3
  }
  
  proc close {} {
    server::checkstatus
    server::checkactivity "stopping" "moving" "tracking" "focusing" "idle"
    safetyswitch::checksafetyswitch
    server::newactivitycommand "closing" "idle" \
     telescope::closeactivitycommand 1200e3
  }
  
  proc emergencyclose {} {
    # Do not check status or activity.
    safetyswitch::checksafetyswitch
    server::newactivitycommand "closing" [server::getstoppedactivity] \
      telescope::emergencycloseactivitycommand 1200e3
  }
  
  proc move {ha delta} {
    server::checkstatus
    server::checkactivity "moving" "tracking" "idle"
    safetyswitch::checksafetyswitch
    astrometry::parseha $ha
    astrometry::parsedelta $delta
    server::newactivitycommand "moving" "idle" \
      "telescope::moveactivitycommand $ha $delta"
  }
  
  proc movetoidle {} {
    log::info "moving to idle."
    variable idleha
    variable idledelta
    move $idleha $idledelta
  }
  
  proc movetozenith {} {
    log::info "moving to idle."
    variable idleha
    variable idledelta
    move 0h [astrometry::formatdelta [astrometry::latitude]]
  }
  
  proc park {} {
    server::checkstatus
    server::checkactivity "moving" "tracking" "idle"
    safetyswitch::checksafetyswitch
    log::info "parking"
    server::newactivitycommand "parking" "idle" \
      "telescope::parkactivitycommand"
  }
  
  proc unpark {} {
    server::checkstatus
    server::checkactivity "moving" "tracking" "idle"
    safetyswitch::checksafetyswitch
    log::info "unparking"
    server::newactivitycommand "unparking" "idle" \
      "telescope::unparkactivitycommand"
  }
  
  proc movesecondary {z0 setasinitial} {
    variable withsecondary
    if {!$withsecondary} {
      error "the telescope does not have a secondary."
    }
    server::checkstatus
    server::checkactivity "idle" "tracking"
    safetyswitch::checksafetyswitch
    server::newactivitycommand "moving" [server::getactivity] \
      "telescope::movesecondaryactivitycommand $z0 $setasinitial"
  }

  proc setsecondaryoffset {dz} {
    variable withsecondary
    if {$withsecondary} {
      server::checkstatus
      server::checkactivity "idle" "tracking"
      safetyswitch::checksafetyswitch
      server::newactivitycommand "setting" [server::getactivity] \
        "telescope::setsecondaryoffsetactivitycommand $dz"
    } else {
      return
    }
  }

  set server::datalifeseconds 0

  proc start {} {
    server::setstatus "ok"
    server::newactivitycommand "starting" "started" \
      telescope::startactivitycommand 1200000
  }

}
