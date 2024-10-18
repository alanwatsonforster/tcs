########################################################################

# This file is part of the UNAM telescope control system.

########################################################################

# Copyright © 2019 Alan M. Watson <alan@astro.unam.mx>
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
package require "controller"
package require "log"
package require "server"

package provide "plccolibri" 0.0

namespace eval "plc" {

  ######################################################################

  variable controllerhost [config::getvalue "plc" "controllerhost"]
  variable controllerport [config::getvalue "plc" "controllerport"]  
  
  ######################################################################

  set controller::host                        $controllerhost
  set controller::port                        $controllerport
  set controller::statuscommand               "StatusA\nStatusB\nStatusC\n"
  set controller::timeoutmilliseconds         5000
  set controller::intervalmilliseconds        500
  set controller::updatedata                  plc::updatedata
  set controller::statusintervalmilliseconds  1000

  set server::datalifeseconds                 30

  ######################################################################
  
  variable boltwoodenabled [config::getvalue "plc" "boltwoodenabled"]
  variable vaisalaenabled  [config::getvalue "plc" "vaisalaenabled"]
  
  ######################################################################

  server::setdata "timestamp"         ""

  variable settledelayseconds 5

  proc isignoredresponseresponse {response} {
    if {
      [regexp {[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9]:[0-9][0-9]:[0-9][0-9] - OK} $response] == 1 ||
      [string equal "" $response]
    } {
      return true
    } else {
      return false
    }
  }
  
  variable responsea ""
  variable responseb ""
  variable responsec ""

  variable lastresponsea ""
  variable lastresponseb ""
  variable lastresponsec ""

  proc updatedata {response} {

    variable responsea
    variable responseb
    variable responsec

    variable lastresponsea
    variable lastresponseb
    variable lastresponsec

    variable boltwoodenabled
    variable vaisalaenabled

    set timestamp [utcclock::combinedformat now]

    set response [string trim $response]
    if {[isignoredresponseresponse $response]} {
      return false
    }

    if {[string length $response] == 0} {
      log::warning "unexpected response \"$response\"."
      return false
    }
    
    if {[string match "* Cloud Sensor has been restarted *" $response]} {
      log::info "finished rebooting boltwood."
      return false
    }
    
    if {[string match "* Weather Station has been restarted *" $response]} {
      log::info "finished rebooting vaisala."
      return false
    }
    
    if {[string match "* Clarity II Software has been restarted *" $response]} {
      log::info "finished restarting boltwood software."
      return false
    }
    
    set letter [string index $response 0]    
    if {[string equal $letter "a"]} {
      set responsea $response
      return false
    } elseif {[string equal $letter "b"]} {
      set responseb $response
      return false
    } elseif {[string equal $letter "c"]} {
      set responsec $response
    } else {
      log::warning "unexpected response \"$response\"."
      return false
    }
    
    if {
      [string equal $responsea ""] ||
      [string equal $responseb ""] ||
      [string equal $responsec ""]
    } {
      log::warning "missing at least one response."
      return false
    }
    
    server::setdata "responsea" $responsea
    server::setdata "responseb" $responseb
    server::setdata "responsec" $responsec
    
    # Process responsea.
    
    set field [string map {" " ""} $responsea]
    set field [split $field ";"]
    
    if {!$vaisalaenabled} {
      server::setdata "vaisalawindminazimuth"        ""
      server::setdata "vaisalawindaverageazimuth"    ""
      server::setdata "vaisalawindmaxzimuth"         ""
      server::setdata "vaisalawindminspeed"          ""
      server::setdata "vaisalawindaveragespeed"      ""
      server::setdata "vaisalawindmaxspeed"          ""
      server::setdata "vaisalatemperature"           ""
      server::setdata "vaisalahumidity"              ""
      server::setdata "vaisalapressure"              ""
      server::setdata "vaisalarainaccumulation"      ""
      server::setdata "vaisalarainseconds"           ""
      server::setdata "vaisalarainrate"              ""
      server::setdata "vaisalaheatingtemperature"    ""
      server::setdata "vaisalaheatingcoltage"        ""
      server::setdata "vaisalahsupplyvoltage"        ""
      server::setdata "vaisalareferencevoltage"      ""
    } elseif {[catch {
      server::setdata "vaisalawindminazimuth"        [format "%d"   [parseinteger [lindex $field 2]]]
      server::setdata "vaisalawindaverageazimuth"    [format "%d"   [parseinteger [lindex $field 3]]]
      server::setdata "vaisalawindmaxzimuth"         [format "%d"   [parseinteger [lindex $field 4]]]
      server::setdata "vaisalawindminspeed"          [format "%.1f" [lindex $field 5]]
      server::setdata "vaisalawindaveragespeed"      [format "%.1f" [lindex $field 6]]
      server::setdata "vaisalawindmaxspeed"          [format "%.1f" [lindex $field 7]]
      server::setdata "vaisalatemperature"           [format "%.1f" [lindex $field 8]]
      server::setdata "vaisalahumidity"              [format "%.3f" [expr {0.01 * [lindex $field 9]}]]
      server::setdata "vaisalapressure"              [format "%.1f" [lindex $field 10]]
      server::setdata "vaisalarainaccumulation"      [format "%.1f" [lindex $field 11]]
      server::setdata "vaisalarainseconds"           [format "%d"   [parseinteger [lindex $field 12]]]
      server::setdata "vaisalarainrate"              [format "%.1f" [lindex $field 13]]
      server::setdata "vaisalaheatingtemperature"    [format "%.1f" [lindex $field 14]]
      server::setdata "vaisalaheatingcoltage"        [format "%.1f" [lindex $field 15]]
      server::setdata "vaisalahsupplyvoltage"        [format "%.1f" [lindex $field 16]]
      server::setdata "vaisalareferencevoltage"      [format "%.1f" [lindex $field 17]]
    }]} {
      log::warning "unable to read vaisala data."
    }
    
    if {!$boltwoodenabled} {
      server::setdata "boltwoodskytemperature"        ""
      server::setdata "boltwoodairtemperature"        ""
      server::setdata "boltwoodwindspeed"             ""
      server::setdata "boltwoodhumidity"              ""
      server::setdata "boltwooddewpoint"              ""
      server::setdata "boltwoodheatersetting"         ""
      server::setdata "boltwoodrainindex"             ""
      server::setdata "boltwoodwetnessindex"          ""
      server::setdata "boltwoodcloudindex"            ""
      server::setdata "boltwoodwindindex"             ""
      server::setdata "boltwooddaylightindex"         ""
      server::setdata "boltwoodroofindex"             ""
    } elseif {[catch {
      server::setdata "boltwoodskytemperature"        [format "%.1f" [lindex $field 18]]
      server::setdata "boltwoodairtemperature"        [format "%.1f" [lindex $field 19]]
      server::setdata "boltwoodwindspeed"             [format "%.1f" [lindex $field 20]]
      server::setdata "boltwoodhumidity"              [format "%.3f" [expr {0.01 * [lindex $field 21]}]]
      server::setdata "boltwooddewpoint"              [format "%.1f" [lindex $field 22]]
      server::setdata "boltwoodheatersetting"         [format "%.1f" [lindex $field 23]]
      server::setdata "boltwoodrainindex"             [format "%d"   [parseinteger [lindex $field 24]]]
      server::setdata "boltwoodwetnessindex"          [format "%d"   [parseinteger [lindex $field 25]]]
      server::setdata "boltwoodcloudindex"            [format "%d"   [parseinteger [lindex $field 26]]]
      server::setdata "boltwoodwindindex"             [format "%d"   [parseinteger [lindex $field 27]]]
      server::setdata "boltwooddaylightindex"         [format "%d"   [parseinteger [lindex $field 28]]]
      server::setdata "boltwoodroofindex"             [format "%d"   [parseinteger [lindex $field 29]]]
    }]} {
      log::warning "unable to read boltwood data."
    }
    
    if {[catch {
      server::setdata "comet1temperature"             [format "%.1f" [lindex $field 30]]
      server::setdata "comet1humidity"                [format "%.3f" [expr {0.01 * [lindex $field 31]}]]
      server::setdata "comet2temperature"             [format "%.1f" [lindex $field 32]]
      server::setdata "comet2humidity"                [format "%.3f" [expr {0.01 * [lindex $field 33]}]]
      server::setdata "comet3temperature"             [format "%.1f" [lindex $field 34]]
      server::setdata "comet3humidity"                [format "%.3f" [expr {0.01 * [lindex $field 35]}]]
    }]} {
      log::warning "unable to read comet data."
    }
    
    if {[catch {
      server::setdata "europeanupsbatterycapacity"    [format "%.2f" [expr {0.01 * [lindex $field 36]}]]
      server::setdata "europeanupsbatterytemperature" [format "%.1f" [lindex $field 37]]
      server::setdata "europeanupsbatteryvoltage"     [format "%.0f" [lindex $field 38]]
      server::setdata "europeanupsbatterycurrent"     [format "%.0f" [lindex $field 39]]
      server::setdata "europeanupsbatteryseconds"     [format "%.0f" [expr {60 * [lindex $field 40]}]]
      server::setdata "europeanupsload"               [format "%.2f" [expr {0.01 * [lindex $field 41]}]]
      server::setdata "europeanupsl12voltage"         [format "%.0f" [lindex $field 42]]
      server::setdata "europeanupsl23voltage"         [format "%.0f" [lindex $field 43]]
      server::setdata "europeanupsl13voltage"         [format "%.0f" [lindex $field 44]]
      server::setdata "europeanupsl12current"         [format "%.0f" [lindex $field 45]]
      server::setdata "europeanupsl23current"         [format "%.0f" [lindex $field 46]]
      server::setdata "europeanupsl13current"         [format "%.0f" [lindex $field 47]]
      server::setdata "europeanupsinputfrequency"     [format "%.0f" [lindex $field 48]]
      server::setdata "europeanupsoutputfrequency"    [format "%.0f" [lindex $field 49]]
    }]} {
      log::warning "unable to read european ups data."
    }
    
    # Master is PLC and telescope normally left in remote.
    set rawmode [lindex $field 50]
    switch $rawmode {
    
      
      "MANU"           { set mode "local" }
      "OFF"            { set mode "off"   }
      "WAIT_ACK"       { set mode "remote and waiting for local confirmation to operate"}
      "AUTO"           { set mode "remote and may operate" }
      "AUTO_PARK"      { set mode "remote but must not operate" }
      "AUTO_INTRUSION" { set mode "remote but intrusion detected"}
      "ESTOP"          { set mode "emergency stop activated"}
      "WAIT_MANU"      { set mode "local but waiting for telescope to be switched to remote" }
      "WAIT_OFF"       { set mode "off but waiting for telescope to be switched to remote" }
      "WAIT_AUTO"      { set mode "remote but waiting for telescope to be switched to remote" }

       default          { 
        log::warning "unable to read mode data."
        set mode ""
      }
    }
    server::setdata "mode"                          $mode

    if {[catch {
      server::setdata "unsafeseconds"                 [format "%d" [parseinteger [lindex $field 51]]]
    }]} {
      log::warning "unable to read unsafe seconds data."
    }

    # Process responseb.

    switch -- "[string index $responseb 22][string index $responseb 23]" {
      "00" { set keyswitch "off"    }
      "01" { set keyswitch "remote" }
      "10" { set keyswitch "local"  }
      "11" { set keyswitch "error"  }
      "default" {
        log::warning "unable to read key switch data."
        set keyswitch ""
      }
    }
    server::setdata "keyswitch"                     $keyswitch

    if {[catch {
      server::setdata "europeanupsbatteryexhausted"   [boolean [string index $responseb 24]]
      server::setdata "europeanupsbatterylow"         [boolean [string index $responseb 25]]
      server::setdata "europeanupsusingbattery"       [boolean [string index $responseb 26]]
      server::setdata "europeanupsfault"              [boolean [string index $responseb 27]]
      server::setdata "europeanupsusinginverter"      [boolean [string index $responseb 28]]
      server::setdata "europeanupsloadprotected"      [boolean [string index $responseb 29]]
      server::setdata "europeanupscommunicationalarm" [boolean [string index $responseb 30]]
    }]} {
      log::warning "unable to read european ups data."
    }

    if {[catch {
      server::setdata "needtopark"                    [boolean [string index $responseb 31]]
      server::setdata "rainalarm"                     [boolean [string index $responseb 32]]
      server::setdata "windalarm"                     [boolean [string index $responseb 33]]
      server::setdata "cloudalarm"                    [boolean [string index $responseb 34]]
      server::setdata "daylightalarm"                 [boolean [string index $responseb 35]]
      server::setdata "humidityalarm"                 [boolean [string index $responseb 36]]
      server::setdata "tcsalarm"                      [boolean [string index $responseb 37]]
      server::setdata "upsalarm"                      [boolean [string index $responseb 38]]
    }]} {
      log::warning "unable to read alarm data."
    }
    
    switch -- "[string index $responseb 39]" {
      "0" { set localconfirmation "pending"   }
      "1" { set localconfirmation "confirmed" }
      "default" {
        log::warning "unable to read local confirmation data."
        set localconfirmation ""
      }
    }
    server::setdata "localconfirmation"               $localconfirmation

    if {[catch {
      server::setdata "emergencystopalarm"            [boolean [string index $responseb 40]]
      server::setdata "emergencystoplogiclevel"       [boolean [string index $responseb 41]]
      server::setdata "motorpoweron"                  [boolean [string index $responseb 42]]
    }]} {
      log::warning "unable to read emergency stop data."
    }

    if {[catch {
      server::setdata "intrusionalarm"                [boolean [string index $responseb 43]]
    }]} {
      log::warning "unable to read intrusion alarm data."
    }
    
    # Positions 44 and 45 are reserved.

    if {[catch {
      server::setdata "bypasskeyswitch"                [boolean [string index $responseb 46]]
      server::setdata "bypassweatheralarms"            [boolean [string index $responseb 47]]
    }]} {
      log::warning "unable to read bypass data."
    }

    if {[catch {
      server::setdata "riocommunicationalarm"          [boolean [string index $responseb 48]]
      server::setdata "riovaisalapowersupply"          [boolean [string index $responseb 49]]
      server::setdata "rioboltwoodpowersupply"         [boolean [string index $responseb 50]]
      server::setdata "rioboltwoodcommunicationalarm"  [boolean [string index $responseb 51]]
      server::setdata "riovaisalacommunicationalarm"   [boolean [string index $responseb 52]]
      server::setdata "rioicronpowersupplyalarm"       [boolean [string index $responseb 53]]
      server::setdata "riomainbreakerclosed"           [boolean [string index $responseb 54]]
      server::setdata "rioswitchbreakerclosed"         [boolean [string index $responseb 55]]
      server::setdata "riopowerbreakerclosed"          [boolean [string index $responseb 56]]
      server::setdata "riousingbattery"                [boolean [string index $responseb 57]]
      server::setdata "riobatteryalarm"                [boolean [string index $responseb 58]]
      server::setdata "riobatterycharged"              [boolean [string index $responseb 59]]
    }]} {
      log::warning "unable to read rio data."
    }
    
    if {[catch {
      foreach i { 1 2 3 4 5 6 7 8 9 10 11 12 } {
        switch [string index $responseb [expr {59 + $i}]] {
          "0" { set louver "closed" }
          "1" { set louver "open"   }
          "2" { set louver "error"  }
          default {
            log::warning "unable to read louver data."
            set louver ""
          }
        }
        server::setdata "louver$i"                      $louver
      }
    }]} {
      log::warning "unable to read louver data."
    }
    
    if {[catch {
      switch [string index $responseb 60] {
        "0" { set lights "off"  }
        "1" { set lights "on"  }
        default {
          log::warning "unable to read lights data."
          set lights ""
        }
      }
      server::setdata "lights"                         $lights
    }]} {
      log::warning "unable to read lights data."
    }
        
    switch -- "[string index $responseb 77][string index $responseb 78]" {
      "00" { set telescopemode "off"    }
      "01" { set telescopemode "remote"  }
      "10" { set telescopemode "local" }
      "11" { set telescopemode "error"  }
      "default" {
        log::warning "unable to read telescope mode data."
        set telescopemode ""
      }
    }
    server::setdata "telescopemode"                    $telescopemode

    switch -- "[string index $responseb 79]" {
      "0" { set domemode "local" }
      "1" { set domemode "remote"  }
      "default" {
        log::warning "unable to read dome mode data."
        set domemode ""
      }
    }
    server::setdata "domemode"                         $domemode
    
    switch -- "[string index $responseb 80][string index $responseb 81]" {
      "00" { set shutters "error"         }
      "01" { set shutters "open"          }
      "10" { set shutters "closed"        }
      "11" { set shutters "intermediate"  }
      "default" {
        log::warning "unable to read shutters data."
        set shutters ""
      }
    }
    server::setdata "shutters"                         $shutters

    if {[catch {
      switch -- "[string index $responseb 82][string index $responseb 83]" {
        "00" { set telescopemode "off"    }
        "01" { set telescopemode "remote"  }
        "10" { set telescopemode "local" }
        "default" {
          log::warning "unable to read plc data."
          set telescopemode ""
        }
      }
      server::setdata "requestedtelescopemode"         $telescopemode
      server::setdata "requestedpark"                  [boolean [expr {![string index $responseb 84]}]]
      server::setdata "requestedcloseshutters"         [boolean [expr {![string index $responseb 85]}]]
      switch -- "[string index $responseb 86]" {
        "0" { set domemode "remote" }
        "1" { set domemode "local"  }
        "default" {
          log::warning "unable to read plc data."
          set domemode ""
        }
      }
      server::setdata "requesteddomemode"              $domemode
    }]} { 
      log::warning "unable to read plc data."
    }

    if {[catch {
      server::setdata "bypassdaylightalarm"            [boolean [string index $responseb 87]]
      server::setdata "bypasswindalarm"                [boolean [string index $responseb 89]]
      server::setdata "bypasshumidityalarm"            [boolean [string index $responseb 90]]
      server::setdata "bypasscloudalarm"               [boolean [string index $responseb 91]]
      server::setdata "bypassrainalarm"                [boolean [string index $responseb 92]]
      server::setdata "bypassupsalarm"                 [boolean [string index $responseb 93]]
      server::setdata "bypasstcsalarm"                 [boolean [string index $responseb 94]]
    }]} {
      log::warning "unable to read bypass data."
    }
    
    switch -- "[string index $responseb 95]" {
      "0" { set status "unknown" }
      "2" { set status "ok"  }
      "4" { set status "warning alarm"  }
      "8" { set status "critical alarm"  }
      "default" {
        log::warning "unable to read european ups data."
          set status ""
      }
    }
    server::setdata "europeanupsstatus"                $status

    switch -- "[string index $responseb 96]" {
      "0" { set fans "off" }
      "1" { set fans "on"  }
      "default" {
         log::warning "unable to read fans data."
         set fans ""
      }
    }
    server::setdata "fans"                             $fans

    switch -- "[string index $responseb 97]" {
      "0" { set telescopecabinetpower "off" }
      "1" { set telescopecabinetpower "on"  }
      "default" {
         log::warning "unable to read telescope cabinet data."
         set fans ""
      }
    }
    server::setdata "telescopecabinetpower"            $telescopecabinetpower
    
    switch -- "[string index $responseb 100]" {
      "0" { set accessrequested false }
      "1" { set accessrequested true  }
    }
    server::setdata "accessrequested"                  $accessrequested

    # Process responsec.

    set field [string map {" " ""} $responsec]
    set field [split $field ";"]
    
    if {[catch {
      server::setdata "americanupsl1current"          [format "%.1f" [lindex $field 2]]
      server::setdata "americanupsl2current"          [format "%.1f" [lindex $field 3]]
      server::setdata "americanupsl3current"          [format "%.1f" [lindex $field 4]]
      server::setdata "americanupsl1voltage"          [format "%.1f" [lindex $field 5]]
      server::setdata "americanupsl2voltage"          [format "%.1f" [lindex $field 6]]
      server::setdata "americanupsl3voltage"          [format "%.1f" [lindex $field 7]]
      server::setdata "americanupsload"               [format "%.2f" [expr {0.01 * [lindex $field 8]}]]
      server::setdata "americanupsoutputfrequency"    [format "%.1f" [lindex $field 9]]
      server::setdata "americanupsbatterytemperature" [format "%.1f" [lindex $field 10]]
      server::setdata "americanupsbatterycharge"      [format "%.2f" [expr {0.01 * [lindex $field 11]}]]
      server::setdata "americanupsbatteryvoltage"     [format "%.1f" [lindex $field 12]]
      server::setdata "americanupsbatterycurrent"     [format "%.1f" [lindex $field 13]]
      set statusword [lindex $field 14]
      server::setdata "americanupsusingbattery"       [boolean [expr {$statusword & 1}]]
      set status ""
      if {$statusword & (1 <<  2)} { set status "$status/on bypass"          }
      if {$statusword & (1 <<  9)} { set status "$status/inoperable battery" }
      if {$statusword & (1 << 13)} { set status "$status/information alarm"  }
      if {$statusword & (1 << 14)} { set status "$status/warning alarm"      }
      if {$statusword & (1 << 15)} { set status "$status/critical alarm"     }
      set status [string range $status 1 end]
      server::setdata "americanupsstatus"             $status
      server::setdata "americanupscommunicationalarm" [boolean [lindex $field 15]]
    }]} {
      log::warning "unable to read american ups data."
    }

    if {[catch {
      server::setdata "plccabinettemperature"            [format "%.1f" [lindex $field 16]]
      server::setdata "weathercabinettemperature" [format "%.1f" [lindex $field 17]]
      server::setdata "seeingcabinettemperature"         [format "%.1f" [lindex $field 18]]
    }]} {
      log::warning "unable to read cabinet temperature data."
    }

    server::setdata "rainalarmdisabled"                     [boolean [expr {[server::getdata "bypassrainalarm"]     || [server::getdata "bypassweatheralarms"]}]]
    server::setdata "windalarmdisabled"                     [boolean [expr {[server::getdata "bypasswindalarm"]     || [server::getdata "bypassweatheralarms"]}]]
    server::setdata "humidityalarmdisabled"                 [boolean [expr {[server::getdata "bypasshumidityalarm"] || [server::getdata "bypassweatheralarms"]}]]
    server::setdata "cloudalarmdisabled"                    [boolean [expr {[server::getdata "bypasscloudalarm"]    || [server::getdata "bypassweatheralarms"]}]]
    server::setdata "daylightalarmdisabled"                 [boolean [expr {[server::getdata "bypassdaylightalarm"] || [server::getdata "bypassweatheralarms"]}]]
    
    server::setdata "tcsalarmdisabled"                      [server::getdata "bypasstcsalarm"]
    server::setdata "upsalarmdisabled"                      [server::getdata "bypassupsalarm"]

    server::setdata "emergencystopalarmdisabled"            false
    server::setdata "intrusionalarmdisabled"                false

    server::setdata "riocommunicationalarmdisabled"         [server::getdata "bypassweatheralarms"]
    server::setdata "riovaisalacommunicationalarmdisabled"  [server::getdata "bypassweatheralarms"]
    server::setdata "rioboltwoodcommunicationalarmdisabled" [server::getdata "bypassweatheralarms"]
    
    set mustnotoperate [boolean [expr {![string equal $mode "remote and may operate"]}]]
    server::setdata "mustnotoperate"                        $mustnotoperate
    
    foreach {level name prettyname} {

      "info"    "fans"                          "fans"             

      "info"    "shutters"                      "shutters"

      "summary" "telescopecabinetpower"         "telescope cabinet power"
      
      "info"    "bypasskeyswitch"               "key switch bypass"
      "info"    "bypassweatheralarms"           "weather alarms bypass"
      "info"    "bypasswindalarm"               "wind alarm bypass"
      "info"    "bypasshumidityalarm"           "dewpoint alarm bypass"
      "info"    "bypasscloudalarm"              "cloud alarm bypass"
      "info"    "bypassrainalarm"               "rain alarm bypass"
      "info"    "bypassdaylightalarm"           "daylight alarm bypass"
      "info"    "bypassupsalarm"                "ups alarm bypass"
      "info"    "bypasstcsalarm"                "tcs alarm bypass"
      
      "info"    "rainalarmdisabled"             "rain alarm disabled"
      "info"    "windalarmdisabled"             "wind alarm disabled"
      "info"    "humidityalarmdisabled"         "humidity alarm disabled"
      "info"    "cloudalarmdisabled"            "cloud alarm disabled"
      "info"    "daylightalarmdisabled"         "daylight alarm disabled"
      "info"    "tcsalarmdisabled"              "tcs alarm disabled"
      "info"    "upsalarmdisabled"              "ups alarm disabled"
      
      "info"    "motorpoweron"                  "motor power on"

      "info"    "europeanupsstatus"             "european ups status"
      "info"    "europeanupsusingbattery"       "european ups using battery"
      "info"    "europeanupscommunicationalarm" "european ups communication alarm"
      "info"    "americanupsstatus"             "american ups status"
      "info"    "americanupsusingbattery"       "american ups using battery"
      "info"    "americanupscommunicationalarm" "american ups communication alarm"

      "info"    "riousingbattery"               "rio using battery"

      "info"    "riobatteryalarm"               "rio battery alarm"
      "info"    "rainalarm"                     "rain alarm"
      "info"    "windalarm"                     "wind alarm"
      "info"    "cloudalarm"                    "cloud alarm"
      "info"    "daylightalarm"                 "daylight alarm"
      "info"    "humidityalarm"                 "dewpoint alarm"
      "info"    "tcsalarm"                      "tcs alarm"
      "info"    "upsalarm"                      "ups alarm"
      "info"    "intrusionalarm"                "intrusion alarm"
      "info"    "riocommunicationalarm"         "rio communication alarm"
      "info"    "riovaisalacommunicationalarm"  "rio vaisala communication alarm"
      "info"    "rioboltwoodcommunicationalarm" "rio boltwoodcommunication alarm"
      "info"    "emergencystopalarm"            "emergency stop alarm"

      "info"    "needtopark"                    "needtopark"

      "summary" "keyswitch"                     "key switch"
      "summary" "mode"                          "mode"

      "info"    "requestedtelescopemode"        "requested telescope mode"
      "info"    "telescopemode"                 "telescope mode"
      "info"    "requesteddomemode"             "requested dome mode"
      "info"    "domemode"                      "dome mode"

      "summary" "requestedpark"                 "requested park"
      "summary" "requestedcloseshutters"        "requested close shutters"
      
      "summary" "mustnotoperate"                "mustnotoperate"
      
      "summary" "accessrequested"               "accessrequested"

    } {
      logchange $level $name $prettyname
    }
    
    server::setdata "timestamp"           $timestamp
    server::setstatus "ok"

    foreach {sensorname dataname} {
      plc-cabinet-temperature             plccabinettemperature 
      weather-cabinet-temperature weathercabinettemperature 
      seeing-cabinet-temperature          seeingcabinettemperature 
      comet1-temperature                  comet1temperature
      comet2-temperature                  comet2temperature
      comet1-humidity                     comet1humidity
      comet2-humidity                     comet2humidity
    } {
      log::writesensorsfile "plc-$sensorname" [server::getdata $dataname] [server::getdata "timestamp"]
    }

    set lastresponsea $responsea
    set lastresponseb $responseb
    set lastresponsec $responsec
    set responsea ""
    set responseb ""
    set responsec ""
        
    return true
  }

  proc logalarm {value lastvalue name} {
    if {[string equal $lastvalue ""]} {
      if {$value} {
        log::info "the $name is on."
      } else {
        log::info "the $name is off."
      }
    } elseif {![string equal $lastvalue $value]} {
      if {$value} {
        log::warning "the $name has changed from off to on."
      } else {
        log::summary "the $name has changed from on to off."
      }
    }
  }

  proc boolean {x} {
    if {$x} {
      return "true"
    } else {
      return "false"
    }
  }
  
  ######################################################################
  
  variable lastvalue {}
  
  proc logchange {level name prettyname} {
    variable lastvalue
    set value [server::getdata $name]
    if {![dict exists $lastvalue $name]} {
      log::$level [format "%s is %s." $prettyname $value]
    } elseif {![string equal [dict get $lastvalue $name] $value]} {
      log::$level [format "%s has changed from %s to %s." $prettyname [dict get $lastvalue $name] $value]
    }
    dict set lastvalue $name $value
  }
  
  ######################################################################

  proc parseinteger {old} {
    if {[scan $old "%d" new] != 1} {
      return ""
    } else {
      return $new
    }
  }
  ######################################################################

  proc startactivitycommand {} {
    set start [utcclock::seconds]
    log::info "starting."
    variable boltwoodenabled
    variable vaisalaenabled
    if {!$boltwoodenabled} {
      log::warning "the boltwood is not enabled."
    }
    if {!$vaisalaenabled} {
      log::warning "the vaisala is not enabled."
    }
    controller::sendcommand "UnsafeTimer\{1\}\n"
    set end [utcclock::seconds]
    log::info [format "finished starting after %.1f seconds." [utcclock::diff $end $start]]
  }

  proc initializeactivitycommand {} {
    set start [utcclock::seconds]
    log::info "initializing."
    log::info [format "finished initializing after %.1f seconds." [utcclock::diff now $start]]
  }

  proc openactivitycommand {} {
    set start [utcclock::seconds]
    log::info "opening."
    log::info [format "finished opening after %.1f seconds." [utcclock::diff now $start]]
  }

  proc closeactivitycommand {} {
    set start [utcclock::seconds]
    log::info "closing."
    log::info [format "finished closing after %.1f seconds." [utcclock::diff now $start]]
  }

  proc resetactivitycommand {} {
    set start [utcclock::seconds]
    log::info "resetting."
    controller::flushcommandqueue
    log::info [format "finished resetting after %.1f seconds." [utcclock::diff now $start]]
  }

  proc stopactivitycommand {} {
    set start [utcclock::seconds]
    log::info "stopping."
    set activity [server::getactivity]
    if {
      [string equal $activity "initializing"] || 
      [string equal $activity "opening"] || 
      [string equal $activity "closing"]
    } {
      controller::flushcommandqueue
    }
    log::info [format "finished stopping after %.1f seconds." [utcclock::diff now $start]]
  }

  ######################################################################
  
  proc checkremote {} {
    if {![string equal [server::getdata "keyswitch"] "remote"]} {
      error "the PLC is not in remote keyswitch."
    }
  }

  proc checkrainsensor {} {
  }
  
  proc checkformove {} {
  }

  proc initialize {} {
    server::checkstatus
    server::checkactivityforinitialize
    checkremote
    server::newactivitycommand "initializing" "idle" plc::initializeactivitycommand
  }

  proc stop {} {
    server::checkstatus
    server::checkactivityforstop
    checkremote
    server::newactivitycommand "stopping" [server::getstoppedactivity] plc::stopactivitycommand
  }

  proc reset {} {
    server::checkstatus
    server::checkactivityforreset
    checkremote
    server::newactivitycommand "resetting" [server::getstoppedactivity] plc::resetactivitycommand
  }

  proc open {} {
    server::checkstatus
    server::checkactivityformove
    checkremote
    checkrainsensor
    checkformove
    server::newactivitycommand "opening" "idle" "plc::openactivitycommand"
  }

  proc close {} {
    server::checkstatus
    server::checkactivityformove
    checkremote
    checkformove
    server::newactivitycommand "closing" "idle" plc::closeactivitycommand
  }
  
  proc updateweather {} {
    server::checkstatus
    variable lastresponsea
    if {[string equal "" $lastresponsea]} {
      log::warning "unable to update weather: no data."
      return
    }
    set timestamp   [server::getdata "timestamp"]
    set date        [utcclock::formatdate $timestamp]
    set time        [utcclock::formattime $timestamp]
    set compactdate [utcclock::formatdate $timestamp false]
    set line "b.1 $date $time $lastresponsea"
    set line [string map {";" " "} $line]
    set directorypath [file join [directories::var] "weather"]
    if {[catch {
      file mkdir $directorypath
      set filepath [file join $directorypath "$date.txt"]
      set channel [::open $filepath "a"]
      puts $channel $line
      ::close $channel      
    }]} {
      log::warning "unable to update weather: cannot write to file."
    }
    return
  }
  
  ######################################################################

  proc enablealarmactivitycommand {alarm} {
    set start [utcclock::seconds]
    log::info "enabling the $alarm alarm."
    switch $alarm { 
      "weather"  { set command "ByPassWeather\{OFF\}\n" }
      "rain"     { set command "RainAlarm\{ON\}\n" }
      "wind"     { set command "WindThreshold\{ON\}\n" }
      "cloud"    { set command "CloudThreshold\{ON\}\n" }
      "humidity" { set command "HumidityThreshold\{ON\}\n" }
      "daylight" { set command "DayLightThreshold\{ON\}\n" }
      "ups"      { set command "UpsThreshold\{ON\}\n" }
      "tcs"      { set command "ComThreshold\{ON\}\n" }
      default {
        error "unknown alarm \"$alarm\"."
      }
    }
    controller::sendcommand $command
    log::info [format "finished enabling the $alarm alarm after %.1f seconds." [utcclock::diff now $start]]
  }

  proc disablealarmactivitycommand {alarm} {
    set start [utcclock::seconds]
    log::info "disabling the $alarm alarm."
    switch $alarm { 
      "weather"  { set command "ByPassWeather\{ON\}\n" }
      "rain"     { set command "RainAlarm\{OFF\}\n" }
      "wind"     { set command "WindThreshold\{OFF\}\n" }
      "cloud"    { set command "CloudThreshold\{OFF\}\n" }
      "humidity" { set command "HumidityThreshold\{OFF\}\n" }
      "daylight" { set command "DayLightThreshold\{OFF\}\n" }
      "ups"      { set command "UpsThreshold\{OFF\}\n" }
      "tcs"      { set command "ComThreshold\{OFF\}\n" }
      default {
        error "unknown alarm \"$alarm\"."
      }
    }
    controller::sendcommand $command
    log::info [format "finished disabling the $alarm alarm after %.1f seconds." [utcclock::diff now $start]]
  }

  proc grantaccessactivitycommand {} {
    set start [utcclock::seconds]
    log::info "granting access."
    controller::sendcommand "Telescope\{STOP\}\n"
    log::info [format "finished granting access after %.1f seconds." [utcclock::diff now $start]]
  }

  proc rebootactivitycommand {} {
    set start [utcclock::seconds]
    log::info "rebooting."
    variable boltwoodenabled
    if {$boltwoodenabled} {
      log::info "rebooting boltwood."
      controller::sendcommand "CloudSensorRestart{RESTART}\n"
      log::info "restarting boltwood software."
      controller::sendcommand "CX5140{BoltwoodRestart}\n"
    }
    variable vaisalaenabled
    if {$vaisalaenabled} {
      log::info "rebooting vaisala."
      controller::sendcommand "WeatherStationRestart{RESTART}\n"
    }    
    log::info [format "finished rebooting after %.1f seconds." [utcclock::diff now $start]]
  }

  ######################################################################
  
  proc checkalarm {alarm} {
    switch $alarm {
      "weather"  { return }
      "rain"     { return }
      "wind"     { return }
      "cloud"    { return }
      "humidity" { return }
      "daylight" { return }
      "ups"      { return }
      "tcs"      { return }
      default { 
        error "unknown alarm \"$alarm\"."      
      }
    }
  }
  
  proc enablealarm {alarm} {
    set start [utcclock::seconds]
    server::checkstatus
    checkalarm $alarm
    server::newactivitycommand "enabling" "idle" "plc::enablealarmactivitycommand $alarm"
  }

  proc disablealarm {alarm} {
    set start [utcclock::seconds]
    server::checkstatus
    checkalarm $alarm
    server::newactivitycommand "disabling" "idle" "plc::disablealarmactivitycommand $alarm"
  }

  proc grantaccess {} {
    set start [utcclock::seconds]
    server::checkstatus
    server::newactivitycommand "granting" "idle" "plc::grantaccessactivitycommand"
  }

  ######################################################################

  proc reboot {} {
    set start [utcclock::seconds]
    server::checkstatus
    server::newactivitycommand "rebooting" "idle" "plc::rebootactivitycommand"
  }

  ######################################################################

  proc switchonlights {} {
    server::checkstatus
    log::info "switching on lights."
    controller::pushcommand "ObsRoomLight{ON}\n"
    return
  }

  proc switchofflights {} {
    server::checkstatus
    log::info "switching off lights."
    controller::pushcommand "ObsRoomLight{OFF}\n"
    return
  }

  ######################################################################

  proc switchonfans {} {
    server::checkstatus
    log::info "switching on fans."
    controller::pushcommand "Fans{ON}\n"
    return
  }

  proc switchofffans {} {
    server::checkstatus
    log::info "switching off fans."
    controller::pushcommand "Fans{OFF}\n"
    return
  }

  ######################################################################

  proc openlouvers {} {
    server::checkstatus
    log::info "opening louvers."
    controller::pushcommand "Louver{ALL,OPEN}\n"
    return
  }

  proc closelouvers {} {
    server::checkstatus
    log::info "closing louvers."
    controller::pushcommand "Louver{ALL,CLOSE}\n"
    return
  }

  ######################################################################

  proc start {} {
    set controller::connectiontype "persistent"
    controller::startcommandloop
    controller::startstatusloop
    server::newactivitycommand "starting" "idle" plc::startactivitycommand
  }

}
