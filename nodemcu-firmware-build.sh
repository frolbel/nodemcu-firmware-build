#!/bin/bash

# Purpose: Build NodeMCU firmware with advanced settings for the ESP8266 on local machine.
# Author: Alexaner Belkin
# Source: https://github.com/frolbel/nodemcu-firmware-build

set -e

# Before using the current script, you need to install srec_cat:
# sudo apt-get install srecord
hash srec_cat 2>/dev/null || { echo >&2 "The srec_cat is required but it's not installed.  Aborting."; exit 1; }

# Definition of the toolchain directory
TOOLCHAIN_DIR=/opt/Espressif/esp-open-sdk/xtensa-lx106-elf/bin/

# An opensource toolchain is available in https://github.com/pfalcon/esp-open-sdk.
# For set up manually the GCC toolchain and SDK you must do the following:
# 1) Use Git command to clone the git repository esp-open-sdk into your local directory: git clone --recursive https://github.com/pfalcon/esp-open-sdk
# 2) Review the open SDK's README.md and edit line 3 of the Makefile to select which the Espressif SDK Version that you wish to install if it is not the (default) latest version, e.g. VENDOR_SDK = 1.3.0
# 3) Run the make to install: make STANDALONE=y |& tee make0.log
# Рlease see: http://www.esp8266.com/wiki/doku.php?id=toolchain
if [ ! -d "$TOOLCHAIN_DIR" ]; then
   echo "ERROR: Failed toolchain. Check the location of the tool in the following folder: $TOOLCHAIN_DIR"
   exit 1
fi
export PATH=$TOOLCHAIN_DIR:$PATH

# Comment out the NODEMCU_MODULES definition to use the default definition
# Can be the following values: adc,ads1115,adxl345,am2320,apa102,bit,ds18b20,bme280,bmp085,cjson,coap,cron,crypto,dht,ds18b20,encoder,enduser_setup,file,gdbstub,gpio,hdc1080,hmc5883l,http,hx711,i2c,l3g4200d,mcp4725,mdns,mqtt,net,node,ow,pcm,perf,pwm,rc,rfswitch,rotary,rtcfifo,rtcmem,rtctime,si7021,sigma_delta,sjson,enduser_setup,rtctime,sntp,somfy,spi,struct,switec,tcs34725,tls,tm1829,tmr,tsl2561,u8g,uart,ucg,websocket,wifi,wps,ws2801,ws2812,xpt2046
# Рlease see: https://nodemcu.readthedocs.io/en/master/
#NODEMCU_MODULES=node,file,gpio,wifi,net,tmr,uart,mqtt,spi,http,ucg,u8g
NODEMCU_MODULES=adc,bmp085,file,gpio,http,i2c,mdns,net,node,rtcfifo,rtcmem,rtctime,sntp,tmr,websocket,wifi,thermistor

# Comment out the BUILD_AUTHOR definition to use the default definition
BUILD_AUTHOR="Alexaner Belkin"

# Comment out the DEBUG_ENABLED definition to use the default definition
DEBUG_ENABLED=false

# Comment out the SSL_ENABLED definition to use the default definition
SSL_ENABLED=false

# Comment out the INTEGER_ONLY definition to use the default definition
# INTEGER_ONLY=true

# Comment out the FLOAT_ONLY definition to use the default definition
FLOAT_ONLY=true

# Enabling FatFs
# Рlease see: http://nodemcu.readthedocs.io/en/latest/en/sdcard/
FATFS_ENABLED=false

#The branch definition is applicable when there is no directory: /nodemcu-firmware
#BRANCH=dev
BRANCH=master

FIRMWARE_DIR=$PWD/nodemcu-firmware
FIRMWARE_RELEASE_DIR=$PWD/build_release

echo "Checking the existence of the directory: $firmwaredir"
if [ -d $FIRMWARE_DIR ]; then
    echo "Directory exists"
    cd $FIRMWARE_DIR
    BRANCH="$(git rev-parse --abbrev-ref HEAD | sed -r 's/[\/\\]+/_/g')"
    #git reset --hard
    git pull
else
    if [ -z "$BRANCH" ]; then
        BRANCH=master
    fi
    # git clone --depth=1 --branch=$BRANCH https://github.com/nodemcu/nodemcu-firmware.git
    git clone --depth=1 --branch=$BRANCH https://github.com/frolbel/nodemcu-firmware.git
    cd $FIRMWARE_DIR
fi

# Remove old files
if [ -d $FIRMWARE_RELEASE_DIR ]; then
    rm -rf "$FIRMWARE_RELEASE_DIR"
fi
if [ -s "$FIRMWARE_DIR"/bin/* ]; then
    rm "$FIRMWARE_DIR"/bin/*
fi

# Create release directory
mkdir "$FIRMWARE_RELEASE_DIR"

BUILD_DATE="$(date "+%Y-%m-%d %H:%M")"
COMMIT_ID="$(git rev-parse HEAD)"

# Set default nodemcu modules
if [ -z "$NODEMCU_MODULES" ]; then
    NODEMCU_MODULES=adc,bit,dht,file,gpio,i2c,mqtt,net,node,ow,spi,tls,tmr,uart,wifi
fi

# Define the Build User
if [ -z "$BUILD_AUTHOR" ]; then
    BUILD_AUTHOR="$(whoami)"
fi

# figure out whether SSL is enabled in user_config.h
if grep -Eq "^#define CLIENT_SSL_ENABLE" app/include/user_config.h; then
    SSL="true"
else
    SSL="false"
fi

# check whether the user made changes to the version file, if so then assume she wants to use a custom version rather
# than the one that would be set here -> we can't modify it
if git diff --staged --quiet app/include/user_version.h; then
    CAN_MODIFY_VERSION=true
else
    CAN_MODIFY_VERSION=false
fi

# use the Git branch and the current time stamp to define image name if IMAGE_NAME not set
if [ -z "$IMAGE_NAME" ]; then
  IMAGE_NAME=${BRANCH}_"$(date "+%Y%m%d-%H%M")"
fi

# modify user_modules.h
cd app/include
# replace ',' by newline, make it uppercase and prepend every item with '#define LUA_USE_MODULES_'
MODULES_STRING=$(echo $NODEMCU_MODULES | tr , '\n' | tr '[a-z]' '[A-Z]' | perl -pe 's/(.*)\n/#define LUA_USE_MODULES_$1\n/g')
# inject the modules string into user_modules.h between '#ifndef LUA_CROSS_COMPILER\n' and '\n#endif  /* LUA_CROSS_COMPILER'
# the 's' flag in '/sg' makes . match newlines
# Perl creates a temp file which is removed right after the manipulation
perl -e 'local $/; $_ = <>; s/(#ifndef LUA_CROSS_COMPILER\n)(.*)(\n#endif.*LUA_CROSS_COMPILER.*)/$1'"$MODULES_STRING"'$3/sg; print' user_modules.h > user_modules.h.tmp && mv user_modules.h.tmp user_modules.h
cd ../../

# modify user_config.h
#if [ $DEBUG_ENABLED = true ]; then
    #sed -i '3a\\/\/ Enable debugging\n#define COAP_DEBUG\n' app/include/user_config.h
    #sed -i '/\/\/ #define DEVELOP_VERSION/c #define DEVELOP_VERSION\n' app/include/user_config.h
#fi
if [ $DEBUG_ENABLED = true ]; then
  echo "Enabling DEBUG in user_config.h"
  sed -e 's/\(^\/\/ *#define DEVELOP_VERSION\)/#define DEVELOP_VERSION/g' app/include/user_config.h > app/include/user_config.h.tmp
else
  echo "Disabling DEBUG in user_config.h"
  sed -e 's/\(^#define DEVELOP_VERSION\)/\/\/ #define DEVELOP_VERSION/g' app/include/user_config.h > app/include/user_config.h.tmp
fi
if [ $BUILD_FATFS = true ]; then
  echo "Enabling BUILD_FATFS in user_config.h"
  sed -i 's/\(^\/\/ *#define BUILD_FATFS\)/#define BUILD_FATFS/g' app/include/user_config.h.tmp
else
  echo "Disabling BUILD_FATFS in user_config.h"
  sed -i 's/\(^#define BUILD_FATFS\)/\/\/ #define BUILD_FATFS/g' app/include/user_config.h.tmp
fi
if [ $SSL_ENABLED = true ]; then
  echo "Enabling SSL in user_config.h"
  sed -i 's/\(^\/\/ *#define CLIENT_SSL_ENABLE\)/#define CLIENT_SSL_ENABLE/g' app/include/user_config.h.tmp
else
  echo "Disabling SSL in user_config.h"
  sed -i 's/\(^#define CLIENT_SSL_ENABLE\)/\/\/ #define CLIENT_SSL_ENABLE/g' app/include/user_config.h.tmp
fi
mv app/include/user_config.h.tmp app/include/user_config.h;

# modify user_version.h to provide more info in NodeMCU welcome message, doing this by passing
# EXTRA_CCFLAGS="-DBUILD_DATE=... AND -DNODE_VERSION=..." to make turned into an escaping/expanding nightmare for which
# I never found a good solution
if [ "$CAN_MODIFY_VERSION" = true ]; then
  sed -i 's/\(NodeMCU [^"]*\)/\1 - custom build by '"$BUILD_AUTHOR"'\\n\\tbranch: '"$BRANCH"'\\n\\tcommit: '"$COMMIT_ID"'\\n\\tdebug enabled: '"$DEBUG_ENABLED"'\\n\\tSSL: '"$SSL"'\\n\\tmodules: '"$NODEMCU_MODULES"'\\n/g' app/include/user_version.h
  sed -i 's/"unspecified"/"created on '"$BUILD_DATE"'\\n"/g' app/include/user_version.h
fi

make clean

# make a float build if !only-integer
if [ -z "$INTEGER_ONLY" ]; then
  make WRAPCC="$(which ccache)" clean all
  echo "***Float build successful!!!"
  cd bin
  srec_cat -output nodemcu_float_"${IMAGE_NAME}".bin -binary 0x00000.bin -binary -fill 0xff 0x00000 0x10000 0x10000.bin -binary -offset 0x10000
  # copy and rename the mapfile to bin/
  cp ../app/mapfile "$FIRMWARE_RELEASE_DIR"/nodemcu_float_"${IMAGE_NAME}".map
  mv nodemcu_float_"${IMAGE_NAME}".bin "$FIRMWARE_RELEASE_DIR"
  cd ../
fi

# make an integer build
if [ -z "$FLOAT_ONLY" ]; then
  make WRAPCC="$(which ccache)" EXTRA_CCFLAGS="-DLUA_NUMBER_INTEGRAL" clean all
  echo "***Integer build successful!!!"
  cd bin
  srec_cat -output nodemcu_integer_"${IMAGE_NAME}".bin -binary 0x00000.bin -binary -fill 0xff 0x00000 0x10000 0x10000.bin -binary -offset 0x10000
  # copy and rename the mapfile to bin/
  cp ../app/mapfile "$FIRMWARE_RELEASE_DIR"/nodemcu_integer_"${IMAGE_NAME}".map
  mv nodemcu_integer_"${IMAGE_NAME}".bin "$FIRMWARE_RELEASE_DIR"
  cd ../
fi

# revert the changes made to the debug enabling
#if [ $DEBUG_ENABLED = true ]; then
  #git checkout app/include/user_config.h
#fi

# revert the changes made to the version params
if [ "$CAN_MODIFY_VERSION" = true ]; then
  git checkout app/include/user_version.h
fi

if [ -d $FIRMWARE_RELEASE_DIR ]; then
   echo -e "***The firmware is in the following directory:\n$FIRMWARE_RELEASE_DIR"
fi
