########################################################################

# This file is part of the UNAM telescope control system.

# $Id: fitfocus.tcl 3557 2020-05-22 18:23:30Z Alan $

########################################################################

# Copyright © 2014, 2017, 2019 Alan M. Watson <alan@astro.unam.mx>
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

package provide "fitfocus" 0.0

namespace eval "fitfocus" {

  variable svnid {$Id}

  ######################################################################

  # The code finds the least-squares fitting parabola, with 2-sigma
  # rejection, to the FWHM, and the minium focus. (Formally, it determines
  # the turning point, which might be the maximum.)
  #
  # The least-square parabola is determined as follows. Given a parabola y
  # = a + b * x + c * x * x, the least-squares fitting coefficients are
  # given by:
  #
  # S01 = S00 * a + S10 * b + S20 * c,
  # S11 = S10 * a + S20 * b + S30 * c, and
  # S21 = S20 * a + S30 * b + S40 * c.
  #
  # in which Smn is the sum of x^m * y^n. This set of equations can be 
  # reduced to:
  #
  # A0 = B0 * b + C0 * c
  # A1 = B1 * b + C1 * c
  #
  # in which
  #
  # A0 = S01 * S10 - S11 * S00,
  # B0 = S10 * S10 - S20 * S00,
  # C0 = S20 * S10 - S30 * S00,
  #
  # A1 = S11 * S20 - S21 * S10,
  # B1 = S20 * S20 - S30 * S10, and
  # C1 = S30 * S20 - S40 * S10.
  #
  # Solving these, we have:
  #
  # c = (A0 * B1 - A1 * B0) / (B1 * C0 - B0 * C1),
  # b = (A0 - C0 * c) / B0, and
  # a = (S01 - S10 * b - S20 * c) / S00.
  
  variable maxabschi 2.0
  variable maxfwhm 15.0
  
  proc fit {xlist ylist chilist} {
    variable maxabschi
    variable maxfwhm
    set S00 0.0
    set S10 0.0
    set S20 0.0
    set S30 0.0
    set S40 0.0
    set S01 0.0
    set S11 0.0
    set S21 0.0
    foreach x $xlist y $ylist chi $chilist {
      log::debug "fitfocus: x = $x y = $y chi = $chi."
      if {$y <= $maxfwhm && abs($chi) <= $maxabschi} {
        set S00 [expr {$S00 + 1}]
        set S10 [expr {$S10 + $x}]
        set S20 [expr {$S20 + $x * $x}]
        set S30 [expr {$S30 + $x * $x * $x}]
        set S40 [expr {$S40 + $x * $x * $x * $x}]
        set S01 [expr {$S01 + $y}]
        set S11 [expr {$S11 + $x * $y}]
        set S21 [expr {$S21 + $x * $x * $y}]
      }
    }
    set A0 [expr {$S01 * $S10 - $S11 * $S00}]
    set B0 [expr {$S10 * $S10 - $S20 * $S00}]
    set C0 [expr {$S20 * $S10 - $S30 * $S00}]
    set A1 [expr {$S11 * $S20 - $S21 * $S10}]
    set B1 [expr {$S20 * $S20 - $S30 * $S10}]
    set C1 [expr {$S30 * $S20 - $S40 * $S10}]
    set c [expr {($A0 * $B1 - $A1 * $B0) / ($B1 * $C0 - $B0 * $C1)}]
    set b [expr {($A0 - $C0 * $c) / $B0}]
    set a [expr {($S01 - $S10 * $b - $S20 * $c) / $S00}]
    return [list $a $b $c]
  }
  
  proc findmin {xlist ylist} {
    # For brevity, we use x for z0 and y for FWHM.
    variable maxabschi
    variable maxfwhm
    log::debug "fitfocus: maxabschi = $maxabschi."
    log::debug "fitfocus: maxfwhm = $maxfwhm."
    if {[llength $xlist] != [llength $ylist]} {
      error "xlist and ylist do not have the same length."
    }
    set n [llength $xlist]
    log::debug "fitfocus: n = $n."
    set chilist [lrepeat $n 0.0]
    foreach iteration {0 1 2} {
      set coeffientslist [fit $xlist $ylist $chilist]
      set a [lindex $coeffientslist 0]
      set b [lindex $coeffientslist 1]
      set c [lindex $coeffientslist 2]
      log::debug "fitfocus: iteration $iteration: a = $a b = $b c = $c."
      set sdyy 0.0
      foreach x $xlist y $ylist {
        set dy [expr {$y - ($a + $b * $x + $c * $x * $x)}]
        set sdyy [expr {$sdyy + $dy * $dy}]
      }
      set sigma [expr {sqrt($sdyy / ($n - 1))}]
      log::debug "fitfocus: iteration $iteration: sigma = $sigma."
      set chilist {}
      foreach x $xlist y $ylist {
        set dy [expr {$y - ($a + $b * $x + $c * $x * $x)}]
        if {$sigma != 0} {
          lappend chilist [expr {$dy / $sigma}]
        } else {
          lappend chilist 0
        }
      }
    }
    foreach x $xlist y $ylist chi $chilist {
      if {$y <= $maxfwhm && abs($chi) <= $maxabschi} {
        log::info [format "fitfocus: FWHM = %4.1f pixels at %d (chi = %+6.2f)" $y $x $chi]
      } else {
        log::info [format "fitfocus: FWHM = %4.1f pixels at %d (chi = %+6.2f rejected)" $y $x $chi]
      }
    }
    set minx [expr {int(-$b / (2 * $c))}]
    set miny [expr {$a + $b * $minx + $c * $minx * $minx}]
    if {$c < 0} {
      error "turning point is maximum."
    }
    log::info [format "fitfocus: model minimum: FWHM = %.1f pixels at %d." $miny $minx]
    return $minx
  }
  
  ######################################################################
    
}
