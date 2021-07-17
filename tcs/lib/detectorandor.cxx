////////////////////////////////////////////////////////////////////////

// This file is part of the UNAM telescope control system.

// $Id: detectordummy.cxx 3542 2020-05-16 00:42:23Z Alan $

////////////////////////////////////////////////////////////////////////

// Copyright © 2016, 2017, 2019 Alan M. Watson <alan@astro.unam.mx>
//
// Permission to use, copy, modify, and distribute this software for any
// purpose with or without fee is hereby granted, provided that the
// above copyright notice and this permission notice appear in all
// copies.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
// WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
// AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
// DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR
// PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
// TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
// PERFORMANCE OF THIS SOFTWARE.

////////////////////////////////////////////////////////////////////////

#include <float.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

#include "detector.h"

////////////////////////////////////////////////////////////////////////

static char description[DETECTOR_STR_BUFFER_SIZE] = "";
static double detectortemperature = 0;
static double housingtemperature = 0;
static double coolersettemperature = 0;
static const char *cooler = "";

static char readmode[DETECTOR_STR_BUFFER_SIZE] = "";

static unsigned long fullnx = 0;
static unsigned long fullny = 0;
static unsigned long windowsx = 0;
static unsigned long windowsy = 0;
static unsigned long windownx = 0;
static unsigned long windowny = 0;

static unsigned long binning = 1;

////////////////////////////////////////////////////////////////////////

#include "atmcdLXd.h"

////////////////////////////////////////////////////////////////////////

static time_t exposureend = 0;

////////////////////////////////////////////////////////////////////////

static char *
msg(const char *fmt, ...)
{
  static char s[1024];
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(s, sizeof(s), fmt, ap);
  va_end(ap);
  return s;
}

////////////////////////////////////////////////////////////////////////

const char *
detectorrawstart(void)
{
  DETECTOR_OK();
}

////////////////////////////////////////////////////////////////////////

const char *
detectorrawopen(char *identifier)
{
  unsigned int status;

  if (detectorrawgetisopen())
    DETECTOR_ERROR("a detector is currently open");

  char etcdir[] = "/usr/local/etc/andor";
  status = Initialize(etcdir);
  if (status != DRV_SUCCESS) {
    DETECTOR_ERROR(msg("unable to initialize detector (status is %u)", status));
  }
  
  sleep(2);
  
  char model[DETECTOR_STR_BUFFER_SIZE];
  status = GetHeadModel(model);
  if (status != DRV_SUCCESS)
    DETECTOR_ERROR(msg("unable to get head model (status is %u)", status));  
  
  int serialnumber;
  status = GetCameraSerialNumber(&serialnumber);
  if (status != DRV_SUCCESS)
    DETECTOR_ERROR(msg("unable to get serial number (status is %u)", status));

  snprintf(description, sizeof(description), "Andor %s (%d)", model, serialnumber);    
  
  coolersettemperature = 25.0;
  cooler = "off";
  status = CoolerOFF();
  if (status != DRV_SUCCESS)
    DETECTOR_ERROR(msg("unable to switch off cooler (status is %u)", status));
    
  int nx;
  int ny;
  status = GetDetector(&nx, &ny);
  if (status != DRV_SUCCESS)
    DETECTOR_ERROR(msg("unable to get detector size (status is %u)", status));
  fullnx = nx;
  fullny = ny;  
    
  status = SetReadMode(4);
  if (status != DRV_SUCCESS)
    DETECTOR_ERROR(msg("unable to select raw read mode (status is %u)", status));

  status = SetAcquisitionMode(1);
  if (status != DRV_SUCCESS)
    DETECTOR_ERROR(msg("unable to select raw acquisition mode (status is %u)", status));

  status = SetShutter(1,0,50,50);
  if (status != DRV_SUCCESS)
    DETECTOR_ERROR(msg("unable to select raw shutter mode (status is %u)", status));

  detectorrawsetisopen(true);

  return detectorrawsetwindow(0, 0, 0, 0);
}

////////////////////////////////////////////////////////////////////////

const char *
detectorrawclose(void)
{
  detectorrawsetisopen(false);
  ShutDown();
  DETECTOR_OK();
}

////////////////////////////////////////////////////////////////////////

const char *
detectorrawreset(void)
{
  DETECTOR_CHECK_OPEN();
  DETECTOR_OK();
}

////////////////////////////////////////////////////////////////////////

const char *
detectorrawmovefilterwheel(unsigned long position)
{
  DETECTOR_CHECK_OPEN();
  if (position != 0)
    DETECTOR_ERROR("unable to move the filter wheel");
  DETECTOR_OK();
}

////////////////////////////////////////////////////////////////////////

const char *
detectorrawexpose(double exposuretime, const char *shutter)
{
  unsigned int status;

  DETECTOR_CHECK_OPEN();

  if (strcmp(shutter, "open") != 0 && strcmp(shutter, "closed") != 0)
    DETECTOR_ERROR("invalid shutter argument");

  status = SetExposureTime(exposuretime);
  if (status != DRV_SUCCESS)
    DETECTOR_ERROR(msg("unable to set exposure time (status is %u)", status));
    
  if (strcmp(shutter, "open") == 0)
    status = SetShutter(0, 0, 50, 50);
  else 
    status = SetShutter(0, 2, 50, 50);
  if (status != DRV_SUCCESS)
    DETECTOR_ERROR(msg("unable to set shutter (status is %u)", status));
    
  status = StartAcquisition();
  if (status != DRV_SUCCESS)
    DETECTOR_ERROR(msg("unable to start acquisition (status is %u)", status));

  DETECTOR_OK();
}

////////////////////////////////////////////////////////////////////////

const char *
detectorrawcancel(void)
{
  DETECTOR_CHECK_OPEN();
  unsigned int status;
  status = AbortAcquisition();
  if (status != DRV_SUCCESS && status != DRV_IDLE)
    DETECTOR_ERROR(msg("unable to abort acquisition (status is %u)", status));    
  DETECTOR_OK();
}

////////////////////////////////////////////////////////////////////////

bool
detectorrawgetreadytoberead(void)
{
  int status;
  GetStatus(&status);
  return status != DRV_ACQUIRING;
}

////////////////////////////////////////////////////////////////////////

const char *
detectorrawread(void)
{
  DETECTOR_CHECK_OPEN();

  if (!detectorrawgetreadytoberead())
    DETECTOR_ERROR("the detector is not ready to be read");

  unsigned long nx = detectorrawgetpixnx();
  unsigned long ny = detectorrawgetpixny();

  unsigned short pix[ny * nx];
  unsigned int status;
  status = GetAcquiredData16(pix, nx * ny);
  if (status != DRV_SUCCESS)
    DETECTOR_ERROR(msg("unable to get pixel data (nx is %lu ny is %lu status is %u)", nx, ny, status));
  
  detectorrawpixstart();
  for (unsigned long iy = 0; iy < ny; ++iy) {
    for (unsigned long ix = 0; ix < nx; ++ix) {
      long lpix = pix[iy * nx + ix];
      detectorrawpixnext(&lpix, 1);
    }
  }
  detectorrawpixend();
  
  DETECTOR_OK();
}

////////////////////////////////////////////////////////////////////////

const char *
detectorrawsetreadmode(const char *newreadmode)
{
  DETECTOR_CHECK_OPEN();
  if (strcmp(newreadmode, "") == 0)
    DETECTOR_OK();
  if (strlen(newreadmode) >= DETECTOR_STR_BUFFER_SIZE) {
    DETECTOR_ERROR("invalid detector read mode");
  }
  strcpy(readmode, newreadmode);
  DETECTOR_OK();
}

////////////////////////////////////////////////////////////////////////

const char *
detectorrawsetwindow(unsigned long newsx, unsigned long newsy, unsigned long newnx, unsigned long newny)
{
  DETECTOR_CHECK_OPEN();
  if (newsx == 0 && newnx == 0) {
    newnx = fullnx;
  }
  if (newsy == 0 && newny == 0) {
    newny = fullny;
  }
  windowsx = newsx;
  windowsy = newsy;
  windownx = newnx;
  windowny = newny;
  return detectorrawsetbinning(1); 
}

////////////////////////////////////////////////////////////////////////

const char *
detectorrawsetbinning(unsigned long newbinning)
{
  unsigned int status;  
  DETECTOR_CHECK_OPEN();
  
  int maxbinningx;
  status = GetMaximumBinning(4, 0, &maxbinningx);
  if (status != DRV_SUCCESS)
    DETECTOR_ERROR(msg("unable to get maximum x binning (status is %u)", status));

  int maxbinningy;
  status = GetMaximumBinning(4, 1, &maxbinningy);
  if (status != DRV_SUCCESS)
    DETECTOR_ERROR(msg("unable to get maximum x binning (status is %u)", status));
    
  unsigned int maxbinning;
  if (maxbinningx >= maxbinningy)
    maxbinning = maxbinningy;
  else
    maxbinning = maxbinningx;
    
  if (newbinning > maxbinning)
    DETECTOR_ERROR(msg("requested binning (%d) exceeds maximum supported binning (%d)", newbinning, maxbinning));
  
  status = SetImage(newbinning, newbinning, windowsx + 1, windowsx + windownx, windowsy + 1, windowsy + windowny);
  if (status != DRV_SUCCESS)
    DETECTOR_ERROR(msg("unable to set detector window and binning (status is %u)", status));
  
  binning = newbinning;
  
  detectorrawsetpixnx(windownx / binning);
  detectorrawsetpixny(windowny / binning);

  DETECTOR_OK();
}

////////////////////////////////////////////////////////////////////////

const char *
detectorrawupdatestatus(void)
{
  DETECTOR_CHECK_OPEN();
  
  float temperature;
  unsigned int status;
  status = GetTemperatureF(&temperature);
  if (status == DRV_NOT_INITIALIZED) {
    DETECTOR_ERROR("detector is not initialized");
  } else if (status == DRV_TEMP_OFF) {
    cooler = "off";
    detectortemperature = temperature;
  } else if (status == DRV_TEMP_STABILIZED) {
    cooler = "stabilized";
  } else if (status == DRV_TEMP_NOT_REACHED) {
    cooler = "cooling";
  } else if (status == DRV_TEMP_DRIFT) {
    cooler = "drifting";
  } else if (status == DRV_TEMP_NOT_STABILIZED) {
    cooler = "stabilizing";
  } else {
    cooler = "other";
  }
  detectortemperature = temperature;

  DETECTOR_OK();
}

////////////////////////////////////////////////////////////////////////

const char *
detectorrawgetvalue(const char *name)
{
  static char value[DETECTOR_STR_BUFFER_SIZE]; 
  if (strcmp(name, "description") == 0)
    snprintf(value, sizeof(value), "%s", description);
  else if (strcmp(name, "detectortemperature") == 0)
    snprintf(value, sizeof(value), "%+.1f", detectortemperature);
  else if (strcmp(name, "coolersettemperature") == 0)
    snprintf(value, sizeof(value), "%+.1f", coolersettemperature);
  else if (strcmp(name, "cooler") == 0)
    snprintf(value, sizeof(value), "%s", cooler);
  else if (strcmp(name, "readmode") == 0)
    snprintf(value, sizeof(value), "%s", readmode);
  else if (strcmp(name, "windowsx") == 0)
    snprintf(value, sizeof(value), "%lu", windowsx);
  else if (strcmp(name, "windowsy") == 0)
    snprintf(value, sizeof(value), "%lu", windowsy);
  else if (strcmp(name, "windownx") == 0)
    snprintf(value, sizeof(value), "%lu", windownx);
  else if (strcmp(name, "windowny") == 0)
    snprintf(value, sizeof(value), "%lu", windowny);
  else if (strcmp(name, "binning") == 0)
    snprintf(value, sizeof(value), "%lu", binning);
  else
    snprintf(value, sizeof(value), "%s", detectorrawgetdatavalue(name));
  return value;
}

////////////////////////////////////////////////////////////////////////

const char *
detectorrawsetcooler(const char *newcooler)
{
  DETECTOR_CHECK_OPEN();
  if (strcmp(newcooler, "off") == 0) {
    unsigned int status;
    status = CoolerOFF();
    if (status != DRV_SUCCESS)
      DETECTOR_ERROR(msg("unable to switch off cooler (status is %u)", status));
    cooler = "off";
    DETECTOR_OK();
  } else {
    if (strcmp(newcooler, "following") == 0) {
      detectorrawupdatestatus();
      coolersettemperature = housingtemperature;
    } else if (strcmp(newcooler, "on") != 0) {
      char *end;
      double newcoolersettemperature = strtod(newcooler, &end);
      if (*end != 0)
        DETECTOR_ERROR("invalid cooler state");
      newcoolersettemperature = rint(newcoolersettemperature);
      coolersettemperature = newcoolersettemperature;      
      newcooler = "on";
    }
    unsigned int status;
    status = SetTemperature((int) coolersettemperature);
    if (status != DRV_SUCCESS)
      DETECTOR_ERROR(msg("unable to set cooler set temperature (status is %u)", status));
    status = CoolerON();
    if (status != DRV_SUCCESS)
      DETECTOR_ERROR(msg("unable to switch on cooler (status is %u)", status));
    cooler = newcooler;
    DETECTOR_OK();
  }
}

////////////////////////////////////////////////////////////////////////

const char *
detectorrawfilterwheelmove(unsigned long newposition)
{
  DETECTOR_SHOULD_NOT_BE_CALLED();
}

const char *
detectorrawfilterwheelupdatestatus(void)
{
  DETECTOR_SHOULD_NOT_BE_CALLED();
}

const char *
detectorrawfilterwheelgetvalue(const char *name)
{
  DETECTOR_SHOULD_NOT_BE_CALLED();
}

////////////////////////////////////////////////////////////////////////
