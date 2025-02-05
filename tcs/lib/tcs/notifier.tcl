########################################################################

# This file is part of the UNAM telescope control system.

########################################################################

# Copyright © 2010, 2011, 2013, 2014, 2017, 2019 Alan M. Watson <alan@astro.unam.mx>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
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

package require "client"
package require "coroutine"
package require "server"
package require "utcclock"

package provide "notifier" 0.0

namespace eval "notifier" {

  variable servers [concat \
    [config::getvalue "notifier" "monitoredservers"] \
    [config::getvalue "instrument" "monitoreddetectors"] \
  ]
  variable problemtoleranceseconds [config::getvalue "notifier" "problemtoleranceseconds"]

  ######################################################################
  
  proc notify {} {
    log::warning "notifying: persistent problems with: [join $problemservers " "]."
  }
  
  ######################################################################
  
  variable lastnoproblemtimestamp [utcclock::combinedformat "now"]
  variable notified false
  
  proc monitorservers {} {
  
    variable servers
    variable problemtoleranceseconds
    variable lastnoproblemtimestamp
    variable problemnotified
    
    set problemservers {}
    foreach server $servers {

      if {[catch {client::update $server}]} {
        log::info "$server: no response to update."
        lappend problemservers $server
        continue
      }
      
      set status [client::getstatus $server]
      if {![string equal $status "ok"]} {
        log::info "$server: status is $status."
        lappend problemservers $server
        continue
      }

      set activity [client::getdata $server "activity"]
      if {[string equal $activity "error"]} {
        log::info "$server: activity is $activity."
        lappend problemservers $server
        continue
      }
        
    }
    
    if {[llength $problemservers] == 0} {
      log::info "no servers have problems."
    } else {
      log::info "problems with: [join $problemservers " "]."
    }
    
    if {[llength $problemservers] == 0} {
      set lastnoproblemtimestamp [utcclock::combinedformat "now"]
      set notified false
    } elseif {[utcclock::diff now $lastnoproblemtimestamp] > $problemtoleranceseconds} {
      if {!$notified} {
        notify
        set notified true
      }
    }

    server::setdata "servers"                  $servers
    server::setdata "problemservers"           $problemservers
    server::setdata "lastnoproblemtimestamp"   $lastnoproblemtimestamp
    server::setdata "timestamp"                [utcclock::combinedformat "now"]

  }

  ######################################################################

  set server::datalifeseconds 120

  proc start {} {
    server::setrequestedactivity "idle"
    server::setactivity "idle"
    server::setstatus "ok"
    coroutine::every 30000 notifier::monitorservers
  }

}
