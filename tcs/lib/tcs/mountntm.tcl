########################################################################

# This file is part of the UNAM telescope control system.

# $Id: mountntm.tcl 3601 2020-06-11 03:20:53Z Alan $

########################################################################

# Copyright © 2017, 2018, 2019 Alan M. Watson <alan@astro.unam.mx>
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
package require "controller"
package require "client"
package require "log"
package require "pointing"
package require "server"

package provide "mountntm" 0.0

config::setdefaultvalue "mount" "controllerhost"             "mount"
config::setdefaultvalue "mount" "controllerport"             65432
config::setdefaultvalue "mount" "initialcommand"             ""

source [file join [directories::prefix] "lib" "tcs" "mount.tcl"]

config::setdefaultvalue "mount" "allowedpositionerror"       "4as"
config::setdefaultvalue "mount" "pointingmodelparameters0"   [dict create]
config::setdefaultvalue "mount" "pointingmodelID0"           "0"
config::setdefaultvalue "mount" "pointingmodelIH0"           "0"
config::setdefaultvalue "mount" "pointingmodelparameters180" [dict create]
config::setdefaultvalue "mount" "pointingmodelID180"         "0"
config::setdefaultvalue "mount" "pointingmodelIH180"         "0"
config::setdefaultvalue "mount" "allowedguideoffset"         "30as"
config::setdefaultvalue "mount" "trackingsettledlimit"       "1as"
config::setdefaultvalue "mount" "axisdhacorrection"          "0"
config::setdefaultvalue "mount" "axisddeltacorrection"       "0"
config::setdefaultvalue "mount" "easthalimit"                "-12h"
config::setdefaultvalue "mount" "westhalimit"                "+12h"
config::setdefaultvalue "mount" "westhalimit"                "+12h"
config::setdefaultvalue "mount" "meridianhalimit"            "0"
config::setdefaultvalue "mount" "northdeltalimit"            "+90d"
config::setdefaultvalue "mount" "southdeltalimit"            "-90d"
config::setdefaultvalue "mount" "polardeltalimit"            "0"
config::setdefaultvalue "mount" "zenithdistancelimit"        "90d"
config::setdefaultvalue "mount" "hapark"                     "0h"
config::setdefaultvalue "mount" "deltapark"                  "90h"
config::setdefaultvalue "mount" "haunpark"                   "0h"
config::setdefaultvalue "mount" "deltaunpark"                "0d"
config::setdefaultvalue "mount" "maxcorrection"              "1d"

namespace eval "mount" {

  variable svnid {$Id}

  ######################################################################

  variable controllerhost              [config::getvalue "mount" "controllerhost"]
  variable controllerport              [config::getvalue "mount" "controllerport"]
  variable initialcommand              [config::getvalue "mount" "initialcommand"]
  variable allowedpositionerror        [astrometry::parseangle [config::getvalue "mount" "allowedpositionerror"]]
  variable pointingmodelpolarhole      [astrometry::parsedistance [config::getvalue "mount" "pointingmodelpolarhole"]]
  variable allowedguideoffset          [astrometry::parseoffset [config::getvalue "mount" "allowedguideoffset"]]
  variable axisdhacorrection           [astrometry::parseoffset [config::getvalue "mount" "axisdhacorrection"]]
  variable axisddeltacorrection        [astrometry::parseoffset [config::getvalue "mount" "axisddeltacorrection"]]
  variable trackingsettledlimit        [astrometry::parseoffset [config::getvalue "mount" "trackingsettledlimit"]]
  variable easthalimit                 [astrometry::parseha    [config::getvalue "mount" "easthalimit"]]
  variable westhalimit                 [astrometry::parseha    [config::getvalue "mount" "westhalimit"]]
  variable meridianhalimit             [astrometry::parseha    [config::getvalue "mount" "meridianhalimit"]]
  variable northdeltalimit             [astrometry::parsedelta [config::getvalue "mount" "northdeltalimit"]]
  variable southdeltalimit             [astrometry::parsedelta [config::getvalue "mount" "southdeltalimit"]]
  variable polardeltalimit             [astrometry::parsedelta [config::getvalue "mount" "polardeltalimit"]]
  variable zenithdistancelimit         [astrometry::parseangle [config::getvalue "mount" "zenithdistancelimit"]]
  variable hapark                      [astrometry::parseangle [config::getvalue "mount" "hapark"]]
  variable deltapark                   [astrometry::parseangle [config::getvalue "mount" "deltapark"]]
  variable haunpark                    [astrometry::parseangle [config::getvalue "mount" "haunpark"]]
  variable deltaunpark                 [astrometry::parseangle [config::getvalue "mount" "deltaunpark"]]
  variable maxcorrection               [astrometry::parseangle [config::getvalue "mount" "maxcorrection"]]

  ######################################################################

  variable pointingmodelparameters0   [config::getvalue "mount" "pointingmodelparameters0"]
  set pointingmodelparameters0 [pointing::setparameter $pointingmodelparameters0 "ID" [config::getvalue "mount" "pointingmodelID0"]]
  set pointingmodelparameters0 [pointing::setparameter $pointingmodelparameters0 "IH" [config::getvalue "mount" "pointingmodelIH0"]]

  variable pointingmodelparameters180 [config::getvalue "mount" "pointingmodelparameters180"]
  set pointingmodelparameters180 [pointing::setparameter $pointingmodelparameters180 "ID" [config::getvalue "mount" "pointingmodelID180"]]
  set pointingmodelparameters180 [pointing::setparameter $pointingmodelparameters180 "IH" [config::getvalue "mount" "pointingmodelIH180"]]

  ######################################################################

  # We use command identifiers 1 for status command, 2 for emergency
  # stop, and 3-99 for normal commands,

  variable statuscommandidentifier        1
  variable emergencystopcommandidentifier 2
  variable firstnormalcommandidentifier   3
  variable lastnormalcommandidentifier    99

  ######################################################################

  set controller::host                        $controllerhost
  set controller::port                        $controllerport
  set controller::connectiontype              "persistent"
  set controller::statuscommand "$statuscommandidentifier GET [join {
    HA.REALPOS
    HA.TARGETDISTANCE
    HA.MOTION_STATE
    HA.TRAJECTORY.RUN
    HA.TRAJECTORY.FREEPOINTS
    HA.REFERENCED
    HA.ERROR_STATE
    DEC.REALPOS
    DEC.TARGETDISTANCE
    DEC.MOTION_STATE
    DEC.TRAJECTORY.RUN
    DEC.TRAJECTORY.FREEPOINTS
    DEC.REFERENCED
    DEC.ERROR_STATE
    LOCAL.REFERENCED
    CABINET.ERROR_STATE
    CABINET.POWER_STATE
    CABINET.REFERENCED
    CABINET.STATUS.LIST
    } ";"]\n"
  set controller::timeoutmilliseconds         10000
  set controller::intervalmilliseconds        50
  set controller::updatedata                  mount::updatecontrollerdata
  set controller::statusintervalmilliseconds  200

  set server::datalifeseconds                 30

  ######################################################################

  server::setdata "mounttracking"              "unknown"
  server::setdata "mountha"                     ""
  server::setdata "mountalpha"                  ""
  server::setdata "mountdelta"                  ""
  server::setdata "axismeanhatrackingerror"     ""
  server::setdata "axismeandeltatrackingerror"  ""
  server::setdata "mountmeaneasttrackingerror"  ""
  server::setdata "mountmeannorthtrackingerror" ""
  server::setdata "mountrmseasttrackingerror"   ""
  server::setdata "mountrmsnorthtrackingerror"  ""
  server::setdata "mountpveasttrackingerror"    ""
  server::setdata "mountpvnorthtrackingerror"   ""
  server::setdata "mountazimuth"                ""
  server::setdata "mountzenithdistance"         ""
  server::setdata "mountrotation"               ""
  server::setdata "state"                       ""
  server::setdata "timestamp"                   ""
  server::setdata "lastcorrectiontimestamp"     ""
  server::setdata "lastcorrectiondalpha"        ""
  server::setdata "lastcorrectionddelta"        ""

  variable hamotionstate    ""
  variable deltamotionstate ""

  variable haaxismoving        true
  variable deltaaxismoving     true
  variable haaxistrajectory    false
  variable deltaaxistrajectory false
  variable haaxisblocked       false
  variable deltaaxisblocked    false
  variable haaxisacquired      false
  variable deltaaxisacquired   false
  variable haaxislimited       false
  variable deltaaxislimited    false
  variable haaxistracking      false
  variable deltaaxistracking   false
  variable moving              true
  variable waitmoving          true
  variable tracking            false
  variable forcenottracking    true
  variable waittracking        false
  variable trackingtimestamp   ""
  variable settling            false
  variable settlingtimestamp   ""
  variable cabinetstatuslist   ""
  variable cabinetpowerstate   ""
  variable cabineterrorstate   ""
  variable cabinetreferenced   ""
  variable haaxisreferenced    ""
  variable deltaaxisreferenced ""
  variable gpsreferenced       ""
  variable state               ""
  variable freepoints          0

  proc isignoredcontrollerresponse {controllerresponse} {
    expr {
      [regexp {TPL2 OpenTPL-1.99-pl2 CONN [0-9]+ AUTH ENC TLS MESSAGE Welcome .*} $controllerresponse] == 1 ||
      [string equal {AUTH OK 0 0} $controllerresponse] ||
      [regexp {^[0-9]+ COMMAND OK}  $controllerresponse] == 1 ||
      [regexp {^[0-9]+ DATA OK}     $controllerresponse] == 1 ||
      [regexp {^[0-9]+ EVENT INFO } $controllerresponse] == 1
    }
  }

  variable pendingtracking
  variable pendingaxisha
  variable pendingaxishaseconds
  variable pendingaxisdelta
  variable pendingaxisdha
  variable pendingaxisddelta
  variable pendinghamotionstate
  variable pendingdeltamotionstate
  variable pendingcabinetstatuslist
  variable pendingcabineterrorstate
  variable pendingcabinetpowerstate
  variable pendingcabinetreferenced
  variable pendinghafreepoints
  variable pendingdeltafreepoints

  proc updatecontrollerdata {controllerresponse} {

    variable pendingtracking
    variable pendingaxisha
    variable pendingaxishaseconds
    variable pendingaxisdelta
    variable pendingaxisdha
    variable pendingaxisddelta
    variable pendinghamotionstate
    variable pendingdeltamotionstate
    variable pendingcabinetstatuslist
    variable pendingcabineterrorstate
    variable pendingcabinetpowerstate
    variable pendingcabinetreferenced
    variable pendinghafreepoints
    variable pendingdeltafreepoints

    variable haaxismoving
    variable deltaaxismoving
    variable haaxistrajectory
    variable deltaaxistrajectory
    variable haaxisblocked
    variable deltaaxisblocked
    variable haaxisacquired
    variable deltaaxisacquired
    variable haaxislimited
    variable deltaaxislimited
    variable haaxistracking
    variable deltaaxistracking
    variable moving
    variable waitmoving
    variable tracking
    variable forcenottracking
    variable waittracking
    variable trackingtimestamp
    variable settling
    variable settlingtimestamp
    variable cabinetstatuslist
    variable cabinetpowerstate
    variable cabineterrorstate
    variable cabinetreferenced
    variable state
    variable freepoints

    variable trackingsettledlimit

    set controllerresponse [string trim $controllerresponse]
    set controllerresponse [string trim $controllerresponse "\0"]

    if {[isignoredcontrollerresponse $controllerresponse]} {
      return false
    }

    if {
      [regexp {^[0-9]+ EVENT ERROR } $controllerresponse] == 1 ||
      [regexp {^[0-9]+ DATA ERROR } $controllerresponse] == 1
    } {
      log::warning "controller error: \"$controllerresponse\"."
      return false
    }

    if {![scan $controllerresponse "%d " commandidentifier] == 1} {
      log::warning "unexpected controller response \"$controllerresponse\"."
      return true
    }

    variable statuscommandidentifier
    variable emergencystopcommandidentifier
    variable completedcommandidentifier

    if {$commandidentifier == $emergencystopcommandidentifier} {
      log::debug "controller response \"$controllerresponse\"."
      if {[regexp {^[0-9]+ COMMAND COMPLETE} $controllerresponse] == 1} {
        finishemergencystop
        return false
      }
    }

    if {$commandidentifier != $statuscommandidentifier} {
      variable currentcommandidentifier
      variable completedcurrentcommand
      log::debug "controller response \"$controllerresponse\"."
      if {[regexp {^[0-9]+ COMMAND COMPLETE} $controllerresponse] == 1} {
        log::debug [format "controller command %d completed." $commandidentifier]
        if {$commandidentifier == $currentcommandidentifier} {
          log::debug "current controller command completed."
          set completedcurrentcommand true
        }
      }
      return false
    }

    #log::debug "status: controller response \"$controllerresponse\"."
    if {[scan $controllerresponse "%*d DATA INLINE CABINET.ERROR_STATE=%d" value] == 1} {
      set pendingcabineterrorstate $value
      return false
    }
    if {[scan $controllerresponse "%*d DATA INLINE CABINET.POWER_STATE=%f" value] == 1} {
      set pendingcabinetpowerstate $value
      return false
    }
    if {[scan $controllerresponse "%*d DATA INLINE CABINET.STATUS.LIST=%s" value] == 1} {
      set pendingcabinetstatuslist [string trim $value "\""]
      return false
    }
    if {[scan $controllerresponse "%*d DATA INLINE CABINET.REFERENCED=%f" value] == 1} {
      set pendingcabinetreferenced $value
      return false
    }
    if {[scan $controllerresponse "%*d DATA INLINE HA.REFERENCED=%f" value] == 1} {
      variable haaxisreferenced
      if {[string equal $haaxisreferenced ""] || $value != $haaxisreferenced} {
        if {$value == 1} {
          log::info "the HA axis is referenced."
        } else {
          log::info "the HA axis is not referenced."
        }
      }
      set haaxisreferenced $value
      return false
    }
    if {[scan $controllerresponse "%*d DATA INLINE DEC.REFERENCED=%f" value] == 1} {
      variable deltaaxisreferenced
      if {[string equal $deltaaxisreferenced ""] || $value != $deltaaxisreferenced} {
        if {$value == 1} {
          log::info "the δ axis is referenced."
        } else {
          log::info "the δ axis is not referenced."
        }
      }
      set deltaaxisreferenced $value
      return false
    }
    if {[scan $controllerresponse "%*d DATA INLINE LOCAL.REFERENCED=%f" value] == 1} {
      variable gpsreferenced
      if {[string equal $gpsreferenced ""] || $value != $gpsreferenced} {
        if {$value == 1} {
          log::info "the GPS is referenced."
        } else {
          log::info "the GPS is not referenced."
        }
      }
      set gpsreferenced $value
      return false
    }
    if {[scan $controllerresponse "%*d DATA INLINE HA.REALPOS=%f" value] == 1} {
      set pendingaxisha [astrometry::degtorad $value]
      set pendingaxishaseconds [utcclock::seconds]
      return false
    }
    if {[scan $controllerresponse "%*d DATA INLINE DEC.REALPOS=%f" value] == 1} {
      set pendingaxisdelta [astrometry::degtorad $value]
      return false
    }
    if {[scan $controllerresponse "%*d DATA INLINE HA.TARGETDISTANCE=%f" value] == 1} {
      variable axisdhacorrection
      set pendingaxisdha [expr {[astrometry::degtorad $value] - $axisdhacorrection}]
      return false
    }
    if {[scan $controllerresponse "%*d DATA INLINE DEC.TARGETDISTANCE=%f" value] == 1} {
      variable axisddeltacorrection
      set pendingaxisddelta [expr {[astrometry::degtorad $value] - $axisddeltacorrection}]
      return false
    }
    if {[scan $controllerresponse "%*d DATA INLINE HA.MOTION_STATE=%d" value] == 1} {
      set pendinghamotionstate $value
      return false
    }
    if {[scan $controllerresponse "%*d DATA INLINE DEC.MOTION_STATE=%d" value] == 1} {
      set pendingdeltamotionstate $value
      return false
    }
    if {[scan $controllerresponse "%*d DATA INLINE HA.TRAJECTORY.FREEPOINTS=%d" value] == 1} {
      set pendinghafreepoints $value
      return false
    }
    if {[scan $controllerresponse "%*d DATA INLINE DEC.TRAJECTORY.FREEPOINTS=%d" value] == 1} {
      set pendingdeltafreepoints $value
      return false
    }
    if {[regexp {[0-9]+ DATA INLINE } $controllerresponse] == 1} {
      return false
    }
    if {[regexp {[0-9]+ COMMAND COMPLETE} $controllerresponse] != 1} {
      log::warning "unexpected controller response \"$controllerresponse\"."
      return true
    }

    set timestamp [utcclock::combinedformat "now"]

    if {
      ![string equal $pendingcabinetstatuslist ""] &&
      ![string equal $pendingcabinetstatuslist $cabinetstatuslist]
    } {
      if {[string equal -length [string length $cabinetstatuslist] $cabinetstatuslist $pendingcabinetstatuslist]} {
        set statuslist [string range $pendingcabinetstatuslist [string length $cabinetstatuslist] end]
      } else {
        set statuslist $pendingcabinetstatuslist
      }
      set statuslist [split $statuslist ","]
      foreach status $statuslist {
        log::warning "controller reports: \"$status\"."      
      }
    }

    set cabinetstatuslist $pendingcabinetstatuslist
    set cabineterrorstate $pendingcabineterrorstate
    set cabinetpowerstate $pendingcabinetpowerstate
    set cabinetreferenced $pendingcabinetreferenced
    
    if {$pendinghafreepoints < $pendingdeltafreepoints} {
      set freepoints $pendinghafreepoints
    } else {
      set freepoints $pendingdeltafreepoints
    }

    log::debug "state: cabineterrorstate = $cabineterrorstate."
    log::debug "state: cabinetpowerstate = $cabinetpowerstate."
    log::debug "state: cabinetreferenced = $cabinetreferenced."

    variable laststate
    set laststate $state
    if {$cabineterrorstate != 0} {
      set state "error"
    } elseif {$cabinetpowerstate == 0} {
      set state "off"
    } elseif {$cabinetpowerstate < 1 || $cabinetreferenced != 1} {
      set state "referencing"
    } else {
      set state "operational"
    }
    log::debug "state: state = $state."
    if {[string equal $laststate ""]} {
      log::info "the controller state is $state."
    } elseif {![string equal $state $laststate]} {
      if {
        [string equal $state "error"] ||
        ([string equal $laststate "operational"] && ![string equal "rebooting" [server::getdata "activity"]])
      } {
        log::error "the controller state changed from $laststate to $state."
        server::erroractivity
      } else {
        log::info "the controller state changed from $laststate to $state."
      }
    }

    if {![string equal $state "operational"]} {
      set mountrotation           0
      set mountha                 0
      set mountdelta              0
      set mounteasttrackingerror  0
      set mountnorthtrackingerror 0
      set axishatrackingerror     0
      set axisdeltatrackingerror  0
    } elseif {$pendingaxisdelta <= 0.5 * [astrometry::pi]} {
      # The mount is not flipped.
      set mountrotation           0
      set mountha                 $pendingaxisha
      set mountdelta              $pendingaxisdelta
      set mounteasttrackingerror  [expr {$pendingaxisdha * cos($mountdelta)}]
      set mountnorthtrackingerror $pendingaxisddelta
      set axishatrackingerror     $pendingaxisdha
      set axisdeltatrackingerror  $pendingaxisddelta
    } else {
      # The mount is flipped.
      set mountrotation           [astrometry::pi]
      set mountha                 [expr {$pendingaxisha - [astrometry::pi]}]
      set mountdelta              [expr {[astrometry::pi] - $pendingaxisdelta}]
      set mounteasttrackingerror  [expr {-($pendingaxisdha) * cos($mountdelta)}]
      set mounteasttrackingerror  $pendingaxisdha
      set mountnorthtrackingerror [expr {-($pendingaxisddelta)}]
      set axishatrackingerror     $pendingaxisdha
      set axisdeltatrackingerror  $pendingaxisddelta
    }
    set mounttrackingerror  [expr {sqrt(pow($mounteasttrackingerror, 2) + pow($mountnorthtrackingerror, 2))}]
    set mountha             [astrometry::foldradsymmetric $mountha]
    set mountalpha          [astrometry::foldradpositive [expr {[astrometry::last $pendingaxishaseconds] - $mountha}]]
    set mountazimuth        [astrometry::azimuth $mountha $mountdelta]
    set mountzenithdistance [astrometry::zenithdistance $mountha $mountdelta]

    variable hamotionstate
    set lasthamotionstate $hamotionstate
    set hamotionstate $pendinghamotionstate
    if {![string equal $lasthamotionstate ""] && $hamotionstate != $lasthamotionstate} {
      log::debug [format "status: the HA motion state changed from %05b to %05b." $lasthamotionstate $hamotionstate]
    }

    variable deltamotionstate
    set lastdeltamotionstate $deltamotionstate
    set deltamotionstate $pendingdeltamotionstate
    if {![string equal $lastdeltamotionstate ""] && $deltamotionstate != $lastdeltamotionstate} {
      log::debug [format "status: the δ motion state changed from %05b to %05b." $lastdeltamotionstate $deltamotionstate]
    }

    set lasthaaxismoving $haaxismoving
    if {(($hamotionstate >> 0) & 1) == 0} {
      set haaxismoving false
    } else {
      set haaxismoving true
    }
    if {$haaxismoving && !$lasthaaxismoving} {
      log::info "status: started moving in HA."
    } elseif {!$haaxismoving && $lasthaaxismoving} {
      log::info "status: stopped moving in HA."
    }

    set lasthaaxistrajectory $haaxistrajectory
    if {(($hamotionstate >> 1) & 1) == 0} {
      set haaxistrajectory false
    } else {
      set haaxistrajectory true
    }
    if {$haaxistrajectory && !$lasthaaxistrajectory} {
      log::info "status: started running a trajectory in HA."
    } elseif {!$haaxistrajectory && $lasthaaxistrajectory} {
      log::info "status: stopped running a trajectory in HA."
    }

    set lasthaaxisblocked $haaxisblocked
    if {(($hamotionstate >> 2) & 1) == 0} {
      set haaxisblocked false
    } else {
      set haaxisblocked true
    }
    if {$haaxisblocked && !$lasthaaxisblocked} {
      log::debug "status: blocked in HA."
      log::warning "blocked in HA."
    } elseif {!$haaxisblocked && $lasthaaxisblocked} {
      log::debug "status: no longer blocked in HA."
      log::info "no longer blocked in HA."
    }

    set lasthaaxisacquired $haaxisacquired
    if {(($hamotionstate >> 3) & 1) == 0} {
      set haaxisacquired false
    } else {
      set haaxisacquired true
    }
    if {$haaxisacquired && !$lasthaaxisacquired} {
      log::info "status: acquired in HA."
    } elseif {!$haaxisacquired && $lasthaaxisacquired} {
      log::info "status: no longer acquired in HA."
    }

    set lasthaaxislimited $haaxislimited
    if {(($hamotionstate >> 4) & 1) == 0} {
      set haaxislimited false
    } else {
      set haaxislimited true
    }
    if {$haaxislimited && !$lasthaaxislimited} {
      log::debug "status: limited in HA."
      log::warning "limited in HA."
    } elseif {!$haaxislimited && $lasthaaxislimited} {
      log::debug "status: no longer limited in HA."
      log::info "no longer limited in HA."
    }

    set lasthaaxistracking $haaxistracking
    if {$forcenottracking} {
      set haaxistracking false
    } elseif {$haaxistrajectory && $haaxisacquired} {
      set haaxistracking true
    } elseif {!$haaxistrajectory} {
      set haaxistracking false
    }
    if {$haaxistracking && !$lasthaaxistracking} {
      log::debug "status: started tracking in HA."
      log::info [format \
        "started tracking in HA at %s with error of %+.1fas." \
        [astrometry::formatha $mountha] \
        [astrometry::radtoarcsec $mounteasttrackingerror] \
      ]
    } elseif {!$haaxistracking && $lasthaaxistracking} {
      log::debug "status: stopped tracking in HA."
      log::info "stopped tracking in HA."
    }

    set lastdeltaaxismoving $deltaaxismoving
    if {(($deltamotionstate >> 0) & 1) == 0} {
      set deltaaxismoving false
    } else {
      set deltaaxismoving true
    }
    if {$deltaaxismoving && !$lastdeltaaxismoving} {
      log::debug "status: started moving in δ."
    } elseif {!$deltaaxismoving && $lastdeltaaxismoving} {
      log::debug "status: stopped moving in δ."
    }

    set lastdeltaaxistrajectory $deltaaxistrajectory
    if {(($deltamotionstate >> 1) & 1) == 0} {
      set deltaaxistrajectory false
    } else {
      set deltaaxistrajectory true
    }
    if {$deltaaxistrajectory && !$lastdeltaaxistrajectory} {
      log::debug "status: started running a trajectory in δ."
    } elseif {!$deltaaxistrajectory && $lastdeltaaxistrajectory} {
      log::debug "status: stopped running a trajectory in δ."
    }

    set lastdeltaaxisblocked $deltaaxisblocked
    if {(($deltamotionstate >> 2) & 1) == 0} {
      set deltaaxisblocked false
    } else {
      set deltaaxisblocked true
    }
    if {$deltaaxisblocked && !$lastdeltaaxisblocked} {
      log::debug "status: blocked in δ."
      log::warning "blocked in δ."
    } elseif {!$deltaaxisblocked && $lastdeltaaxisblocked} {
      log::debug "status: no longer blocked in δ."
      log::info "no longer blocked in δ."
    }

    set lastdeltaaxisacquired $deltaaxisacquired
    if {(($deltamotionstate >> 3) & 1) == 0} {
      set deltaaxisacquired false
    } else {
      set deltaaxisacquired true
    }
    if {$deltaaxisacquired && !$lastdeltaaxisacquired} {
      log::debug "status: acquired in δ."
    } elseif {!$deltaaxisacquired && $lastdeltaaxisacquired} {
      log::debug "status: no longer acquired in δ."
    }

    set lastdeltaaxislimited $deltaaxislimited
    if {(($deltamotionstate >> 4) & 1) == 0} {
      set deltaaxislimited false
    } else {
      set deltaaxislimited true
    }
    if {$deltaaxislimited && !$lastdeltaaxislimited} {
      log::debug "status: limited in δ."
      log::warning "limited in δ."
    } elseif {!$deltaaxislimited && $lastdeltaaxislimited} {
      log::debug "status: no longer limited in δ."
      log::info "no longer limited in δ."
    }

    set lastmoving $moving
    if {$haaxismoving || $deltaaxismoving} {
      set moving true
    } else {
      set moving false
    }
    if {$moving && !$lastmoving} {
      log::info "started moving."
    } elseif {!$moving && $lastmoving} {
      log::info "stopped moving."
    }
    set waitmoving $moving


    if {[string equal [server::getrequestedactivity] "tracking"] && !$tracking} {
      log::debug [format \
        "moving to track: mount tracking error is %+.1fas (%+.1fas east and %+.1fas north)." \
        [astrometry::radtoarcsec $mounttrackingerror] \
        [astrometry::radtoarcsec $mounteasttrackingerror] \
        [astrometry::radtoarcsec $mountnorthtrackingerror] \
      ]
    }


    set lastdeltaaxistracking $deltaaxistracking
    if {$forcenottracking} {
      set deltaaxistracking false
    } elseif {$deltaaxistrajectory && $deltaaxisacquired} {
      set deltaaxistracking true
    } elseif {!$deltaaxistrajectory} {
      set deltaaxistracking false
    }
    if {$deltaaxistracking && !$lastdeltaaxistracking} {
      log::debug "status: started tracking in δ."
      log::info [format \
        "started tracking in δ at %s with error of %+.1fas." \
        [astrometry::formatdelta $mountdelta] \
        [astrometry::radtoarcsec $mountnorthtrackingerror] \
      ]
    } elseif {!$deltaaxistracking && $lastdeltaaxistracking} {
      log::debug "status: stopped tracking in δ."
      log::info "stopped tracking in δ."
    }

    set lasttracking $tracking
    set lastsettling $settling
    if {$lasttracking} {
      if {!$haaxistracking || !$deltaaxistracking} {
        set tracking false
        set settling false
      }
    } else {
      if {$haaxistracking && $deltaaxistracking} {
        set settling true
      }
      if {!$lastsettling && $settling} {
        log::info "settling."
        set settlingtimestamp [utcclock::combinedformat]
      }
      if {$haaxistracking && $deltaaxistracking && $mounttrackingerror <= $trackingsettledlimit} {
        log::info [format "finished settling after %.1f seconds." [utcclock::diff now $settlingtimestamp]]
        set tracking true
      }
    }
    set waittracking $tracking
    
    if {$tracking && !$lasttracking} {
      log::info "started tracking."
      set trackingtimestamp [utcclock::combinedformat]
    } elseif {!$tracking && $lasttracking} {
      log::info [format "stopped tracking."]
      set trackingtimestamp ""
    }

    if {$tracking} {
      if {$mounttrackingerror > $trackingsettledlimit} {
        log::info [format \
          "while tracking: mount tracking error is %+.1fas (%+.1fas east and %+.1fas north)." \
          [astrometry::radtoarcsec $mounttrackingerror] \
          [astrometry::radtoarcsec $mounteasttrackingerror] \
          [astrometry::radtoarcsec $mountnorthtrackingerror] \
        ]
      }
      updatetracking $axishatrackingerror $axisdeltatrackingerror $mounteasttrackingerror $mountnorthtrackingerror
    }

    variable emergencystopped
    if {
      [string equal $state "operational"] &&
      !$emergencystopped &&
      $moving &&
      ![string equal "starting"     [server::getdata "activity"]] &&
      ![string equal "started"      [server::getdata "activity"]] &&
      ![string equal "initializing" [server::getdata "activity"]] &&
      ![string equal "parking"      [server::getdata "activity"]] &&
      ![string equal "unparking"    [server::getdata "activity"]] &&
      ![withinlimits $mountha $mountdelta $mountrotation]
    } {
      log::error "mount is moving and not within the limits."
      log::error "mount position is [astrometry::formatha $mountha] [astrometry::formatdelta $mountdelta]."
      log::error [format "mount rotation is %.0f°." [astrometry::radtodeg $mountrotation]]
      startemergencystop
    }

    server::setdata "timestamp"                   $timestamp
    server::setdata "mountha"                     $mountha
    server::setdata "mountalpha"                  $mountalpha
    server::setdata "mountdelta"                  $mountdelta
    server::setdata "mountazimuth"                $mountazimuth
    server::setdata "mountzenithdistance"         $mountzenithdistance
    server::setdata "mountrotation"               $mountrotation
    server::setdata "state"                       $state

    updaterequestedpositiondata false

    server::setstatus "ok"

    return true
  }

  ######################################################################
  
  variable sumaxishatrackingerror       0
  variable sumaxisdeltatrackingerror    0
  variable summounteasttrackingerror    0
  variable summountnorthtrackingerror   0
  variable sumsqmounteasttrackingerror  0
  variable sumsqmountnorthtrackingerror 0
  variable nmounttrackingerror          0

  variable maxmounteasttrackingerror    ""
  variable minmounteasttrackingerror    ""
  variable maxmountnorthtrackingerror   ""
  variable minmountnorthtrackingerror   ""

  variable axismeanhatrackingerror      ""
  variable axismeandeltatrackingerror   ""
  variable mountmeaneasttrackingerror   ""
  variable mountmeannorthtrackingerror  ""
  variable mountrmseasttrackingerror    ""
  variable mountrmsnorthtrackingerror   ""
  variable maxmounteasttrackingerror    ""
  variable minmounteasttrackingerror    ""
  variable maxmountnorthtrackingerror   ""
  variable minmountnorthtrackingerror   ""
  variable mountpveasttrackingerror     ""
  variable mountpvnorthtrackingerror    ""

  proc maybestarttracking {} {
    variable forcenottracking
    set forcenottracking false
  }
  
  proc updatetracking {axishatrackingerror axisdeltatrackingerror mounteasttrackingerror mountnorthtrackingerror} {

    variable sumaxishatrackingerror
    variable sumaxisdeltatrackingerror
    variable summounteasttrackingerror
    variable summountnorthtrackingerror
    variable sumsqmounteasttrackingerror
    variable sumsqmountnorthtrackingerror
    variable nmounttrackingerror

    variable axismeanhatrackingerror
    variable axismeandeltatrackingerror
    variable mountmeaneasttrackingerror
    variable mountmeannorthtrackingerror
    variable mountrmseasttrackingerror
    variable mountrmsnorthtrackingerror
    variable maxmounteasttrackingerror
    variable minmounteasttrackingerror
    variable maxmountnorthtrackingerror
    variable minmountnorthtrackingerror
    variable mountpveasttrackingerror
    variable mountpvnorthtrackingerror

    set sumaxishatrackingerror       [expr {$sumaxishatrackingerror       + $axishatrackingerror}]
    set sumaxisdeltatrackingerror    [expr {$sumaxisdeltatrackingerror    + $axisdeltatrackingerror}]
    set summounteasttrackingerror    [expr {$summounteasttrackingerror    + $mounteasttrackingerror}]
    set summountnorthtrackingerror   [expr {$summountnorthtrackingerror   + $mountnorthtrackingerror}]
    set sumsqmounteasttrackingerror  [expr {$sumsqmounteasttrackingerror  + pow($mounteasttrackingerror , 2)}]
    set sumsqmountnorthtrackingerror [expr {$sumsqmountnorthtrackingerror + pow($mountnorthtrackingerror, 2)}]
    set nmounttrackingerror          [expr {$nmounttrackingerror + 1}]

    set axismeanhatrackingerror      [expr {$sumaxishatrackingerror     / $nmounttrackingerror}]
    set axismeandeltatrackingerror   [expr {$sumaxisdeltatrackingerror  / $nmounttrackingerror}]
    set mountmeaneasttrackingerror   [expr {$summounteasttrackingerror  / $nmounttrackingerror}]
    set mountmeannorthtrackingerror  [expr {$summountnorthtrackingerror / $nmounttrackingerror}]
    set mountrmseasttrackingerror    [expr {sqrt(($sumsqmounteasttrackingerror  - $nmounttrackingerror * pow($mountmeaneasttrackingerror , 2)) / $nmounttrackingerror)}]
    set mountrmsnorthtrackingerror   [expr {sqrt(($sumsqmountnorthtrackingerror - $nmounttrackingerror * pow($mountmeannorthtrackingerror, 2)) / $nmounttrackingerror)}]
    if {[string equal $maxmounteasttrackingerror ""]} {
      set maxmounteasttrackingerror  $mounteasttrackingerror
    } else {
      set maxmounteasttrackingerror  [expr {max($maxmounteasttrackingerror,$mounteasttrackingerror)}]
    }
    if {[string equal $minmounteasttrackingerror ""]} {
      set minmounteasttrackingerror  $mounteasttrackingerror
    } else {
      set minmounteasttrackingerror  [expr {min($minmounteasttrackingerror,$mounteasttrackingerror)}]
    }
    if {[string equal $maxmountnorthtrackingerror ""]} {
      set maxmountnorthtrackingerror $mountnorthtrackingerror
    } else {
      set maxmountnorthtrackingerror [expr {max($maxmountnorthtrackingerror,$mountnorthtrackingerror)}]
    }
    if {[string equal $minmountnorthtrackingerror ""]} {
      set minmountnorthtrackingerror $mountnorthtrackingerror
    } else {
      set minmountnorthtrackingerror [expr {min($minmountnorthtrackingerror,$mountnorthtrackingerror)}]
    }
    set mountpveasttrackingerror     [expr {$maxmounteasttrackingerror-$minmounteasttrackingerror}]
    set mountpvnorthtrackingerror    [expr {$maxmountnorthtrackingerror-$minmountnorthtrackingerror}]

    server::setdata "axismeanhatrackingerror"     $axismeanhatrackingerror
    server::setdata "axismeandeltatrackingerror"  $axismeandeltatrackingerror
    server::setdata "mountmeaneasttrackingerror"  $mountmeaneasttrackingerror
    server::setdata "mountmeannorthtrackingerror" $mountmeannorthtrackingerror
    server::setdata "mountrmseasttrackingerror"   $mountrmseasttrackingerror
    server::setdata "mountrmsnorthtrackingerror"  $mountrmsnorthtrackingerror
    server::setdata "mountpveasttrackingerror"    $mountpveasttrackingerror
    server::setdata "mountpvnorthtrackingerror"   $mountpvnorthtrackingerror

  }
  
  proc maybeendtracking {} {

    variable tracking
    variable lasttracking
    variable trackingtimestamp

    variable sumaxishatrackingerror
    variable sumaxisdeltatrackingerror
    variable summounteasttrackingerror
    variable summountnorthtrackingerror
    variable sumsqmounteasttrackingerror
    variable sumsqmountnorthtrackingerror
    variable nmounttrackingerror

    variable axismeanhatrackingerror
    variable axismeandeltatrackingerror
    variable mountmeaneasttrackingerror
    variable mountmeannorthtrackingerror
    variable mountrmseasttrackingerror
    variable mountrmsnorthtrackingerror
    variable maxmounteasttrackingerror
    variable minmounteasttrackingerror
    variable maxmountnorthtrackingerror
    variable minmountnorthtrackingerror
    variable mountpveasttrackingerror
    variable mountpvnorthtrackingerror

    if {$tracking} {
      log::info [format "stopped tracking after %.1f seconds." [utcclock::diff now $trackingtimestamp]]
      if {
        ![string equal $axismeanhatrackingerror ""] &&
        ![string equal $axismeandeltatrackingerror ""]
      } {
        log::info [format \
          "mean axis tracking errors were %+.2fas in HA and %+.2fas in δ." \
          [astrometry::radtoarcsec $axismeanhatrackingerror] \
          [astrometry::radtoarcsec $axismeandeltatrackingerror] \
        ]
      }
      if {
        ![string equal $mountmeaneasttrackingerror ""] &&
        ![string equal $mountmeannorthtrackingerror ""]
      } {
        log::info [format \
          "mean tracking errors were %+.2fas east and %+.2fas north." \
          [astrometry::radtoarcsec $mountmeaneasttrackingerror] \
          [astrometry::radtoarcsec $mountmeannorthtrackingerror] \
        ]
      }
      if {
        ![string equal $mountrmseasttrackingerror ""] &&
        ![string equal $mountrmsnorthtrackingerror ""]
      } {
        log::info [format \
          "RMS tracking errors were %.2fas east and %.2fas north." \
          [astrometry::radtoarcsec $mountrmseasttrackingerror] \
          [astrometry::radtoarcsec $mountrmsnorthtrackingerror] \
        ]
      }
      if {
        ![string equal $mountpveasttrackingerror ""] &&
        ![string equal $mountpvnorthtrackingerror ""]
      } {
        log::info [format \
          "P-V tracking errors were %.2fas east and %.2fas north." \
          [astrometry::radtoarcsec $mountpveasttrackingerror] \
          [astrometry::radtoarcsec $mountpvnorthtrackingerror] \
        ]
      }
    }

    set tracking                     false
    set trackingtimestamp            ""

    set sumaxishatrackingerror       0
    set sumaxisdeltatrackingerror    0
    set summounteasttrackingerror    0
    set summountnorthtrackingerror   0
    set sumsqmounteasttrackingerror  0
    set sumsqmountnorthtrackingerror 0
    set nmounttrackingerror          0

    set axismeanhatrackingerror      ""
    set axismeandeltatrackingerror   ""
    set mountmeaneasttrackingerror   ""
    set mountmeannorthtrackingerror  ""
    set mountrmseasttrackingerror    ""
    set mountrmsnorthtrackingerror   ""
    set maxmounteasttrackingerror    ""
    set minmounteasttrackingerror    ""
    set maxmountnorthtrackingerror   ""
    set minmountnorthtrackingerror   ""
    set mountpveasttrackingerror     ""
    set mountpvnorthtrackingerror    ""

    server::setdata "axismeanhatrackingerror"     $axismeanhatrackingerror
    server::setdata "axismeandeltatrackingerror"  $axismeandeltatrackingerror
    server::setdata "mountmeaneasttrackingerror"  $mountmeaneasttrackingerror
    server::setdata "mountmeannorthtrackingerror" $mountmeannorthtrackingerror
    server::setdata "mountrmseasttrackingerror"   $mountrmseasttrackingerror
    server::setdata "mountrmsnorthtrackingerror"  $mountrmsnorthtrackingerror
    server::setdata "mountpveasttrackingerror"    $mountpveasttrackingerror
    server::setdata "mountpvnorthtrackingerror"   $mountpvnorthtrackingerror

    variable forcenottracking
    set forcenottracking true
  }
  
  ######################################################################

  proc withinlimits {mountha mountdelta mountrotation} {

    variable easthalimit
    variable westhalimit
    variable meridianhalimit
    variable polardeltalimit
    variable southdeltalimit
    variable northdeltalimit
    variable zenithdistancelimit

    set mountzenithdistance [astrometry::zenithdistance $mountha $mountdelta]
    
    if {$mountha < $easthalimit && $mountdelta < $polardeltalimit} {
      log::warning "HA exceeds eastern limit."
      return false
    } elseif {$mountha > $westhalimit && $mountdelta < $polardeltalimit} {
      log::warning "HA exceeds western limit."
      return false
    } elseif {$mountdelta < $southdeltalimit} {
      log::warning "δ exceeds southern limit."
      return false
    } elseif {$mountdelta > $northdeltalimit} {
      log::warning "δ exceeds northern limit."
      return false
    } elseif {$mountzenithdistance > $zenithdistancelimit} {
      log::warning "zenith distance exceeds limit."
      return false
    } elseif {$mountrotation == 0 && $mountha <= -$meridianhalimit && $mountdelta < $polardeltalimit} {
      log::warning "HA exceeds eastern meridian limit."
      return false
    } elseif {$mountrotation != 0 && $mountha >= +$meridianhalimit && $mountdelta < $polardeltalimit} {
      log::warning "HA exceeds western meridian limit."
      return false
    } else {
      return true
    }

  }

  ######################################################################

  proc axisha {ha delta mountrotation} {
    if {$mountrotation == 0} {
      return $ha
    } else {
      return [expr {[astrometry::pi] + $ha}]
    }
  }

  proc axisdelta {ha delta mountrotation} {
    if {$mountrotation == 0} {
      return $delta
    } else {
      return [expr {[astrometry::pi] - $delta}]
    }
  }

  proc mountrotation {ha delta} {
    if {$ha >= 0} {
      return 0
    } else {
      return [astrometry::pi]
    }
  }

  ######################################################################

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

  proc acceptablehaerror {} {
    variable allowedpositionerror
    set haerror [server::getdata "mounthaerror"]
    return [expr {abs($haerror) <= $allowedpositionerror}]
  }

  proc acceptablealphaerror {} {
    variable allowedpositionerror
    set alphaerror [server::getdata "mountalphaerror"]
    return [expr {abs($alphaerror) <= $allowedpositionerror}]
  }

  proc acceptabledeltaerror {} {
    variable allowedpositionerror
    set deltaerror [server::getdata "mountdeltaerror"]
    return [expr {abs($deltaerror) <= $allowedpositionerror}]
  }

  proc checkhaerror {when} {
    variable allowedpositionerror
    set haerror [server::getdata "mounthaerror"]
    if {abs($haerror) > $allowedpositionerror} {
      log::warning "mount HA error is [astrometry::radtohms $haerror 2 true] $when."
    }
  }

  proc checkalphaerror {when} {
    variable allowedpositionerror
    set alphaerror [server::getdata "mountalphaerror"]
    if {abs($alphaerror) > $allowedpositionerror} {
      log::warning "mount alpha error is [astrometry::radtohms $alphaerror 2 true] $when."
    }
  }

  proc checkdeltaerror {when} {
    variable allowedpositionerror
    set deltaerror [server::getdata "mountdeltaerror"]
    if {abs($deltaerror) > $allowedpositionerror} {
      log::warning "mount delta error is [astrometry::radtodms $deltaerror 1 true] $when."
    }
  }

  ######################################################################

  proc offsetcommand {which alphaoffset deltaoffset} {
    set mountdelta [server::getdata "mountdelta"]
    set alphaoffset [expr {$alphaoffset / cos($mountdelta)}]
    set alphaoffset [astrometry::radtoarcsec $alphaoffset]
    set deltaoffset [astrometry::radtoarcsec $deltaoffset]
    while {abs($alphaoffset) > 60 || abs($deltaoffset) > 60} {
      if {$alphaoffset > 60} {
        set dalphaoffset +60
        set alphaoffset [expr {$alphaoffset - 60}]
      } elseif {$alphaoffset < -60} {
        set dalphaoffset -60
        set alphaoffset [expr {$alphaoffset + 60}]
      } else {
        set dalphaoffset 0
      }
      if {$deltaoffset > 60} {
        set ddeltaoffset +60
        set deltaoffset [expr {$deltaoffset - 60}]
      } elseif {$deltaoffset < -60} {
        set ddeltaoffset -60
        set deltaoffset [expr {$deltaoffset + 60}]
      } else {
        set ddeltaoffset 0
      }
      controller::${which}command [format "OFF %+.2f %+.2f\n" $dalphaoffset $ddeltaoffset]
    }
    controller::${which}command [format "OFF %+.2f %+.2f\n" $alphaoffset $deltaoffset]
  }

  ######################################################################

  variable offsetalphalimit [astrometry::parseangle "30as"]
  variable offsetdeltalimit [astrometry::parseangle "30as"]

  proc shouldoffsettotrack {} {
    set mountalphaerror [server::getdata "mountalphaerror"]
    set mountdeltaerror [server::getdata "mountdeltaerror"]
    set mountdelta           [server::getdata "mountdelta"]
    set alphaoffset [expr {$mountalphaerror * cos($mountdelta)}]
    set deltaoffset $mountdeltaerror
    variable offsetalphalimit
    variable offsetdeltalimit
    return [expr {
      [server::getdata "mounttracking"] &&
      abs($alphaoffset) < $offsetalphalimit &&
      abs($deltaoffset) < $offsetdeltalimit
    }]
  }

  ######################################################################

  variable emergencystopped false

  proc startemergencystop {} {
    log::error "starting emergency stop."
    log::warning "stopping the mount."
    log::debug "emergency stop: sending emergency stop."
    variable emergencystopcommandidentifier
    set command "$emergencystopcommandidentifier SET HA.STOP=1;DEC.STOP=1"
    log::debug "emergency stop: sending command \"$command\"."
    controller::flushcommandqueue
    controller::pushcommand "$command\n"
    log::debug "emergency stop: finished sending emergency stop."
    server::setdata "mounttracking" false
    variable emergencystopped
    set emergencystopped true
    server::erroractivity
  }

  proc finishemergencystop {} {
    log::error "finished emergency stop."
  }

  ######################################################################

  variable currentcommandidentifier 0
  variable nextcommandidentifier $firstnormalcommandidentifier
  variable completedcurrentcommand

  proc sendcommand {command} {
    variable currentcommandidentifier
    variable nextcommandidentifier
    variable completedcurrentcommand
    variable firstnormalcommandidentifier
    variable lastnormalcommandidentifier
    set currentcommandidentifier $nextcommandidentifier
    if {$nextcommandidentifier == $lastnormalcommandidentifier} {
      set nextcommandidentifier $firstnormalcommandidentifier
    } else {
      set nextcommandidentifier [expr {$nextcommandidentifier + 1}]
    }
    log::debug "sending controller command $currentcommandidentifier: \"$command\"."
    controller::pushcommand "$currentcommandidentifier $command\n"
  }

  proc sendcommandandwait {command} {
    variable currentcommandidentifier
    variable completedcurrentcommand
    set start [utcclock::seconds]
    set completedcurrentcommand false
    sendcommand $command    
    coroutine::yield
    while {!$completedcurrentcommand} {
      coroutine::yield
    }
    set end [utcclock::seconds]
    log::debug [format "completed controller command $currentcommandidentifier after %.1f seconds." [utcclock::diff $end $start]]
  }

  proc waitwhilemoving {} {
    log::debug "waitwhilemoving: starting."
    variable waitmoving
    set waitmoving false
    while {$waitmoving} {
      log::debug "waitwhilemoving: yielding."
      coroutine::yield
    }
    log::debug "waitwhilemoving: finished."
  }

  proc waitwhilemountrotation {mountrotation} {
    log::debug "waitwhilemountrotation: starting."
    while {$mountrotation == [server::getdata "mountrotation"]} {
      log::debug "waitwhilemountrotation: yielding."
      coroutine::yield
    }
    log::debug "waitwhilemountrotation: finished."
  }
  
  proc waituntilsafetomovebothaxes {} {
    log::debug "waituntilsafetomovebothaxes: starting."
    variable zenithdistancelimit
    while {true} {
      set requestedmountha       [server::getdata "requestedmountha"]
      set requestedmountdelta    [server::getdata "requestedmountdelta"]
      set mountha                [server::getdata "mountha"]
      set mountdelta             [server::getdata "mountdelta"]
      if {
        [astrometry::zenithdistance $requestedmountha $requestedmountdelta] > $zenithdistancelimit
      } {
        error "the requested position is below the zenith distance limit."
      } elseif {
        [astrometry::zenithdistance $mountha $requestedmountdelta] < $zenithdistancelimit &&
        [astrometry::zenithdistance $requestedmountha $mountdelta] < $zenithdistancelimit
      } {
        log::debug "waituntilsafetomovebothaxes: finished."
        return
      }
      log::debug "waituntilsafetomovebothaxes: yielding."
      coroutine::yield
    }
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

  proc isoperational {} {
    variable state
    if {[string equal $state "operational"]} {
      return true
    } else {
      return false
    }
  }

  proc waituntiloperational {} {
    log::debug "waituntiloperational: starting."
    while {![isoperational]} {
      log::debug "waituntiloperational: yielding."
      coroutine::yield
    }
    log::debug "waituntiloperational: finished."
  }

  ######################################################################

  proc stophardware {} {
    log::info "stopping the mount."
    controller::flushcommandqueue
    sendcommandandwait "SET HA.STOP=1;DEC.STOP=1"
    waitwhilemoving
  }

  proc movehardware {movetotrack} {

    updaterequestedpositiondata true
    set requestedmountha       [server::getdata "requestedmountha"]
    set requestedmountdelta    [server::getdata "requestedmountdelta"]
    set requestedmountrotation [server::getdata "requestedmountrotation"]

    set mountha                [server::getdata "mountha"]
    set mountdelta             [server::getdata "mountdelta"]
    set mountrotation          [server::getdata "mountrotation"]

    log::info [format \
      "moving from %s %s (%.0f°) to %s %s (%.0f°)." \
      [astrometry::formatha $mountha] \
      [astrometry::formatdelta $mountdelta] \
      [astrometry::radtodeg $mountrotation] \
      [astrometry::formatha $requestedmountha] \
      [astrometry::formatdelta $requestedmountdelta] \
      [astrometry::radtodeg $requestedmountrotation] \
    ]
    server::setdata "mounttracking" false

    if {$mountrotation != $requestedmountrotation} {
      log::info "moving in δ to flip the mount rotation."
      if {$mountrotation == 0} {
        sendcommandandwait "SET DEC.TARGETPOS=100"
      } else {
        sendcommandandwait "SET DEC.TARGETPOS=80"
      }
      waitwhilemountrotation $mountrotation
      set mountha       [server::getdata "mountha"]
      set mountdelta    [server::getdata "mountdelta"]
      set mountrotation [server::getdata "mountrotation"]
    } else {
      log::info "maintaining the mount rotation."
    }

    set requestedaxisha    [axisha    $requestedmountha $requestedmountdelta $requestedmountrotation]
    set requestedaxisdelta [axisdelta $requestedmountha $requestedmountdelta $requestedmountrotation]
    
    variable zenithdistancelimit
    if {
      [astrometry::zenithdistance $requestedmountha $requestedmountdelta] > $zenithdistancelimit
    } {
      error "the requested position is below the zenith distance limit."
    } elseif {
      [astrometry::zenithdistance $mountha $requestedmountdelta] > $zenithdistancelimit
    } {
      log::info "moving first in HA to stay above the zenith distance limit."
      sendcommandandwait \
        [format "SET HA.TARGETPOS=%.5f" [astrometry::radtodeg $requestedaxisha]]
      waituntilsafetomovebothaxes
      if {!$movetotrack} {
        log::info "moving in δ."
        sendcommandandwait \
          [format "SET DEC.TARGETPOS=%.5f" [astrometry::radtodeg $requestedaxisdelta]]
      }
    } elseif {
      [astrometry::zenithdistance $requestedmountha $mountdelta] > $zenithdistancelimit
    } {
      log::info "moving first in δ to stay above the zenith distance limit."
      sendcommandandwait \
        [format "SET DEC.TARGETPOS=%.5f" [astrometry::radtodeg $requestedaxisdelta]]
      waituntilsafetomovebothaxes
      if {!$movetotrack} {
        log::info "moving in HA."
        sendcommandandwait \
          [format "SET HA.TARGETPOS=%.5f" [astrometry::radtodeg $requestedaxisha]]
      }
    } elseif {!$movetotrack} {
      log::info "moving simultaneously in HA and δ."
      sendcommandandwait [format \
        "SET HA.TARGETPOS=%.5f;DEC.TARGETPOS=%.5f" \
        [astrometry::radtodeg $requestedaxisha] \
        [astrometry::radtodeg $requestedaxisdelta] \
      ]
    }
    
    if {!$movetotrack} {
      waitwhilemoving
    }
    
  }
  
  proc parkhardware {} {
    variable hapark
    variable deltapark
    log::info "moving in δ to pole."
    sendcommandandwait "SET DEC.TARGETPOS=90"
    waitwhilemoving
    log::info [format "moving in HA to park at %+.1fd." [astrometry::radtodeg $hapark]]
    sendcommandandwait "SET HA.TARGETPOS=[astrometry::radtodeg $hapark]"
    waitwhilemoving
    log::info [format "moving in δ to park at %+.1fd." [astrometry::radtodeg $deltapark]]
    sendcommandandwait "SET DEC.TARGETPOS=[astrometry::radtodeg $deltapark]"
    waitwhilemoving
  }
  
  proc unparkhardware {} {
    variable haunpark
    variable deltaunpark
    log::info "moving in δ to pole."
    sendcommandandwait "SET DEC.TARGETPOS=90"
    waitwhilemoving
    log::info [format "moving in HA to unpark at %+.1fd." [astrometry::radtodeg $haunpark]]
    sendcommandandwait "SET HA.TARGETPOS=[astrometry::radtodeg $haunpark]"
    waitwhilemoving
    log::info [format "moving in δ to unpark at %+.1fd." [astrometry::radtodeg $deltaunpark]]
    sendcommandandwait "SET DEC.TARGETPOS=[astrometry::radtodeg $deltaunpark]"
    waitwhilemoving  
  }

  ######################################################################

  proc startactivitycommand {} {
    set start [utcclock::seconds]
    log::info "starting."
    while {[string equal [server::getstatus] "starting"]} {
      coroutine::yield
    }
    stophardware
    set end [utcclock::seconds]
    log::info [format "finished starting after %.1f seconds." [utcclock::diff $end $start]]
  }

  proc initializeactivitycommand {} {
    set start [utcclock::seconds]
    maybeendtracking
    log::info "initializing."
    updaterequestedpositiondata false
    server::setdata "mounttracking" false
    stophardware
    if {![isoperational]} {
      log::info "attempting to change the controller state from [server::getdata "state"] to operational."
      coroutine::after 1000
      #sendcommandandwait "SET CABINET.POWER=0"
      #coroutine::after 1000
      sendcommandandwait "SET CABINET.STATUS.CLEAR=1"
      coroutine::after 1000
      sendcommandandwait "SET CABINET.POWER=1"
      coroutine::after 1000
      waituntiloperational
    }
    log::info "the controller state is operational."
    sendcommandandwait "SET DEC.OFFSET=0"
    sendcommandandwait "SET HA.OFFSET=0"
    parkhardware
    set end [utcclock::seconds]
    log::info [format "finished initializing after %.1f seconds." [utcclock::diff $end $start]]
  }

  proc openactivitycommand {} {
    updaterequestedpositiondata false
    initializeactivitycommand
  }

  proc stopactivitycommand {} {
    set start [utcclock::seconds]
    maybeendtracking
    log::info "stopping."
    updaterequestedpositiondata false
    server::setdata "mounttracking" false
    stophardware
    set end [utcclock::seconds]
    log::info [format "finished stopping after %.1f seconds." [utcclock::diff $end $start]]
  }

  proc resetactivitycommand {} {
    set start [utcclock::seconds]
    maybeendtracking
    log::info "resetting."
    updaterequestedpositiondata false
    server::setdata "mounttracking" false
#    stophardware
    if {![isoperational]} {
      log::info "attempting to change the controller state from [server::getdata "state"] to operational."
      log::info "clearing errors."
      sendcommandandwait "SET CABINET.STATUS.CLEAR=1"
      waituntiloperational
    }
    variable emergencystopped
    if {$emergencystopped} {
      log::info "recovering from emergency stop."
      server::setactivity "parking"
      log::info "parking."
      parkhardware
      server::setactivity "unparking"
      log::info "unparking."
      unparkhardware
      set emergencystopped false
      log::info "finished recovering from emergency stop."
    }
    set end [utcclock::seconds]
    log::info [format "finished resetting after %.1f seconds." [utcclock::diff $end $start]]
  }

  proc rebootactivitycommand {} {
    set start [utcclock::seconds]
    maybeendtracking
    log::info "rebooting."
    updaterequestedpositiondata false
    server::setdata "mounttracking" false
    stophardware
    coroutine::after 1000
    log::info "switching off cabinet."
    sendcommandandwait "SET CABINET.POWER=0"
    coroutine::after 1000
    log::info "attempting to change the controller state from [server::getdata "state"] to operational."
    log::info "clearing errors."
    sendcommandandwait "SET CABINET.STATUS.CLEAR=1"
    coroutine::after 1000
    log::info "switching on cabinet."
    sendcommandandwait "SET CABINET.POWER=1"
    coroutine::after 1000
    waituntiloperational
    set end [utcclock::seconds]
    log::info [format "finished rebooting after %.1f seconds." [utcclock::diff $end $start]]
  }

  proc preparetomoveactivitycommand {} {
    updaterequestedpositiondata false
  }

  proc checktarget {activity expectedactivity} {
    if {[catch {client::checkactivity "target" $expectedactivity} message]} {
      controller::flushcommandqueue
#      controller::sendcommand "NGUIA\n"
      server::setdata "mounttracking" false
      error "$activity cancelled: $message"
    }
    if {![client::getdata "target" "withinlimits"]} {
      controller::flushcommandqueue
#      controller::sendcommand "NGUIA\n"
      server::setdata "mounttracking" false
      error "$activity cancelled: the target is not within the limits."
    }
  }

  proc moveactivitycommand {} {
    set start [utcclock::seconds]
    maybeendtracking
    log::info "moving."
    if {[catch {checktarget "move" "idle"} message]} {
      log::warning $message
      return
    }
#    log::info "stopping."
#    stophardware
    movehardware false
    if {![acceptablehaerror] || ![acceptabledeltaerror]} {
      log::debug [format "mount error %.1fas E and %.1fas N." [astrometry::radtoarcsec [server::getdata "mounthaerror"]] [astrometry::radtoarcsec [server::getdata "mountdeltaerror"]]]
      movehardware false
    }
    checkhaerror    "after moving to fixed"
    checkdeltaerror "after moving to fixed"
    set end [utcclock::seconds]
    log::info [format "finished moving after %.1f seconds." [utcclock::diff $end $start]]
  }

  proc parkactivitycommand {} {
    set start [utcclock::seconds]
    maybeendtracking
    log::info "parking."
#    stophardware
    parkhardware
    set end [utcclock::seconds]
    log::info [format "finished parking after %.1f seconds." [utcclock::diff $end $start]]
  }

  proc unparkactivitycommand {} {
    set start [utcclock::seconds]
    log::info "unparking."
#     stophardware
    unparkhardware
    set end [utcclock::seconds]
    log::info [format "finished unparking after %.1f seconds." [utcclock::diff $end $start]]
  }

  proc preparetotrackactivitycommand {} {
    updaterequestedpositiondata false
  }

  proc addtrajectorypoints {seconds n dseconds} {
    variable freepoints
    set start [utcclock::seconds]
    log::debug "adding trajectory points."
    if {$n > $freepoints} {
      log::debug "only attempting to add $freepoints points."
      set n $freepoints
    }
    set halist    ""
    set deltalist ""
    set timelist  ""
    set i 0
    if {[catch {
      updaterequestedpositiondata false
      set requestedseconds        [utcclock::scan [server::getdata "requestedtimestamp"]]
      set requestedmountha        [server::getdata "requestedmountha"]
      set requestedmountdelta     [server::getdata "requestedmountdelta"]
      set requestedmountrotation  [server::getdata "requestedmountrotation"]
      set requestedmountharate    [server::getdata "requestedmountharate"]
      set requestedmountdeltarate [server::getdata "requestedmountdeltarate"]
      log::debug "adding $n trajectory points from [utcclock::format $requestedseconds] to [utcclock::format [expr {$requestedseconds + ($n - 1) * $dseconds}]]."
      while {$i < $n} {
        set futurerequestedseconds    [expr {$seconds + $i * $dseconds}]
        set futurerequestedmountha    [astrometry::foldradsymmetric [expr {$requestedmountha + ($futurerequestedseconds - $requestedseconds) * $requestedmountharate}]]
        set futurerequestedmountdelta [expr {$requestedmountdelta + ($futurerequestedseconds - $requestedseconds) * $requestedmountdeltarate}]
        set futurerequestedaxisha     [axisha    $futurerequestedmountha $futurerequestedmountdelta $requestedmountrotation]
        set futurerequestedaxisdelta  [axisdelta $futurerequestedmountha $futurerequestedmountdelta $requestedmountrotation]
        log::debug [format "trajectory point %d is %s %s %s %+.6fd %+.6fd" \
          $i \
          [utcclock::format $futurerequestedseconds] \
          [astrometry::formatha $futurerequestedmountha] \
          [astrometry::formatdelta $futurerequestedmountdelta] \
          [astrometry::radtodeg $futurerequestedaxisha] \
          [astrometry::radtodeg $futurerequestedaxisdelta]]
        if {$i > 0} {
          set halist    "$halist,"
          set deltalist "$deltalist,"
          set timelist  "$timelist,"
        } 
        set halist    [format "%s%.6f" $halist    [astrometry::radtodeg $futurerequestedaxisha   ]] 
        set deltalist [format "%s%.6f" $deltalist [astrometry::radtodeg $futurerequestedaxisdelta]] 
        set timelist  [format "%s%.4f" $timelist  $futurerequestedseconds]
        set i [expr {$i + 1}]
      }
    } message]} {
      error "unable to calculate new trajectory points: $message"
    }
    set command "SET "
    set command [format "%sHA.TRAJECTORY.BUFFER\[0-%d\].TIME=%s;"       $command [expr {$n - 1}] $timelist ]
    set command [format "%sHA.TRAJECTORY.BUFFER\[0-%d\].TARGETPOS=%s;"  $command [expr {$n - 1}] $halist   ]
    set command [format "%sDEC.TRAJECTORY.BUFFER\[0-%d\].TIME=%s;"      $command [expr {$n - 1}] $timelist ]
    set command [format "%sDEC.TRAJECTORY.BUFFER\[0-%d\].TARGETPOS=%s;" $command [expr {$n - 1}] $deltalist]
    set command [format "%sHA.TRAJECTORY.ADDPOINTS=%d;"                 $command $n]
    set command [format "%sDEC.TRAJECTORY.ADDPOINTS=%d;"                $command $n]
    log::debug "loading trajectory."
    sendcommandandwait $command
    log::debug [format "finished adding trajectory points after %.1f seconds." [utcclock::diff now $start]]
    return [expr {$seconds + $n * $dseconds}]
  }
  
  proc trackoroffsetactivitycommand {move} {
    set start [utcclock::seconds]
    maybeendtracking
    stophardware
    if {$move} {
      log::info "moving to track."
      movehardware true
    }
    if {[catch {checktarget "tracking" "tracking"} message]} {
      log::warning $message
      return
    }
    set trajectoryseconds [utcclock::seconds]
    set trajectorydseconds 2
    set trajectoryn 60
    set trajectorydfutureseconds 120
    set trajectoryseconds [addtrajectorypoints $trajectoryseconds $trajectoryn $trajectorydseconds]
    waituntilnottracking
    sendcommand "SET HA.TRAJECTORY.RUN=1"
    sendcommand "SET DEC.TRAJECTORY.RUN=1"
    maybestarttracking
    waituntiltracking
    log::info [format "started tracking after %.1f seconds." [utcclock::diff now $start]]
    server::setactivity "tracking"
    server::clearactivitytimeout
    while {true} {
      if {[catch {checktarget "tracking" "tracking"} message]} {
        log::warning $message
        return
      }
      if {[utcclock::diff $trajectoryseconds now] < $trajectorydfutureseconds} {
        set trajectoryseconds [addtrajectorypoints $trajectoryseconds $trajectoryn $trajectorydseconds]
      }
      coroutine::after 1000
    }
  }
  
  proc trackactivitycommand {} {
    trackoroffsetactivitycommand true
  }

  proc offsetactivitycommand {} {
    updaterequestedpositiondata true
    set mountrotation          [server::getdata "mountrotation"]
    set requestedmountrotation [server::getdata "requestedmountrotation"]
    if {$mountrotation == $requestedmountrotation} {
      set move false
    } else {
      set move true
    }
    trackoroffsetactivitycommand $move
  }

  ######################################################################

}
