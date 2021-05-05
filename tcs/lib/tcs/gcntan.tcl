########################################################################

# This file is part of the RATTEL telescope control system.

# $Id: gcntan.tcl 3601 2020-06-11 03:20:53Z Alan $

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

package require "astrometry"
package require "project"
package require "server"

package provide "gcntan" 0.0

namespace eval "gcntan" {

  variable svnid {$Id}

  ######################################################################  

  variable packetport [config::getvalue "gcntan" "serverpacketport"]
  
  # We should get an imalive packet every 60 seconds.
  variable packettimeout 300000
  
  variable swiftalertprojectidentifier   [config::getvalue "gcntan" "swiftalertprojectidentifier"  ]
  variable fermialertprojectidentifier   [config::getvalue "gcntan" "fermialertprojectidentifier"  ]
  variable lvcalertprojectidentifier     [config::getvalue "gcntan" "lvcalertprojectidentifier"    ]
  variable hawcalertprojectidentifier    [config::getvalue "gcntan" "hawcalertprojectidentifier"   ]
  variable icecubealertprojectidentifier [config::getvalue "gcntan" "icecubealertprojectidentifier"]

  ######################################################################

  server::setdata "swiftalpha"   ""
  server::setdata "swiftdelta"   ""
  server::setdata "swiftequinox" ""
  
  ######################################################################
  
  # GCN/TAN packets are defined in: http://gcn.gsfc.nasa.gov/sock_pkt_def_doc.html

  # Symbolic names used here are the names in the GCN/TAN document
  # converted to lower case and with underbars elided.
  
  # Packets are 40 packed 32-bit two's complement integers.
  variable packetlength 160
  variable packetformat I40

  proc readloop {channel} {

    variable packetlength
    variable packetformat
    variable packettimeout
  
    chan configure $channel -translation "binary"
    chan configure $channel -blocking false

    while {true} {
        
      set rawpacket [coroutine::read $channel $packetlength $packettimeout]
        
      set timestamp [utcclock::combinedformat]

      if {[string length $rawpacket] != $packetlength} {
        log::error "packet length is [string length $rawpacket]."
        break
      }
    
      server::setdata "timestamp" $timestamp
      server::setactivity [server::getrequestedactivity]
      server::setstatus "ok"
        
      binary scan $rawpacket $packetformat packet
      
      switch [processpacket $timestamp $packet] {
        "echo" {
          echorawpacket $channel $rawpacket
        }
        "close" {
          break
        }
      }

    }
    
    catch {close $channel}

  } 

  proc processpacket {timestamp packet} {

    log::debug [format "packet is %s." $packet]
    set type [type $packet]
    log::debug [format "packet type is \"%s\"." $type]

    switch $type {

      "unknown" {
        # Do not echo back a bad packet.
        log::warning [format "unknown packet type: \"%s\"." [field0 $packet 0]]
        return "bad"
      }

      "imalive" {
        log::info [format "received %s packet." $type]
        return "echo"
      }

      "kill" {
        log::info [format "received %s packet." $type]
        # Close connection without echoing the packet.
        return "close"
      }

      "swiftactualpointdir" {
        log::info [format "received %s packet." $type]
        set alpha       [swiftalpha   $packet]
        set delta       [swiftdelta   $packet]
        set equinox     [swiftequinox $packet]
        server::setdata "swiftalpha"   $alpha
        server::setdata "swiftdelta"   $delta
        server::setdata "swiftequinox" $equinox
        log::info [format "%s: position is %s %s %s." $type [astrometry::formatalpha $alpha] [astrometry::formatdelta $delta] $equinox]            
        return "echo"
      }
       
      "swiftbatgrbpostest" -
      "swiftbatquicklookposition" - 
      "swiftbatgrbposition" -
      "swiftxrtposition" - 
      "swiftuvotposition" {
        log::summary [format "received %s packet." $type]
        variable swiftalertprojectidentifier
        set projectidentifier  $swiftalertprojectidentifier
        set blockidentifier    [swifttrigger         $packet]
        set name               [swiftgrbname         $packet]
        set origin             "swift"
        set identifier         [swifttrigger         $packet]
        set test               [swifttest            $packet]
        set eventtimestamp     [swifteventtimestamp  $packet]
        set alpha              [swiftalpha           $packet]
        set delta              [swiftdelta           $packet]
        set equinox            [swiftequinox         $packet]
        set uncertainty        [swiftuncertainty     $packet]
        set grb                [swiftgrb             $packet]
        set retraction         [swiftretraction      $packet]
        respondtogrbalert $test $projectidentifier $blockidentifier $name $origin $identifier $type $timestamp $eventtimestamp $retraction $grb $alpha $delta $equinox $uncertainty
        return "echo"
      }

      "fermigbmfltpos" -
      "fermigbmgndpos" -
      "fermigbmfinpos" -
      "fermigbmpostest" {
        log::summary [format "received %s packet." $type]
        variable fermialertprojectidentifier
        set projectidentifier  $fermialertprojectidentifier
        set blockidentifier    [fermitrigger         $packet]
        set name               [fermigrbname         $packet]
        set origin             "fermi"
        set identifier         [fermitrigger         $packet]
        set test               [fermitest            $packet]
        set eventtimestamp     [fermieventtimestamp  $packet]
        set alpha              [fermialpha           $packet]
        set delta              [fermidelta           $packet]
        set equinox            [fermiequinox         $packet]
        set uncertainty        [fermigbmuncertainty  $packet]
        set grb                [fermigrb             $packet]
        set retraction         [fermiretraction      $packet]
        respondtogrbalert $test $projectidentifier $blockidentifier $name $origin $identifier $type $timestamp $eventtimestamp $retraction $grb $alpha $delta $equinox $uncertainty
        return "echo"
      }
       
      "fermilatgrbpostest" -
      "fermilatgrbposupd" -
      "fermilatgnd" -
      "fermilatoffline" {
        log::summary [format "received %s packet." $type]
        variable fermialertprojectidentifier
        set projectidentifier  $fermialertprojectidentifier
        set blockidentifier    [fermitrigger         $packet]
        set name               [fermigrbname         $packet]
        set origin             "fermi"
        set identifier         [fermitrigger         $packet]
        set test               [fermitest            $packet]
        set eventtimestamp     [fermieventtimestamp  $packet]
        set alpha              [fermialpha           $packet]
        set delta              [fermidelta           $packet]
        set equinox            [fermiequinox         $packet]
        set uncertainty        [fermilatuncertainty  $packet]
        set grb                [fermigrb             $packet]
        set retraction         [fermiretraction      $packet]
        respondtogrbalert $test $projectidentifier $blockidentifier $name $origin $identifier $type $timestamp $eventtimestamp $retraction $grb $alpha $delta $equinox $uncertainty
        return "echo"
      }
      
      "hawcburstmonitor" {
        log::summary [format "received %s packet." $type]
        variable hawcalertprojectidentifier
        set projectidentifier  $hawcalertprojectidentifier
        set blockidentifier    [hawctrigger        $packet]
        set name               [hawcgrbname        $packet]
        set origin             "hawc"
        set identifier         [hawctrigger        $packet]
        set test               [hawctest           $packet]
        set eventtimestamp     [hawceventtimestamp $packet]
        set alpha              [hawcalpha          $packet]
        set delta              [hawcdelta          $packet]
        set equinox            [hawcequinox        $packet]
        set uncertainty        [hawcuncertainty    $packet]
        set grb                [hawcgrb            $packet]
        set retraction         [hawcretraction     $packet]
        respondtogrbalert $test $projectidentifier $blockidentifier $name $origin $identifier $type $timestamp $eventtimestamp $retraction $grb $alpha $delta $equinox $uncertainty
        return "echo"
      }

      "hawcburstmonitor" {
        log::summary [format "received %s packet." $type]
        variable hawcalertprojectidentifier
        set projectidentifier  $hawcalertprojectidentifier
        set blockidentifier    [hawctrigger        $packet]
        set name               [hawcgrbname        $packet]
        set origin             "hawc"
        set identifier         [hawctrigger        $packet]
        set test               [hawctest           $packet]
        set eventtimestamp     [hawceventtimestamp $packet]
        set alpha              [hawcalpha          $packet]
        set delta              [hawcdelta          $packet]
        set equinox            [hawcequinox        $packet]
        set uncertainty        [hawcuncertainty    $packet]
        set grb                [hawcgrb            $packet]
        set retraction         [hawcretraction     $packet]
        respondtogrbalert $test $projectidentifier $blockidentifier $name $origin $identifier $type $timestamp $eventtimestamp $retraction $grb $alpha $delta $equinox $uncertainty
        return "echo"
      }

      "icecubeastrotrackgold" -
      "icecubeastrotrackbronze" -
      "icecubecascade" {
        log::summary [format "received %s packet." $type]
        variable icecubealertprojectidentifier
        set projectidentifier  $icecubealertprojectidentifier
        set blockidentifier    [icecubetrigger        $packet]
        set name               [icecubegrbname        $packet]
        set origin             "icecube"
        set identifier         [icecubetrigger        $packet]
        set test               [icecubetest           $packet]
        set eventtimestamp     [icecubeeventtimestamp $packet]
        set alpha              [icecubealpha          $packet]
        set delta              [icecubedelta          $packet]
        set equinox            [icecubeequinox        $packet]
        set uncertainty        [icecubeuncertainty    $packet]
        set grb                [icecubegrb            $packet]
        set retraction         [icecuberetraction     $packet]
        respondtogrbalert $test $projectidentifier $blockidentifier $name $origin $identifier $type $timestamp $eventtimestamp $retraction $grb $alpha $delta $equinox $uncertainty
        return "echo"      
      }

      "lvcpreliminary" -
      "lvcinitial" -
      "lvcupdate" {
        log::summary [format "received %s packet." $type]
        return "echo"
        variable lvcalertprojectidentifier
        set projectidentifier  $lvcalertprojectidentifier
        set blockidentifier    [lvctrigger         $packet]
        set name               [lvcname            $packet]
        set origin             "lvc"
        set identifier         [lvcidentifier      $packet]
        set eventtimestamp     [lvceventtimestamp  $packet]
        set test               [lvctest            $packet]
        set skymapurl          [lvcurl             $packet]
        respondtolvcalert $test $projectidentifier $blockidentifier $name $origin $identifier $type $timestamp $eventtimestamp false $skymapurl
        return "echo"
      }

      "lvcretraction" {
        log::summary [format "received %s packet." $type]
        return "echo"
        variable lvcalertprojectidentifier
        set projectidentifier  $lvcalertprojectidentifier
        set blockidentifier    [lvctrigger          $packet]
        set name               [lvcname             $packet]
        set origin             "lvc"
        set identifier         [lvcidentifier       $packet]
        set eventtimestamp     [lvceventtimestamp   $packet]
        set test               [lvctest             $packet]
        respondtolvcalert $test $projectidentifier $blockidentifier $name $origin $identifier $type $timestamp $eventtimestamp true ""
        return "echo"
      }
       
      "lvccounterpart" {
        log::summary [format "received %s packet." $type]
        return "echo"
        variable lvcalertprojectidentifier
        set projectidentifier  $lvcalertprojectidentifier
        set blockidentifier    [lvctrigger          $packet]
        set name               [lvcname             $packet]
        set origin             "lvc"
        set identifier         [lvcidentifier       $packet]
        set eventtimestamp     [lvceventtimestamp   $packet]
        set test               [lvctest             $packet]
        log::info [format "%s: test is %s." $type $test]
        log::info [format "%s: project identifier is \"%s\"." $type $projectidentifier]
        log::info [format "%s: block identifier is %s." $type $blockidentifier ]
        log::info [format "%s: name is %s." $type $name]
        log::info [format "%s: origin/identifier/type are %s/%s/%s." $type $origin $identifier $type]
        log::info [format "%s: event timestamp is %s." $type $eventtimestamp]
        return "echo"
      }
       
      default {
        log::info [format "received %s packet." $type]
        return "echo"
      }

    }

  }
  
  proc echorawpacket {channel rawpacket} {
    log::debug "echoing packet."
    puts -nonewline $channel $rawpacket
    flush $channel
  }
  
  ######################################################################
  
  proc logresponse {test retraction grb message} {
    if {$test} {
      log::debug "test: $message"
    } elseif {![string equal $retraction ""] && $retraction} {
      log::summary $message
    } elseif {![string equal $grb ""] && !$grb} {
      log::info $message
    } else {
      log::summary $message
    }
  }
  
  proc respondtogrbalert {test projectidentifier blockidentifier name origin identifier type alerttimestamp eventtimestamp retraction grb alpha delta equinox uncertainty} {
    logresponse $test $retraction $grb [format "%s: name is %s." $type $name]
    if {$test} {
      logresponse $test $retraction $grb [format "%s: this is a test." $type]
    } else {
      logresponse $test $retraction $grb [format "%s: this is not a test." $type]
    }
    set enabled ""
    if {![string equal $grb ""]} {
      if {$grb} {
        logresponse $test $retraction $grb [format "%s: this is a GRB." $type]
        set enabled true
      } else {
        logresponse $test $retraction $grb [format "%s: this is not a GRB." $type]
        set enabled false
      }
    }
    if {![string equal $retraction ""] && $retraction} {
      logresponse $test $retraction $grb [format "%s: this is a retraction." $type]
      set enabled false
    }
    logresponse $test $retraction $grb [format "%s: origin/identifier/type are %s/%s/%s." $type $origin $identifier $type]
    logresponse $test $retraction $grb [format "%s: alert timestamp is %s." $type [utcclock::format $alerttimestamp]] 
    if {![string equal $eventtimestamp ""]} {
      logresponse $test $retraction $grb [format "%s: event timestamp is %s." $type [utcclock::format $eventtimestamp]]
      logresponse $test $retraction $grb [format "%s: event delay is %s." $type [utcclock::formatinterval [utcclock::diff $alerttimestamp $eventtimestamp]]]
    } else {
      logresponse $test $retraction $grb [format "%s: no event timestamp." $type]
    }
    logresponse $test $retraction $grb [format "%s: position is %s %s %s." $type [astrometry::formatalpha $alpha] [astrometry::formatdelta $delta] $equinox]
    logresponse $test $retraction $grb [format "%s: 90%% uncertainty is %s in radius." $type [astrometry::formatdistance $uncertainty]]
    logresponse $test $retraction $grb [format "%s: project identifier is %s." $type $projectidentifier]
    logresponse $test $retraction $grb [format "%s: block identifier is %d." $type $blockidentifier]
    if {$test} {
      logresponse $test $retraction $grb [format "%s: not requesting selector to respond: this is a test packet." $type]
    } elseif {[string equal $projectidentifier ""]} {
      logresponse $test $retraction $grb [format "%s: not requesting selector to respond: no project identifier." $type]
    } else {
      logresponse $test $retraction $grb [format "%s: requesting selector to respond." $type]
      if {[catch {
        client::request "selector" [list respondtoalert $projectidentifier $blockidentifier $name $origin $identifier $type $alerttimestamp $eventtimestamp $enabled $alpha $delta $equinox $uncertainty]
      } result]} {
        log::warning [format "%s: unable to request selector: %s" $type $result]
      }
    }
  }
  
  proc respondtolvcalert {test projectidentifier blockidentifier name origin identifier type alerttimestamp eventtimestamp retraction skymapurl} {
    logresponse $test $retraction true [format "%s: name is %s." $type $name]
    if {$test} {
      logresponse $test $retraction true [format "%s: this is a test." $type]
    } else {
      logresponse $test $retraction true [format "%s: this is not a test." $type]
    }
    if {![string equal $retraction ""] && $retraction} {
      logresponse $test $retraction true [format "%s: this is a retraction." $type]
      set enabled false
    } else {
      set enabled true
    }
    logresponse $test $retraction true [format "%s: origin/identifier/type are %s/%s/%s." $type $origin $identifier $type]
    logresponse $test $retraction true [format "%s: alert timestamp is %s." $type [utcclock::format $alerttimestamp]] 
    logresponse $test $retraction true [format "%s: event timestamp is %s." $type [utcclock::format $eventtimestamp]]
    logresponse $test $retraction true [format "%s: event delay is %s." $type [utcclock::formatinterval [utcclock::diff $alerttimestamp $eventtimestamp]]]
    if {![string equal $skymapurl ""]} {
      logresponse $test $retraction true [format "%s: skymap url is %s." $type $skymapurl]
    }
    logresponse $test $retraction true [format "%s: project identifier is \"%s\"." $type $projectidentifier]
    logresponse $test $retraction true [format "%s: block identifier is %d." $type $blockidentifier]
    if {$test} {
      logresponse $test $retraction true [format "%s: not requesting selector to respond: this is a test packet." $type]
    } elseif {[string equal $projectidentifier ""]} {
      logresponse $test $retraction true [format "%s: not requesting selector to respond: no project identifier." $type]
    } else {
      logresponse $test $retraction true [format "%s: requesting selector to respond." $type]
      if {[catch {
        client::request "selector" [list respondtolvcalert $projectidentifier $blockidentifier $name $origin $identifier $type $alerttimestamp $eventtimestamp $enabled $skymapurl]
      } result]} {
        log::warning [format "%s: unable to request selector: %s" $type $result]
      }
    }
  }
  
  ######################################################################

  # These procedures are designed to work with the following packet types:
  #
  #   swiftbatgrbpostest
  #   swiftbatquicklookposition
  #   swiftbatgrbposition
  #   swiftxrtposition
  #   swiftuvotposition
  
  proc swifttest {packet} {
    switch [type $packet] {
      "swiftbatgrbpostest" {
        return true
      }
      "swiftbatquicklookposition" -
      "swiftbatgrbposition" -
      "swiftxrtposition" -
      "swiftuvotposition" {
        return false
      }
      default {
        error "unexpected packet type \"$packet\"."
      }
    }
  }

  proc swifttrigger {packet} {
    return [expr {[field0 $packet 4] & 0xffffff}]
  }
  
  proc swiftgrbname {packet} {
    set timestamp [swifteventtimestamp $packet]
    if {[string equal $timestamp ""]} {
      return ""
    }
    if {[scan $timestamp "%d-%d-%dT%d:%d:%f" year month day hours minutes seconds] != 6} {
      error "unable to scan timestamp \"$timestamp\"."
    }
    set dayfraction [expr {($hours + $minutes / 60.0 + $seconds / 3600.0) / 24.0}]
    set identifier [format "Swift GRB %02d%02d%02d.%03d" [expr {$year % 100}] $month $day [expr {int($dayfraction * 1000)}]]
    return $identifier
  }

  proc swifteventtimestamp {packet} {
    switch [type $packet] {
      "swiftbatquicklookposition" -
      "swiftbatgrbposition" -
      "swiftbatgrbpostest" {
        return [utcclock::combinedformat [seconds $packet 5]]
      }
      "swiftxrtposition" -
      "swiftuvotposition" {
        return ""
      }
      default {
        error "unexpected packet type \"$packet\"."
      }
    }
  }
  
  proc swiftalpha {packet} {
    return [astrometry::foldradpositive [astrometry::degtorad [field4 $packet 7]]]
  }
  
  proc swiftdelta {packet} {
    return [astrometry::degtorad [field4 $packet 8]]
  }
  
  proc swiftequinox {packet} {
    return 2000
  }
  
  proc swiftuncertainty {packet} {
    # BAT, XRT, and UVOT give 90% radius
    set uncertainty [astrometry::degtorad [field4 $packet 11]]
    return [format "%.1fas" [astrometry::radtoarcsec $uncertainty]]
  }

  proc swiftgrb {packet} {
    switch [type $packet] {
      "swiftbatgrbposition" -
      "swiftbatgrbpostest" {
        if {([field0 $packet 18] >> 1) & 1} {
          return true
        } else {
          return false
        }
      }
      "swiftbatquicklookposition" -
      "swiftxrtposition" -
      "swiftuvotposition" {
        return ""
      }
      default {
        error "unexpected packet type \"$packet\"."
      }
    }
  }
  
  proc swiftretraction {packet} {
    switch [type $packet] {
      "swiftbatquicklookposition" {
        return ""
      }
      "swiftbatgrbpostest" -
      "swiftbatgrbposition" -
      "swiftxrtposition" -
      "swiftuvotposition" {
        if {([field0 $packet 18] >> 5) & 1} {
          return true
        } else {
          return false
        }
      }
      default {
        error "unexpected packet type \"$packet\"."
      }
    }
  }

  ######################################################################

  # These procedures are designed to work with the following packet types:
  #
  #  fermigbmpostest
  #  fermigbmfltpos
  #  fermigbmgndpos
  #  fermigbmfinpos
  #  fermilatgrbpostest
  #  fermilatgrbposupd
  #  fermilatgnd
  #  fermilatoffline

  proc fermitest {packet} {
    switch [type $packet] {
      "fermigbmpostest" -
      "fermilatgrbpostest" {
        return true
      }
      "fermigbmfltpos" -
      "fermigbmgndpos" -
      "fermigbmfinpos" -
      "fermilatgrbposupd" - 
      "fermilatgnd" - 
      "fermilatoffline" {
        return false
      }
      default {
        error "unexpected packet type \"$packet\"."
      }
    }
  }

  proc fermitrigger {packet} {
    return [field0 $packet 4]
  }

  proc fermigrbname {packet} {
    set timestamp [fermieventtimestamp $packet]
    if {[string equal $timestamp ""]} {
      return ""
    }
    if {[scan $timestamp "%d-%d-%dT%d:%d:%f" year month day hours minutes seconds] != 6} {
      error "unable to scan timestamp \"$timestamp\"."
    }
    switch -glob [type $packet] {
      "fermigbm*" {
        set dayfractioninthousandths [field0 $packet 32]
        set identifier [format "Fermi GRB %02d%02d%02d.%03d" [expr {$year % 100}] $month $day $dayfractioninthousandths]
      }
      "fermilat*" {
        set dayfraction [expr {($hours + $minutes / 60.0 + $seconds / 3600.0) / 24.0}]
        set identifier [format "Fermi GRB %02d%02d%02d.%03d" [expr {$year % 100}] $month $day [expr {int($dayfraction * 1000)}]]
      }
    }
    return $identifier
  }

  proc fermieventtimestamp {packet} {
    return [utcclock::combinedformat [seconds $packet 5]]
  }
  
  proc fermialpha {packet} {
    return [astrometry::foldradpositive [astrometry::degtorad [field4 $packet 7]]]
  }
  
  proc fermidelta {packet} {
    return [astrometry::degtorad [field4 $packet 8]]
  }

  proc fermiequinox {packet} {
    return 2000
  }

  proc fermigbmuncertainty {packet} {

    set type [type $packet]

    # We work in degrees here.

    set rawuncertainty [field4 $packet 11]
    log::info [format "%s: raw uncertainty is %.1fd in radius." $type $rawuncertainty]  
    
    # We want the radius containing 90% of the probability. There are
    # two complications here.
    # 
    # First, the GCN notices distribute a raw sigma defined to be the "radius
    # containing 68% of the probability" (see the start of section 5 of
    # Connaughton et al. 2015). This is not the standard sigma in a 2-D Gaussian
    # with p(x,y) = A exp(-0.5*(r/sigma)^2).
    # 
    # Second, we need to add the systematic uncertainty. The core and
    # tail are both Gaussians and a certain fraction of the probability
    # is in the core. The parameters are given in Table 3 of Goldstein
    # et al. (2020). They are different for long and short GRBs,
    # but we use the global values. This could be improved based on the
    # classification in the GCN notice.
    #
    # So, we need to convert the raw uncertainty to a true sigma, then account
    # for the systematic uncertainty, and then determine the radius containing
    # 90% of the probability.
    #
    # In this, calculation, we use the result that the probability contained
    # within a radius r of a 2-D Gaussian with p(x,y) = A exp(-0.5*(r/sigma)^2)
    # is (1-exp(-0.5*(r/sigma)^2)).
    #
    # The mapping from raw 68% statistical uncertainty to true 90% uncertainty, including
    # systematics, is then:
    #
    #   raw  true
    #   0.0   4.8
    #   1.0   4.9
    #   2.0   5.4
    #   3.0   6.2
    #   4.0   7.2
    #   5.0   8.4
    #   6.0   9.6
    #   7.0  10.9
    #   8.0  12.2
    #   9.0  13.5
    #  10.0  14.9
    #  15.0  21.8
    #  20.0  28.8
    #  25.0  35.8
    #  30.0  42.9
    #
    # For well-localized bursts (raw uncertainty of 2 degrees or less), the
    # dominant component of the true uncertainty is the systematic uncertainty
    # of about 5 degrees. For poorly-localisted bursts (raw uncertainty of 10
    # degrees or more), the dominant correction is the factor of roughly 1.4
    # between the 68% radius and the 90% radius.
    #
    # References:
    #
    # Connaughton et al. (2015): https://ui.adsabs.harvard.edu/abs/2015ApJS..216...32C/abstract
    # Goldstein et al. (2020): https://ui.adsabs.harvard.edu/abs/2020ApJ...895...40G/abstract

    # These parameters characterize the systematic uncertainty. F is the
    # fraction in the core. C and T are the sigmas of the core and tail. See
    # Goldstein et al. (2020).
        
    set F 0.517
    set C 1.81
    set T 4.07
    
    set R $rawuncertainty
    
    # Convert from "radius containing 68% of the probability" to a true sigma.
    set R [expr {$R / sqrt(-2 * log(1-0.68))}]
    set C [expr {$C / sqrt(-2 * log(1-0.68))}]
    set T [expr {$T / sqrt(-2 * log(1-0.68))}]

    # Add the systematic and statistical uncertainties in quadrature.
    set C [expr {sqrt($R * $R + $C * $C)}]
    set T [expr {sqrt($R * $R + $T * $T)}]

    # Find the radius containing 90% of the probability.
    set P 0.9
    set r 0
    set dr 0.01
    while {true} {
      set p [expr {$F * (1 - exp(-0.5*($r*$r)/($C*$C))) + (1 - $F) * (1 - exp(-0.5*($r*$r)/($T*$T)))}]
      if {$p > $P} {
        set r [expr {$r - $dr}]      
        break
      }
      set r [expr {$r + $dr}]
    }

    set uncertainty $r
    log::info [format "%s: 90%% uncertainty is %.1fd in radius." $type $uncertainty]  

    return [format "%.1fd" $uncertainty]
  }
  
  proc fermilatuncertainty {packet} {
    # LAT gives 90% radius.
    set uncertainty [astrometry::degtorad [field4 $packet 11]]
    return [format "%.1fam" [astrometry::radtoarcmin $uncertainty]]
  }
  
  proc fermiretraction {packet} {
    if {([field0 $packet 18] >> 5) & 1} {
      return true
    } else {
      return false
    }
  }
  
  proc fermigrb {packet} {
    set type [type $packet]
    switch [type $packet] {
      "fermigbmpostest" -
      "fermigbmfltpos" {
        set sigma [fermigbmtriggersigma $packet]
        log::info [format "%s: %.1f sigma." $type $sigma]
        set class            [fermigbmclass $packet 23]
        set classprobability [fermigbmclassprobability $packet 23]
        log::info [format "%s: class is \"%s\" (%.0f%%)." $type $class [expr {$classprobability * 100}]]
        if {[string equal $class "grb"]} {
          return true
        } else {
          return false
        }
      }
      "fermigbmgndpos" {
        set sigma [fermigbmtriggersigma $packet]
        log::info [format "%s: trigger sigma is %.1f." $type $sigma]
        if {[fermiretraction $packet]} {
          return false
        } else {
          log::info [format "%s: the duration is %s." $type [fermigbmgrbduration $packet]]          
          return true
        }
      }
      "fermigbmfinpos" {
        if {[fermiretraction $packet]} {
          return false
        } else {
          log::info [format "%s: the duration is %s." $type [fermigbmgrbduration $packet]]          
          return true
        }
      }
      "fermilatgrbposupd" -
      "fermilatgrbpostest" {
        set temporalsignificance [field0 $packet 25]
        set imagesignificance    [field0 $packet 26]
        set totalsignificance    [expr {$temporalsignificance + $imagesignificance}]
        log::info [format "%s: temporal significance is %d." $type $temporalsignificance]
        log::info [format "%s: image significance is %d."    $type $imagesignificance]
        log::info [format "%s: total significance is %d."    $type $totalsignificance]
        if {$totalsignificance >= 120} {
          return true
        } else {
          return false
        }
      }
      "fermilatgnd" {
        # fermilatgnd packets a field that gives the sqrt of the trigger
        # significance. I am confused by this. So, for the time being, I
        # am logging it but treating all as GRBs.
        set significance [field2 $packet 26]
        log::info [format "%s: significance is %.2f." $type $significance]
        return true
      }
      "fermilatoffline" {
        return true
      }
      default {
        error "fermigrb: unexpected packet type \"$packet\"."
      }
    }
  }

  variable fermigbmclassdict {
    0 "error"
    1 "unreliablelocation"
    2 "localparticles"
    3 "belowhorizon"
    4 "grb"
    5 "genericsgr"
    6 "generictransient"
    7 "distantparticles"
    8 "solarflare"
    9 "cygx1"
    10 "sgr180620"
    11 "groj042232"
    19 "tgf"
  }
  
  proc fermigbmclass {packet i} {
    set i [expr {[field0 $packet $i] & 0xffff}]
    variable fermigbmclassdict
    if {[dict exists $fermigbmclassdict $i]} {
      return [dict get $fermigbmclassdict $i]
    } else {
      return "unknown"
    } 
  }
  
  proc fermigbmclassprobability {packet i} {
    return [expr {(([field0 $packet $i] >> 16) & 0xffff) / 256.0}]
  }
  
  proc fermigbmtriggersigma {packet} {
    set type [type $packet]
    switch [type $packet] {
      "fermigbmpostest" -
      "fermigbmfltpos" {
        return [field2 $packet 21]
      }
      "fermigbmgndpos" {
        return [field1 $packet 21]
      }
      default {
        error "fermigbmtriggersigma: unexpected packet type \"$packet\"."
      }
    }
  }
  
  proc fermigbmgrbduration {packet} {
    set ls [expr {([field0 $packet 18] >> 26) & 0x3}]
    switch $ls {
    0 {
      return "uncertain" 
    }
    1 { 
      return "short" 
    }
    2 {
      return "long" 
    }
    3 { 
      log::warning "invalid value in l-v-s field."
      return "uncertain"
    }
    }
  }

  ######################################################################

  # These procedures are designed to work with the following packet types:
  #
  #  hawcburstmonitor
  
  proc hawctest {packet} {
    if {([field0 $packet 18] >> 1) & 0x1} {
      return true
    } else {
      return false
    }
  }

  proc hawctrigger {packet} {
    # HAWC events are uniquely identified by the combination of the run_id and
    # event_id, which isn't very useful for us as we want a single integer.
    # Therefore, we use the timestamp to generate one.
    set timestamp [hawceventtimestamp $packet]
    return [string range [string map {"T" ""} [utcclock::combinedformat $timestamp 0 false]] 0 end-2]
  }

  proc hawcgrbname {packet} {
    set timestamp [hawceventtimestamp $packet]
    if {[string equal $timestamp ""]} {
      return ""
    }
    if {[scan $timestamp "%d-%d-%dT%d:%d:%f" year month day hours minutes seconds] != 6} {
      error "unable to scan timestamp \"$timestamp\"."
    }
    set dayfraction [expr {($hours + $minutes / 60.0 + $seconds / 3600.0) / 24.0}]
    set identifier [format "HAWC GRB %02d%02d%02d.%03d" [expr {$year % 100}] $month $day [expr {int($dayfraction * 1000)}]]
    return $identifier
  }

  proc hawceventtimestamp {packet} {
    return [utcclock::combinedformat [seconds $packet 5]]
  }
  
  proc hawcalpha {packet} {
    return [astrometry::foldradpositive [astrometry::degtorad [field4 $packet 7]]]
  }
  
  proc hawcdelta {packet} {
    return [astrometry::degtorad [field4 $packet 8]]
  }

  proc hawcequinox {packet} {
    return 2000
  }

  proc hawcuncertainty {packet} {

    set type [type $packet]

    # We work in degrees here.

    set rawuncertainty [field4 $packet 11]
    log::info [format "%s: raw uncertainty is %.1fam in radius." $type [expr {$rawuncertainty * 60}]]

    # The notice gives the 68% statistical radius. 

    # We assume a Gaussian distribution p(x,y) = A exp(-0.5*(r/sigma)^2), for
    # which P(<r) = 1 - exp(-0.5*(r/sigma)^2). We use this to convert from the
    # 68% radius in the notice to a 90% radius.

    # According to Hugo Ayala (email on 2021-04-27), there is currently no
    # estimate of the systematic error.
    
    set r68 $rawuncertainty
    set sigma [expr {$r68 / sqrt(-2 * log(1-0.68))}]
    set r90 [expr {$sigma * sqrt(-2 * log(1-0.90))}]

    log::info [format "%s: 90%% uncertainty is %.1fam in radius." $type [expr {$r90 * 60}]]

    return [format "%.1fam" [expr {$r90 * 60}]]
  }
  
  proc hawcgrb {packet} {
    if {[hawcretraction $packet]} {
      return false
    } else {
      return true
    }
  }

  proc hawcretraction {packet} {
    if {([field0 $packet 18] >> 5) & 0x1} {
      return true
    } else {
      return false
    }
  }

  ######################################################################

  # These procedures are designed to work with the following packet types:
  #
  #  icecubeastrotrackgold
  #  icecubeastrotrackbronze
  #  icecubecascade
  
  proc icecubetest {packet} {
    if {([field0 $packet 18] >> 1) & 0x1} {
      return true
    } else {
      return false
    }
  }

  proc icecubetrigger {packet} {
    # IceCube events are uniquely identified by the combination of the run_id and
    # event_id, which isn't very useful for us as we want a single integer.
    # Therefore, we use the timestamp to generate one.
    set timestamp [icecubeeventtimestamp $packet]
    return [string range [string map {"T" ""} [utcclock::combinedformat $timestamp 0 false]] 0 end-2]
  }

  proc icecubegrbname {packet} {
    set timestamp [icecubeeventtimestamp $packet]
    if {[string equal $timestamp ""]} {
      return ""
    }
    if {[scan $timestamp "%d-%d-%dT%d:%d:%f" year month day hours minutes seconds] != 6} {
      error "unable to scan timestamp \"$timestamp\"."
    }
    set dayfraction [expr {($hours + $minutes / 60.0 + $seconds / 3600.0) / 24.0}]
    set type [type $packet]
    switch $type {
      "icecubeastrotrackgold" {
        set eventtype "gold track"
      }
      "icecubeastrotrackbronze" {
        set eventtype "bronze track"
      }
      "icecubecascade" {
        set eventtype "cascade"
      }
    }
    set identifier [format "Icecube %s %02d%02d%02d.%03d" $eventtype [expr {$year % 100}] $month $day [expr {int($dayfraction * 1000)}]]
    return $identifier
  }

  proc icecubeeventtimestamp {packet} {
    return [utcclock::combinedformat [seconds $packet 5]]
  }
  
  proc icecubealpha {packet} {
    return [astrometry::foldradpositive [astrometry::degtorad [field4 $packet 7]]]
  }
  
  proc icecubedelta {packet} {
    return [astrometry::degtorad [field4 $packet 8]]
  }

  proc icecubeequinox {packet} {
    return 2000
  }

  proc icecubeuncertainty {packet} {

    set type [type $packet]

    # We work in degrees here.

    set rawuncertainty [field4 $packet 11]
    log::info [format "%s: raw uncertainty is %.1fam in radius." $type [expr {$rawuncertainty * 60}]]

    # The notice gives the 90% radius. 
    set r90 $rawuncertainty
    log::info [format "%s: 90%% uncertainty is %.1fam in radius." $type [expr {$r90 * 60}]]

    return [format "%.1fam" [expr {$r90 * 60}]]
  }
  
  proc icecubegrb {packet} {
    if {[icecuberetraction $packet]} {
      return false
    } else {
      return true
    }
  }

  proc icecuberetraction {packet} {
    if {([field0 $packet 18] >> 5) & 0x1} {
      return true
    } else {
      return false
    }
  }

  ######################################################################

  proc lvcidentifier {packet} {

    set date [field0 $packet 4]            

    set prefixcode [expr {([field0 $packet 19] >> 20) & 0xf}]
    switch [directories::prefix]code {
      1  { set prefix "G" }
      2  { set prefix "T" }
      3  { set prefix "M" }
      4  { set prefix "Y" }
      5  { set prefix "H" }
      6  { set prefix "E" }
      7  { set prefix "K" }
      8  { set prefix "S" }
      9  { set prefix "GW" }
      10 { set prefix "TS" }
      11 { set prefix "TGW" }
      12 { set prefix "MS"  }
      13 { set prefix "MGW" }
      default {
        log::warning "unknown lvc prefix code [directories::prefix]code."
        set prefix ""
      }
    }

    set suffix0 [format "%c" [expr {([field0 $packet 19] >> 10) & 0xff}]]
    set suffix1 [format "%c" [expr {([field0 $packet 21] >>  0) & 0xff}]]          

    return [string trimright "${prefix}${date}${suffix0}${suffix1}"]
  }

  proc lvctest {packet} {
    set identifier [lvcidentifier $packet]
    switch -glob $identifier {
      "S*" -
      "GW" {
        return false
      }
      "MS*"  -
      "MGW*" -
      "TS*"  -
      "TGW" {
        return true
      } 
      default {
        log::warning "obsolete lvc identifier $identifier."
        return false
      }
    }
  }

  proc lvcname {packet} {
    return "LVC [lvcidentifier $packet]"     
  }

  proc lvceventtimestamp {packet} {
    return [utcclock::combinedformat [seconds $packet 5]]
  }

  proc lvctrigger {packet} {
    # LVC events don't have a formal numerical trigger number, so we use the
    # timestamp to generate one.
    set timestamp [lvceventtimestamp $packet]
    return [string range [string map {"T" ""} [utcclock::combinedformat $timestamp 0 false]] 0 end-2]
  }
  
  proc lvcurl {packet} {
    return [string trimright [format "%s%s%s%s%s%s%s%s%s%s%s" \
      "https://gracedb.ligo.org/api/superevents/" \
      [fields $packet 29] \
      [fields $packet 30] \
      [fields $packet 31] \
      [fields $packet 32] \
      [fields $packet 33] \
      [fields $packet 34] \
      [fields $packet 35] \
      [fields $packet 36] \
      [fields $packet 37] \
      [fields $packet 38] \
   ] "\0"]
  }

######################################################################

  proc seconds {packet i} {
    # Convert the GCN/TAN time into seconds since the epoch. Leap
    # seconds are ignored. TJD 10281 is 1996 July 17 UTC. SOD is the
    # number of seconds since the start of the JD.
    set tjd [field0 $packet $i]
    set sod [field2 $packet [expr {$i + 1}]]
    expr {($tjd - 10281) * 24.0 * 60.0 * 60.0 + [utcclock::scan "19960717T000000"] + $sod}
  }
  
  variable typedict {
     1  "batseoriginal"
     2  "test"
     3  "imalive"
     4  "kill"
    11  "batsemaxbc"
    21  "bradfordtest"
    22  "batsefinal"
    24  "batselocburst"
    25  "alexis"
    26  "rxtepcaalert"
    27  "rxtepca"
    28  "rxteasmalert"
    29  "rxteasm"
    30  "comptel"
    31  "ipnraw"
    32  "ipnsegment"
    33  "saxwfcalert"
    34  "saxwfc"
    35  "saxnfialert"
    36  "saxnfi"
    37  "rxteasmxtrans"
    38  "sparetesting"
    39  "ipnposition"
    40  "hetescalert"
    41  "hetescupdate"
    42  "hetesclast"
    43  "hetegndana"
    44  "hetetest"
    45  "grbcounterpart"
    46  "swifttoofomobserve"
    47  "swifttooscslew"
    48  "dowtodtest"
    51  "integralpointdir"
    52  "integralspiacs"
    53  "integralwakeup"
    54  "integralrefined"
    55  "integraloffline"
    56  "integralweak"
    57  "aavso"
    58  "milagro"
    59  "konuslightcurve"
    60  "swiftbatgrbalert"
    61  "swiftbatgrbposition"
    62  "swiftbatgrbnackposition"
    63  "swiftbatgrblightcurve"
    64  "swiftbatscaledmap"
    65  "swiftfomobserve"
    66  "swiftscslew"
    67  "swiftxrtposition"
    68  "swiftxrtspectrum"
    69  "swiftxrtimage"
    70  "swiftxrtlightcurve"
    71  "swiftxrtnackposition"
    72  "swiftuvotimage"
    73  "swiftuvotsrclist"
    76  "swiftbatgrbproclightcurve"
    77  "swiftxrtprocspectrum"
    78  "swiftxrtprocimage"
    79  "swiftuvotprocimage"
    80  "swiftuvotprocsrclist"
    81  "swiftuvotposition"
    82  "swiftbatgrbpostest"
    83  "swiftpointdir"
    84  "swiftbattrans"
    85  "swiftxrtthreshpix"
    86  "swiftxrtthreshpixproc"
    87  "swiftxrtsper"
    88  "swiftxrtsperproc"
    89  "swiftuvotnackposition"
    97  "swiftbatquicklookposition"
    98  "swiftbatsubthresholdposition"
    99  "swiftbatslewgrbposition"
    100 "superagilegrbposwakeup"
    101 "superagilegrbposground"
    102 "superagilegrbposrefined"
    103 "swiftactualpointdir"
    105 "agilealert"
    107 "agilepointdir"
    109 "superagilegrbpostest"
    110 "fermigbmalert"
    111 "fermigbmfltpos"
    112 "fermigbmgndpos"
    114 "fermigbmgndinternal"
    115 "fermigbmfinpos"
    116 "fermigbmalertinternal"
    117 "fermigbmfltinternal"
    119 "fermigbmpostest"
    120 "fermilatgrbposini"
    121 "fermilatgrbposupd"
    122 "fermilatgrbposdiag"
    123 "fermilattrans"
    124 "fermilatgrbpostest"
    125 "fermilatmonitor"
    126 "fermiscslew"
    127 "fermilatgnd"
    128 "fermilatoffline"
    129 "fermipointdir"
    130 "simbadnedsearchresults"
    131 "fermigbmsubthreshold"
    133 "swiftbatmonitor"
    134 "maxiunknownsource"
    135 "maxiknownsource"
    136 "maxitest"
    137 "ogle"
    139 "moa"
    140 "swiftbatsubsubthreshpos"
    141 "swiftbatknownsrcpos"
    144 "fermiscslewinternal"
    145 "coincidence"
    146 "fermigbmfinposinternal"
    148 "suzakulightcurve"
    149 "snews"
    150 "lvcpreliminary"
    151 "lvcinitial"
    152 "lvcupdate"
    153 "lvctest"
    154 "lvccounterpart"
    157 "icecubecoinc"
    158 "icecubehese"
    159 "icecubetest"
    160 "caletgbmfltlc"
    161 "caletgbmgndlc"
    164 "lvcretraction"
    166 "icecubecluster"
    168 "gwhencoinc"
    169 "icecubeehe"
    170 "amonantaresfermilatcoinc"
    171 "hawcburstmonitor"
    172 "amonnuemcoinc"
    173 "icecubeastrotrackgold"
    174 "icecubeastrotrackbronze"
    175 "sksupernova"
    176 "icecubecascade"
  }
  
  proc type {packet} {
    set i [field0 $packet 0]
    variable typedict
    if {[dict exists $typedict $i]} {
      return [dict get $typedict $i]
    } else {
      return "unknown"
    }
  }
  
  proc field0 {packet i} {
    return [lindex $packet $i]
  }

  proc field1 {packet i} {
    return [expr {[field0 $packet $i] * 1e-1}]
  }

  proc field2 {packet i} {
    return [expr {[field0 $packet $i] * 1e-2}]
  }

  proc field4 {packet i} {
    return [expr {[field0 $packet $i] * 1e-4}]
  }
  
  proc fields {packet i} {
    return [format "%s%s%s%s" \
      [bytes $packet $i 0] \
      [bytes $packet $i 1] \
      [bytes $packet $i 2] \
      [bytes $packet $i 3] \
    ]
  }
  
  proc byte0 {packet i j} {
    return [expr {([field0 $packet $i] >> (8 * $j)) & 0xff}]
  }
  
  proc bytes {packet i j} {
    return [format "%c" [byte0 $packet $i $j]]
  }

  ######################################################################
  
  variable servercoroutine
  variable serving false
  
  proc servername {address} {
    if {![catch {set output [exec "host" $address]}]} {
      set servername [lindex [split [string trimright $output "."]] end]
    } else {
      set servername "unknown"
    }
    return $servername
  }

  proc server {channel address} {
    variable serving
    set serving true
    if {[catch {readloop $channel} message]} {
      log::error "while serving connection from [servername $address] ($address): $message"
    }
    log::summary "closing connection from [servername $address] ($address)."
    catch {close $channel}
    set serving false
    log::summary "waiting for connection."
  }

  proc accept {channel address port} {
    log::summary "accepting connection from [servername $address] ($address)."
    variable serving
    if {$serving} {
      log::warning "closing connection from [servername $address] ($address): already serving another connection."
      catch {close $channel}
    } else {
      log::summary "serving connection from [servername $address] ($address)."
      after idle coroutine gcntan::servercoroutine "gcntan::server $channel $address"
    }
  }
  
  ######################################################################

  proc stop {} {
    server::checkstatus
    server::checkactivityforstop
    server::setactivity [server::getrequestedactivity]
  }

  proc reset {} {
    server::checkstatus
    server::checkactivityforreset
    server::setactivity [server::getrequestedactivity]
  }
  
  ######################################################################

  set server::datalifeseconds 300

  proc start {} {
    variable packetport
    log::summary "waiting for connection."
    socket -server gcntan::accept $packetport
    server::setrequestedactivity "idle"
    server::setstatus "starting"
    
  }

  ######################################################################

  # Test the code by putting the decimal representation of a packet (40
  # integers) as a list in the second argument below and uncommenting the
  # call. This packet will be processed when the server starts.

  # processpacket [utcclock::combinedformat] {}

  ######################################################################

}
