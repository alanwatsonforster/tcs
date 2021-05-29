########################################################################

# This file is part of the RATTEL telescope control system.

# $Id: selector.tcl 3601 2020-06-11 03:20:53Z Alan $

########################################################################

# Copyright © 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019 Alan M. Watson <alan@astro.unam.mx>
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

package require "alert"
package require "block"
package require "config"
package require "client"
package require "constraints"
package require "directories"
package require "log"
package require "project"
package require "server"
package require "visit"

package provide "selector" 0.0

namespace eval "selector" {

  variable svnid {$Id}

  ######################################################################

  variable offsethours [config::getvalue "selector" "offsethours"]

  ######################################################################

  variable mode           "disabled"
  variable filetype       ""
  variable filename       ""
  variable alertindex     0

  ######################################################################
  
  proc updatedata {} {
    variable mode
    variable filetype
    variable filename
    server::setdata "mode"             $mode
    server::setdata "filetype"         $filetype
    server::setdata "filename"         $filename
    server::setdata "selectordate"     [selectordate true]
    server::setdata "focustimestamp"   [constraints::focustimestamp]
    server::setdata "timestamp"        [utcclock::combinedformat now]
  }
  
  ######################################################################

  proc selectordate {{extended true}} {
    variable offsethours
    set seconds [expr {[utcclock::seconds] + 3600 * $offsethours}]
    return [utcclock::formatdate $seconds $extended]
  }

  ######################################################################

  proc getblockfilesdirectory {} {
    log::info "selector date is [selectordate true]."
    return [file join [directories::var] [selectordate false] "blocks"]
  }
  
  proc getblockfiles {} {
    if {[catch {
      set blockfilesdirectory [getblockfilesdirectory]
      set channel [open "|[directories::bin]/tcs getblockfiles \"$blockfilesdirectory\"" "r"]
      set blockfiles [read $channel]
      close $channel
      set blockfiles [split [string trimright $blockfiles "\n"] "\n"]
      log::debug "block files are \"$blockfiles\"."
    } message]} {
      log::error "unable to get block files: $message"
      set blockfiles {}
    }
    return $blockfiles
  }
  
  proc getalertfile {tail} {
    set alertfile [file join [directories::var] "alerts" $tail]
    set oldalertfile [file join [directories::var] "oldalerts" $tail]
    if {[file exists $alertfile]} {
      return $alertfile
    } elseif {[file exists $oldalertfile]} {
      return $oldalertfile
    } else {
      return $alertfile
    }
  }
  
  proc getalertfiles {rolled} {
    variable alertindex
    set names [glob -nocomplain -directory [file join [directories::var] "alerts"] "*"]
    set mtimesandnames {}
    foreach name $names {
      lappend mtimesandnames [list [file mtime $name] $name]
    }
    set mtimesandnames [lsort -decreasing -integer -index 0 $mtimesandnames]
    set names {}
    foreach mtimeandname $mtimesandnames {
      set name [lindex $mtimeandname 1]
      lappend names $name
    }
    log::debug "unrolled alertfile list is \"$names\"."
    if {$rolled} {
      log::debug "alertindex is $alertindex."
      set n [llength $names]
      if {$n != 0} {
        set names [concat \
          [lrange $names [expr {$alertindex % $n}] end] \
          [lrange $names 0 [expr {$alertindex % $n - 1}]] \
        ]
      }
      log::debug "rolled alertfile list is \"$names\"."
      set alertindex [expr {$alertindex + 1}]
    }
    return $names
  }
  
  ######################################################################

  proc isselectablealertfile {alertfile seconds} {
    if {[catch {
      set block [alert::alerttoblock [alert::readalertfile $alertfile]]
    } message]} {
      log::warning "error while reading alert file \"[file tail $alertfile]\": $message"
      return "invalid alert file."
    } 
    if {[constraints::check $block $seconds]} {
      return ""
    } else {
      return [constraints::why]
    }
  }
  
  proc selectalertfile {seconds} {
    foreach alertfile [getalertfiles true] {
      log::info "considering alert file \"[file tail $alertfile]\"."
      set why [isselectablealertfile $alertfile $seconds]
      if {[string equal $why ""]} {
        log::summary "selected alert file \"[file tail $alertfile]\"."
        return $alertfile
      }
      log::info "rejected alert file \"[file tail $alertfile]\": $why"
      coroutine::after 1
    }
    return ""
  }
    
  proc isselectableblockfile {blockfile seconds} {
    if {[catch {
      set block [block::readfile $blockfile]
    } message]} {
      log::warning "error while reading block file \"[file tail $blockfile]\": $message"
      log::warning "deleting block file \"[file tail $blockfile]\"."
      file delete -force $blockfile
      return "invalid block file."
    } 
    if {[constraints::check $block $seconds]} {
      return ""
    } else {
      return [constraints::why]
    }
  }
  
  proc selectblockfile {seconds} {
    swift::updatefavoredside
    foreach blockfile [getblockfiles] {
      log::info "considering block file \"[file tail $blockfile]\"."
      set why [isselectableblockfile $blockfile $seconds]
      if {[string equal $why ""]} {
        log::summary "selected block file \"[file tail $blockfile]\"."
        return $blockfile
      }
      log::info "rejected block file \"[file tail $blockfile]\": $why"
      coroutine::after 1
    }
    return ""
  }
  
  ######################################################################

  proc blockloop {} {
  
    variable mode
    variable filetype
    variable filename

    log::debug "blockloop: starting."

    set idled false
    set delay 0
    set recover false

    server::setstatus "ok" 
    
    while {true} {
    
      set filetype ""
      set filename ""
      updatedata
      server::setrequestedactivity "idle"      

      if {[string equal $mode "disabled"]} {
        log::debug "blockloop: disabled."
        server::setactivity "idle"
        set recover false
        coroutine::after 1000
        continue
      }
      
      if {$delay != 0} {
        log::debug "blockloop: waiting for $delay ms."
        server::setactivity "waiting"
        coroutine::after $delay
      }
      
      if {[string equal $mode "disabled"]} {
        continue
      }

      if {$recover} {
        log::warning "recovering."
        server::setactivity "recovering"      
        if {[catch {
          client::request "executor" "recover"
          client::wait "executor"
        } message]} {
          log::error "unable to recover: $message"
          set delay 60000
          set recover true
          continue
        }
        set recover false
      }
      
      if {[string equal $mode "disabled"]} {
        continue
      }

      log::info "stopping."
      server::setactivity "stopping"      
      if {[catch {
        client::request "executor" "stop"
        client::wait "executor"
      } message]} {
        log::error "unable to stop: $message"
        set recover true
        continue
      }

      if {[string equal $mode "disabled"]} {
        continue
      }

      log::summary "selecting."
      server::setactivity "selecting"
      set seconds [utcclock::seconds]
      if {[string equal "" [constraints::focustimestamp]]} {
        log::info "not focused."
      } else {
        log::info [format "%.0f seconds since last focused." [utcclock::diff $seconds [constraints::focustimestamp]]]
      }

      if {[string equal $mode "disabled"]} {
        continue
      }

      set filename [selectalertfile $seconds]
      if {![string equal $filename ""]} {
        set filetype "alert"
      } else {
        set filetype "block"
        set filename [selectblockfile $seconds]
      }
      updatedata
      
      if {[string equal $mode "disabled"]} {
        continue
      }

      if {[string equal $filename ""]} {
        log::summary "no alert or block selected."
        if {!$idled} {
          log::info "idling."
          server::setactivity "idling"
          if {[catch {
            client::request "executor" "idle"
            client::wait "executor"
          } message]} {
            log::error "unable to idle: $message"
            set delay 60000
            set recover true
            continue
          }
          set idled true
          log::info "finished idling."
        }
        set delay 60000
        continue
      }

      log::summary "executing $filetype file \"[file tail $filename]\"."
      server::setactivity "executing"
      set idled false
      if {[catch {
        client::request "executor" "execute $filetype $filename"
        client::wait "executor"
      } message]} {
        log::error "unable to execute: $message"
        set delay 60000
        set recover true
        continue
      }
      log::summary "finished executing $filetype file \"[file tail $filename]\"."
      set delay 0
    }
  
  }
  
  ######################################################################

  proc stop {} {
    log::summary "stopping."
    server::checkstatus
    server::checkactivityforstop
    server::setactivity [server::getrequestedactivity]
    log::summary "finished stopping."
    return
  }

  proc reset {} {
    log::summary "resetting."
    server::checkstatus
    server::checkactivityforreset
    server::setactivity [server::getrequestedactivity]
    log::summary "finished resetting."
    return
  }
  
  proc enable {} {
    log::summary "enabling."
    variable mode
    set mode "enabled"
    updatedata
    server::setrequestedactivity "idle"
    log::summary "finished enabling."
    return
  }
  
  proc disable {} {
    log::summary "disabling."
    variable mode
    set lastmode $mode
    set mode "disabled"
    updatedata
    if {[string equal $lastmode "enabled"]} {
      log::info "interrupting the executor."
      if {[catch {client::request "executor" "stop"} message]} {
        log::error "unable to interrupt the executor: $message"
      }
    }
    server::setactivity "idle"
    server::setrequestedactivity "idle"
    log::summary "finished disabling."
    return
  }
  
  proc respondtoalert {projectidentifier blockidentifier name origin identifier type alerttimestamp eventtimestamp enabled alpha delta equinox uncertainty} {
    variable mode

    log::summary "responding to alert for $name."

    if {![string equal $alerttimestamp ""]} {
      set alerttimestamp [utcclock::combinedformat [utcclock::scan $alerttimestamp]]
    }
    if {![string equal $eventtimestamp ""]} {
      set eventtimestamp [utcclock::combinedformat [utcclock::scan $eventtimestamp]]
    }

    log::info [format "projectidentifier is %s." $projectidentifier]
    log::info [format "blockidentifier is %s." $blockidentifier]
    log::info [format "origin/identifier/type are %s/%s/%s." $origin $identifier $type]
    log::info [format "alert timestamp is %s." [utcclock::format [utcclock::scan $alerttimestamp]]]
    if {![string equal $eventtimestamp ""]} {
      log::info [format "event timestamp is %s." [utcclock::format [utcclock::scan $eventtimestamp]]]
      log::info [format "event delay is %s." [utcclock::formatinterval [utcclock::diff $alerttimestamp $eventtimestamp]]]
    } else {
      log::info "no event timestamp."
    }
    if {![string equal $alpha ""] && ![string equal $delta ""] && ![string equal $equinox ""] && ![string equal $uncertainty ""]} {
      set alpha [astrometry::parsealpha $alpha]
      set delta [astrometry::parsedelta $delta]
      set equinox [astrometry::parseequinox $equinox]
      set uncertainty [astrometry::parsedistance $uncertainty]
      log::info [format "position is %s %s %s." [astrometry::formatalpha $alpha] [astrometry::formatdelta $delta] $equinox]
      log::info [format "uncertainty is %s." [astrometry::formatdistance $uncertainty]]
    }
    if {![string equal $enabled ""]} {
      if {$enabled} {
        log::info "this alert is enabled."
      } else {
        log::info "this alert is not enabled."
      }
    }
    
    set alertfile [getalertfile "$projectidentifier-$blockidentifier"]
    
    file mkdir [file dirname $alertfile]
    log::info [format "alert file is \"%s\"." $alertfile]
    set alertfileexists [file exists $alertfile]

    if {$alertfileexists} {
      set interrupt false
    } elseif {[string equal $enabled ""] || $enabled} {
      set interrupt true
    } else {
      set interrupt false
    }
    set channel [open $alertfile "a"]
    if {!$alertfileexists} {
      puts $channel [format "// Alert file \"%s\"." $alertfile]
      puts $channel [format "// Created at %s." [utcclock::format now]]
    } else {
      puts $channel [format "// Updated at %s." [utcclock::format now]]
    }
    puts $channel [format "\{"]
    if {![string equal "" $name]} {
      puts $channel [format "  \"name\": \"%s\"," $name]
    }
    puts $channel [format "  \"origin\": \"%s\"," $origin]
    puts $channel [format "  \"identifier\": \"%s\"," $identifier]
    puts $channel [format "  \"type\": \"%s\"," $type]
    puts $channel [format "  \"projectidentifier\": \"%s\"," $projectidentifier]
    if {
      ![string equal "" $alpha] && 
      ![string equal "" $delta] &&
      ![string equal "" $equinox] &&
      ![string equal "" $uncertainty]
    } {
      puts $channel [format "  \"alpha\": \"%s\"," [astrometry::formatalpha $alpha]]
      puts $channel [format "  \"delta\": \"%s\"," [astrometry::formatdelta $delta]]
      puts $channel [format "  \"equinox\": \"%s\"," $equinox]
      puts $channel [format "  \"uncertainty\": \"%s\"," [astrometry::formatdistance $uncertainty]]
    }
    if {![string equal "" $enabled]} {
      puts $channel [format "  \"enabled\": \"%s\"," $enabled]
    }
    if {![string equal "" $eventtimestamp]} {
      puts $channel [format "  \"eventtimestamp\": \"%s\"," $eventtimestamp]
    }
    puts $channel [format "  \"alerttimestamp\": \"%s\"" $alerttimestamp]
    puts $channel [format "\}"]

    close $channel
    
    if {!$interrupt} {
      log::summary "not interrupting the executor: interrupt is false."
    } elseif {[string equal $mode "disabled"]} {
      log::summary "not interrupting the executor: selector is disabled."
    } else {
      set why [isselectablealertfile $alertfile [utcclock::seconds]]
      if {![string equal "" $why]} {
        log::summary "not interrupting the executor: alert is not selectable: $why"
      } else {
        log::summary "interrupting the executor."
        if {[catch {client::request "executor" "stop"} message]} {
          log::error "unable to interrupt the executor: $message"
        }
        variable alertindex
        set alertindex 0
      }
    }
    
    if {!$alertfileexists && ([string equal "" $enabled] || $enabled)} {
      log::info "running alertscript."
      if {[catch {
        exec "[directories::etc]/alertscript" $name $origin $identifier $type
      } message]} {
        log::warning "alertscript failed: $message."
      }
      log::info "finished running alertscript."
    }

    log::summary "finished responding to alert."
    return
  }
  
  proc respondtolvcalert {projectidentifier blockidentifier name origin identifier type alerttimestamp eventtimestamp enabled skymapurl} {
    log::summary "responding to lvc alert."    
    if {![string equal $skymapurl ""]} {
      log::info [format "skymap url is %s." $skymapurl]
      set channel [open "|[directories::bin]/tcs newpgrp [directories::bin]/tcs lvcskymapfindpeak $skymapurl" "r"]
      chan configure $channel -buffering "line"
      chan configure $channel -encoding "ascii"
      set line [coroutine::gets $channel 0 100]
      catch {close $channel}
      if {[scan $line "%f %f %s" alpha delta equinox] != 3} {
        log::error "tcs lvcskymapfindpeak failed: $line."
        error "tcs lvcskymapfindpeak failed: $line."
      }
      set alpha [astrometry::formatalpha [astrometry::degtorad $alpha]]
      set delta [astrometry::formatdelta [astrometry::degtorad $delta]]
      set uncertainty "10d"
      log::info [format "peak position is %s %s %s." [astrometry::formatalpha $alpha] [astrometry::formatdelta $delta] $equinox]
    } else {
      set alpha       ""
      set delta       ""
      set equinox     ""
      set uncertainty ""
    }
    respondtoalert $projectidentifier $blockidentifier $name $origin $identifier $type $alerttimestamp $eventtimestamp $enabled $alpha $delta $equinox $uncertainty
    log::summary "finished responding to lvc alert."
    return
  }
  
  proc setfocused {} {
    log::info "setting focus timestamp."  
    constraints::setfocustimestamp [utcclock::combinedformat]
    updatedata
    log::info "finished setting focus timestamp."  
    return
  }
  
  proc setunfocused {} {
    log::info "unsetting focus timestamp." 
    constraints::setfocustimestamp ""
    updatedata
    log::info "finished unsetting focus timestamp."  
    return
  }
  
  proc writealerts {} {
    set tmpfilename [file join [directories::var] "alerts.json.[pid]"]
    set channel [open $tmpfilename "w"]
    puts $channel "\["
    set first true
    foreach alertfile [getalertfiles false] {
      if {!$first} {
        puts $channel ","
      }
      puts $channel [tojson::object [alert::readalertfile $alertfile] tojson::string]
      set first false
    }
    puts $channel "\]"
    close $channel
    file rename -force -- $tmpfilename [file join [directories::var] "alerts.json"]
  }
  
  ######################################################################

  set server::datalifeseconds 0

  proc start {} {
    server::setstatus "starting"
    server::setactivity "starting"
    server::setrequestedactivity "idle"
    updatedata
    after idle {
      coroutine selector::blockloopcoroutine selector::blockloop
    }
  }

}
