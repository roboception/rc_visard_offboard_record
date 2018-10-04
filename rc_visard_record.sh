#!/bin/bash

# Copyright (c) 2018 Roboception GmbH
# All rights reserved
#
# Author: Raphael Schaller
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# 1. Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
# 
# 2. Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
# 
# 3. Neither the name of the copyright holder nor the names of its contributors
# may be used to endorse or promote products derived from this software without
# specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.


set -e

# commands
GC_STREAM=gc_stream
GC_INFO=gc_info
GC_CONFIG=gc_config
DYN_STREAM=rcdynamics_stream

SCRIPT=$0

# rc_visard serial number
SN=

# default parameters
LEFT=true
RIGHT=false
DISPARITY=true
CONFIDENCE=true
ERROR=true

CAM_PARAMS=""
SLAM=""
IMU=""
HAND_EYE_CALIB=""
PROJECTOR_MODE=""

NUMBER=1000000
FRAME_RATE=3
MONO=false

VERBOSE=false
YES=false

OUT_FOLDER="rc-visard_%S_%T"

# Usage text
USAGE="Usage: $SCRIPT [options] <rc_visard serial number>\n\
 Options:\n\
  -h,--help: print this message\n\
  -v,--verbose: enable verbose mode\n\
  -y,--yes: assume Yes to all queries and do not prompt\n\
  -m,--mono: record monochrome images even if color camera\n\
  --number=[int]: number of images to capture\n\
  --out-folder=[string] (default: $OUT_FOLDER): if non-empty, store data in given folder. %S will be replaced by the serial number, %T by the current timestamp.\n\
  --freq=[int] (default: $FRAME_RATE): capturing frame rate\n\
  --left=[true,false] (default: $LEFT): capture left image\n\
  --right=[true,false] (default: $RIGHT): capture right image\n\
  --disparity=[true,false] (default: $DISPARITY): capture disparity image\n\
  --confidence=[true,false] (default: $CONFIDENCE): capture confidence image\n\
  --error=[true,false] (default: $ERROR): capture error image\n\
  --cam-params=[string]: write camera parameters to given file\n\
  --slam=[string]: enable SLAM and write trajectory to given file\n\
  --imu=[string]: record some IMU samples and write them to the given file\n\
  --hand-eye-calib=[string]: write hand-eye-calibration to given file\n\
  --projector=[Low,High,ExposureActive,ExposureAlternateActive]: projector mode. If not set, projector mode is not changed."

# check if a variable is boolean
check_is_boolean()
{
  if [ "$1" != true ] && [ "$1" != false ]; then
    echo Argument $2 is not a boolean
    PARSE_ERROR=true
  fi
}

# check if a variable's content can be used for projector control
check_projector()
{
  if [ "$1" != "Low" ] && [ "$1" != "High" ] && [ "$1" != "ExposureActive" ] && [ "$1" != "ExposureAlternateActive" ]; then
    echo Argument $2 is not a valid projector state
    PARSE_ERROR=true
  fi
}

# check if a variable is a number
check_is_number()
{
  case $1 in
    ''|*[!0-9]*) 
    echo Argument $2 is not a number
    PARSE_ERROR=true 
    ;;
  esac
}

NO_ARGS_PASSED=false
if [ "$#" -eq "0" ]; then
  NO_ARGS_PASSED=true
fi

PARSE_ERROR=false
PRINT_HELP=false

# iterate command line arguments
for i in "$@"
do
case $i in
    -h|--help)
    PRINT_HELP=true
    shift
    ;;
    -v|--verbose)
    VERBOSE=true
    shift
    ;;
    -y|--yes)
    YES=true
    shift
    ;;
    -m|--mono)
    MONO=true
    shift
    ;;
    --number=*)
    NUMBER="${i#*=}"
    check_is_number "$NUMBER" "number"
    shift
    ;;
    --out-folder=*)
    OUT_FOLDER="${i#*=}"
    shift
    ;;
    --freq=*)
    FRAME_RATE="${i#*=}"
    check_is_number "$FRAME_RATE" "freq"
    shift
    ;;
    --left=*)
    LEFT="${i#*=}"
    check_is_boolean "$LEFT" "left"
    shift
    ;;
    --right=*)
    RIGHT="${i#*=}"
    check_is_boolean "$RIGHT" "right"
    shift
    ;;
    --disparity=*)
    DISPARITY="${i#*=}"
    check_is_boolean "$DISPARITY" "disparity"
    shift
    ;;
    --confidence=*)
    CONFIDENCE="${i#*=}"
    check_is_boolean "$CONFIDENCE" "confidence"
    shift
    ;;
    --error=*)
    ERROR="${i#*=}"
    check_is_boolean "$ERROR" "error"
    shift
    ;;
    --cam-params=*)
    CAM_PARAMS="${i#*=}"
    shift
    ;;
    --slam=*)
    SLAM="${i#*=}"
    shift
    ;;
    --imu=*)
    IMU="${i#*=}"
    shift
    ;;
    --hand-eye-calib=*)
    HAND_EYE_CALIB="${i#*=}"
    shift
    ;;
    --projector=*)
    PROJECTOR="${i#*=}"
    check_projector "$PROJECTOR" "projector"
    shift
    ;;
    -*|--*)
    ARG="${i}"
    echo Option $ARG not known
    PARSE_ERROR=true
    shift
    ;;
    *)
    # unknown option
    break
    ;;
esac
if $PARSE_ERROR; then break; fi
done

if $NO_ARGS_PASSED && [ -z "$SN" ]; then
  # no arguments are given and SN not set manually -> interactively promt user for serial number
  while ! $PRINT_HELP && [ -z "$SN" ]; do
    echo "Enter the rc_visard's serial number or user defined name, 'L' to list available rc_visards, or 'h' to print the help text"
    read REPLY
    if [ "$REPLY" = "h" ]; then PRINT_HELP=true; 
    elif [ "$REPLY" = "l" ] || [ "$REPLY" = "L" ]; then
      if [ -z "$(command -v $GC_CONFIG)" ]; then
        echo "$GC_CONFIG is not found"
        pause_if_interactive_and_exit 1
      fi
      whereis $GC_CONFIG
      $GC_CONFIG -l
    else SN=$REPLY; fi
  done
elif [ -n "$1" ]; then
  SN=$1
fi

pause_if_interactive_and_exit()
{
  if $NO_ARGS_PASSED; then
    echo 'Press enter to exit...'
    read REPLY
  fi
  exit $1
}

if ! $PARSE_ERROR && $PRINT_HELP; then
  echo -e $USAGE
  pause_if_interactive_and_exit 0
fi

if $PARSE_ERROR; then
  echo -e $USAGE
  if $NO_ARGS_PASSED; then pause; fi
  pause_if_interactive_and_exit 1
fi

# replace %T and %S in OUT_FOLDER
TS=$(date +"%Y-%m-%d_%H-%M-%S")
OUT_FOLDER=$(echo $OUT_FOLDER | sed "s/%T/$TS/g")
OUT_FOLDER=$(echo $OUT_FOLDER | sed "s/%S/$SN/g")

if [ -n "$OUT_FOLDER" ] && [ -d "$OUT_FOLDER" ] && ! $YES; then
  echo "Directory '$OUT_FOLDER' already exists. Are you sure use it? (y/N)"
  read REPLY
  if [ "$REPLY" = "${REPLY#[Yy]}" ]; then
    pause_if_interactive_and_exit 1
  fi
fi

if [ -n "$OUT_FOLDER" ]; then
  mkdir -p $OUT_FOLDER
  cd $OUT_FOLDER
  echo "Writing data to '$(pwd)'"
fi

# function to promt user if file would be overwritten
check_overwrite()
{
  if [ -n "$1" ] && [ -f "$1" ] && ! $YES; then
    echo "File '$1' already exists. Are you sure to overwrite it? (y/N)"
    read REPLY
    if [ "$REPLY" = "${REPLY#[Yy]}" ]; then
      pause_if_interactive_and_exit 1
    fi
  fi
}

check_overwrite $CAM_PARAMS
check_overwrite $SLAM
check_overwrite $IMU
check_overwrite $HAND_EYE_CALIB

if [ -z "$(command -v $GC_STREAM)" ]; then
  echo "$GC_STREAM is not found"
  pause_if_interactive_and_exit 1
fi
if [ -z "$(command -v $GC_CONFIG)" ]; then
  echo "$GC_CONFIG is not found"
  pause_if_interactive_and_exit 1
fi
if [ -n "$CAM_PARAMS" ] && [ -z "$(command -v $GC_INFO)" ]; then
  echo "$GC_INFO is not found but required for writing camera info"
  pause_if_interactive_and_exit 1
fi
if [ -n "$IMU" ] && [ -z "$(command -v $DYN_STREAM)" ]; then
  echo "$DYN_STREAM is not found but required for writing IMU samples"
  pause_if_interactive_and_exit 1
fi

if [ -n "$SLAM" ] || [ -n "$IMU" ] || [ -n "$HAND_EYE_CALIB" ]; then
  # get IP of sensor for Rest API calls
  IP=$($GC_CONFIG $SN --iponly)
  
  if [ -z "$IP" ]; then 
    pause_if_interactive_and_exit 1
  fi
  if [ $VERBOSE = true ]; then echo Sensor IP is $IP; fi
fi

# forward stdout to /dev/null in case not in verbose mode
conditional_silence_cmd() 
{
  if [ $VERBOSE = false ]; then
      "$@" > /dev/null
  else
      "$@"
  fi 
}

if [ -n "$SLAM" ]; then
  echo Starting SLAM ...
  conditional_silence_cmd curl -s -S -X PUT --header 'Content-Type: application/json' --header 'Accept: application/json' -d '{ }' "http://$IP/api/v1/nodes/rc_dynamics/services/restart_slam"
fi

get_trajectory()
{
  echo "Writing trajectory to '$SLAM'" ...
  conditional_silence_cmd curl -s -S -X PUT --header 'Content-Type: application/json' --header 'Accept: application/json' -d '{ }' "http://$IP/api/v1/nodes/rc_dynamics/services/stop"
  conditional_silence_cmd curl -s -S -X PUT --header 'Content-Type: application/json' --header 'Accept: application/json' -d '{ }' "http://$IP/api/v1/nodes/rc_slam/services/get_trajectory" -o $SLAM
}

cleanup()
{
  if [ -n "$SLAM" ]; then get_trajectory; fi
  pause_if_interactive_and_exit 0 
}
trap 'cleanup' INT

if [ -n "$CAM_PARAMS" ]; then
  echo "Writing camera parameters to '$CAM_PARAMS'"
  $GC_INFO $SN > $CAM_PARAMS
fi

if [ -n "$IMU" ]; then
  echo "Writing IMU samples to '$IMU'"
  $DYN_STREAM -v $IP -s imu -o $IMU -n 20
fi

if [ -n "$HAND_EYE_CALIB" ]; then
  echo "Writing hand-eye-calibration to '$HAND_EYE_CALIB'"
  conditional_silence_cmd curl -s -S -X PUT --header 'Content-Type: application/json' --header 'Accept: application/json' -d '{ }' "http://$IP/api/v1/nodes/rc_hand_eye_calibration/services/get_calibration" -o $HAND_EYE_CALIB
fi

if $MONO; then
  COLOR_CMD="$GC_CONFIG $SN ComponentSelector=Intensity PixelFormat=Mono8 ComponentSelector=IntensityCombined PixelFormat=Mono8"
else
  COLOR_CMD="$GC_CONFIG $SN ComponentSelector=Intensity PixelFormat=YCbCr411_8 ComponentSelector=IntensityCombined PixelFormat=YCbCr411_8"
fi

if $VERBOSE; then echo "$COLOR_CMD"; fi
$COLOR_CMD 2> /dev/null

# build gc_stream command
ENABLE_INTENSITY=0
ENABLE_COMBINED=0
ENABLE_DISPARITY=0
ENABLE_CONFIDENCE=0
ENABLE_ERROR=0

if [ $LEFT = true ] && [ $RIGHT = true ]; then 
  ENABLE_COMBINED=1 
elif [ $LEFT = true ]; then
  ENABLE_INTENSITY=1
elif [ $RIGHT = true ]; then
  ENABLE_COMBINED=1
fi
if [ $DISPARITY = true ]; then ENABLE_DISPARITY=1; fi
if [ $CONFIDENCE = true ]; then ENABLE_CONFIDENCE=1; fi
if [ $ERROR = true ]; then ENABLE_ERROR=1; fi

GC_COMMAND="$GC_STREAM $SN n=$NUMBER\
 AcquisitionFrameRate=$FRAME_RATE\
 ComponentSelector=Intensity ComponentEnable=$ENABLE_INTENSITY\
 ComponentSelector=IntensityCombined ComponentEnable=$ENABLE_COMBINED\
 ComponentSelector=Disparity ComponentEnable=$ENABLE_DISPARITY\
 ComponentSelector=Confidence ComponentEnable=$ENABLE_CONFIDENCE\
 ComponentSelector=Error ComponentEnable=$ENABLE_ERROR"
 
if [ -n "$PROJECTOR" ]; then
  GC_COMMAND+=" LineSelector=Out1 LineSource=$PROJECTOR"
fi

echo Start streaming ...
if [ $VERBOSE = true ]; then echo "$GC_COMMAND"; fi

$GC_COMMAND

if [ -n "$SLAM" ]; then get_trajectory; 
else pause_if_interactive_and_exit 0; fi

