########################################################################

# This file is part of the UNAM telescope control system.

# $Id: executorcoatlioan.tcl 3594 2020-06-10 14:55:51Z Alan $

########################################################################

# Copyright © 2018, 2019 Alan M. Watson <alan@astro.unam.mx>
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

package require "directories"

package provide "executorcoatlioan" 0.0

namespace eval "executor" {

  variable svnid {$Id}

  proc movefilterwheel {position} {
    set start [utcclock::seconds]
    log::info "moving filter wheel to $position."
    client::request "instrument" "movefilterwheel $position"
    client::wait "instrument"
    log::info [format "finished moving filter wheel after %.1f seconds." [utcclock::diff now $start]]
  }
  
}
