########################################################################

# This file is part of the UNAM telescope control system.

# $Id: secondarycoatlioan.tcl 3601 2020-06-11 03:20:53Z Alan $

########################################################################

# Copyright © 2017, 2019 Alan M. Watson <alan@astro.unam.mx>
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

package require "config"
package require "log"
package require "opentsi"
package require "server"

package provide "secondaryopentsi" 0.0

namespace eval "secondary" {

  ######################################################################

  server::setstatus "ok"
  server::setdata "z"                ""
  server::setdata "zlowerlimit"      ""
  server::setdata "zupperlimit"      ""
  server::setdata "zerror"           ""
  server::setdata "timestamp"        [utcclock::combinedformat now]

  set server::datalifeseconds        30

  ######################################################################

  set statuscommand "GET [join {
    TELESCOPE.READY_STATE
    POSITION.INSTRUMENTAL.FOCUS.LIMIT_STATE
    POSITION.INSTRUMENTAL.FOCUS.MOTION_STATE
    POSITION.INSTRUMENTAL.FOCUS.CURRPOS
    POSITION.INSTRUMENTAL.FOCUS.TARGETDISTANCE
  } ";"]\n"

  ######################################################################

  variable moving
  variable zerror

  variable pendingmode
  variable pendingz
  variable pendingzerror
  variable pendingzlowerlimit
  variable pendingzupperlimit

  proc updatedata {response} {
  
    variable moving
    variable zerror

    variable pendingmode
    variable pendingz
    variable pendingzerror
    variable pendingzlowerlimit
    variable pendingzupperlimit

    if {[scan $response "%*d DATA INLINE TELESCOPE.READY_STATE=%f" value] == 1} {
      if {$value == -3.0} {
        set pendingmode "local"
      } elseif {$value == -2.0} {
        set pendingmode "emergencystop"
      } elseif {$value == -1.0} {
        set pendingmode "blocked"
      } elseif {$value == 0.0} {
        set pendingmode "off"
      } elseif {$value == 1.0} {
        set pendingmode "on"
      } else {
        set pendingmode "intermediate"
      }
      return false
    }
    if {[scan $response "%*d DATA INLINE POSITION.INSTRUMENTAL.FOCUS.CURRPOS=%f" value] == 1} {
      variable minz
      variable maxz
      set pendingz [expr {round($value * 1000)}]
      set pendingz [expr {max($minz,min($maxz,$pendingz))}]
      return false
    }
    if {[scan $response "%*d DATA INLINE POSITION.INSTRUMENTAL.FOCUS.TARGETDISTANCE=%f" value] == 1} {
      set pendingzerror [expr {round($value * 1000)}]
      return false
    }
    if {[scan $response "%*d DATA INLINE POSITION.INSTRUMENTAL.FOCUS.MOTION_STATE=%d" value] == 1} {
      if {$value & (1 << 0)} {
        set moving true
      } else {
        set moving false
      }
      log::debug "moving is $moving."
      return false
    }
    if {[scan $response "%*d DATA INLINE POSITION.INSTRUMENTAL.FOCUS.LIMIT_STATE=%d" value] == 1} {
      if {$value & (1 << 0 | 1 << 8)} {
        set pendingzlowerlimit true
      } else {
        set pendingzlowerlimit false
      }
      if {$value & (1 << 1 | 1 << 9)} {
        set pendingzupperlimit true
      } else {
        set pendingzupperlimit false
      }
      return false
    }

    if {[regexp {[0-9]+ DATA INLINE } $response] == 1} {
      log::debug "status: ignoring DATA INLINE response: $response"
      return false
    }
    if {[regexp {[0-9]+ COMMAND COMPLETE} $response] != 1} {
      log::warning "unexpected controller response \"$response\"."
      return true
    }
    
    set mode        $pendingmode
    set z           $pendingz
    set zerror      $pendingzerror
    set zlowerlimit $pendingzlowerlimit
    set zupperlimit $pendingzupperlimit

    set timestamp   [utcclock::combinedformat "now"]

    server::setdata "timestamp"   $timestamp
    server::setdata "mode"        $mode
    server::setdata "z"           $z
    server::setdata "zerror"      $zerror
    server::setdata "zlowerlimit" $zlowerlimit
    server::setdata "zupperlimit" $zupperlimit

    server::setstatus "ok"

    return true
  }

  proc waitwhilemoving {} {
    log::info "waiting while moving."
    variable moving
    variable zerror
    set startingdelay 1
    set settlingdelay 0
    set start [utcclock::seconds]
    while {[utcclock::diff now $start] < $startingdelay} {
      coroutine::yield
    }
    while {$moving} {
      coroutine::yield
    }
    set settle [utcclock::seconds]
    while {[utcclock::diff now $settle] < $settlingdelay} {
      coroutine::yield
    }
    log::info "finished waiting while moving."
  }
  
  ######################################################################
  
  proc starthardware {} {
    controller::flushcommandqueue
    opentsi::sendcommand "SET POSITION.INSTRUMENTAL.FOCUS.OFFSET=0"
    opentsi::sendcommand "SET POINTING.SETUP.FOCUS.SYNCMODE=0"
    waitwhilemoving
  }

  proc stophardware {} {
    controller::flushcommandqueue
    # OpenTSI has a global stop, but no means to stop individual axes. This is
    # about the best we can do.
    set z [server::getdata "z"]
    opentsi::sendcommand "SET POSITION.INSTRUMENTAL.FOCUS.TARGETPOS=[expr {$z / 1000.0}]"
    waitwhilemoving
  }
  
  proc movehardwaresimple {requestedz} {
    log::debug "movehardwaresimple: starting."
    controller::flushcommandqueue
    variable minz
    variable maxz
    if {$requestedz < $minz} {
      log::warning "moving to minimum position $minz instead of $requestedz."
      set requestedz $minz
    } elseif {$requestedz > $maxz} {
      log::warning "moving to maximum position $maxz instead of $requestedz."
      set requestedz $maxz
    }
    set z [server::getdata "z"]
    if {$z != $requestedz} {
      log::debug "movehardwaresimple: sending commands."
      opentsi::sendcommand "SET POSITION.INSTRUMENTAL.FOCUS.TARGETPOS=[expr {$requestedz / 1000.0}]"
      coroutine::after 1000
      waitwhilemoving
    }
    log::debug "movehardwaresimple: done."
  }

  proc movehardware {requestedz check} {
    set z [server::getdata "z"]
    log::info "moving from raw position $z to $requestedz."
    variable zdeadzonewidth
    if {abs($requestedz - $z) <= $zdeadzonewidth} {
      log::info "ignoring the requested move as the requested position is within the deadzone."
      return
    }
    variable dztweak
    if {
      ($dztweak < 0 && $requestedz < $z) ||
      ($dztweak > 0 && $requestedz > $z)
    } {
      log::info "moving first to raw position [expr {$requestedz + $dztweak}] to mitigate backlash."
      movehardwaresimple [expr {$requestedz + $dztweak}]
    }
    log::info "moving to raw position $requestedz."
    movehardwaresimple $requestedz
    if {$check} {
      checkzerror "after moving"
    }
  }
  
  proc checkhardware {} {
    set mode [server::getdata "mode"]
    if {![string equal $mode "on"]} {
      error "mode is \"$mode\"."
    }
  }
  
  ######################################################################

  proc startactivitycommand {} {
    set start [utcclock::seconds]
    log::info "starting."
    setrequestedz0 ""
    setrequestedz
    starthardware
    set end [utcclock::seconds]
    log::info [format "finished starting after %.1f seconds." [utcclock::diff $end $start]]    
  }
  
  proc initializeactivitycommand {} {
    set start [utcclock::seconds]
    log::info "initializing."
    variable initialz0
    setrequestedz0 $initialz0
    setrequestedz
    log::info "moving to corrected position [server::getdata "requestedz0"]."
    movehardware [server::getdata "requestedz"] true 
    set end [utcclock::seconds]
    log::info [format "finished initializing after %.1f seconds." [utcclock::diff $end $start]]    
  }

  proc stopactivitycommand {previousactivity} {
    set start [utcclock::seconds]
    log::info "stopping."
    if {
      [string equal $previousactivity "initializing"] ||
      [string equal $previousactivity "moving"]
    } {
      stophardware
    }
    set end [utcclock::seconds]
    log::info [format "finished stopping after %.1f seconds." [utcclock::diff $end $start]]    
  }

  proc resetactivitycommand {} {
    set start [utcclock::seconds]
    log::info "resetting."
    stophardware
    set end [utcclock::seconds]
    log::info [format "finished resetting after %.1f seconds." [utcclock::diff $end $start]]    
  }

  proc moveactivitycommand {check} {
    set start [utcclock::seconds]
    log::info "moving."
    log::info "moving to corrected position [server::getdata "requestedz0"]."
    setrequestedz
    movehardware [server::getdata "requestedz"] true 
    set end [utcclock::seconds]
    log::info [format "finished moving after %.1f seconds." [utcclock::diff $end $start]]    
  }

  ######################################################################

  proc start {} {
    server::setstatus "starting"
    opentsi::start $secondary::statuscommand secondary::updatedata
    server::newactivitycommand "starting" "started" secondary::startactivitycommand
  }

  ######################################################################

}

source [file join [directories::prefix] "lib" "tcs" "secondary.tcl"]
