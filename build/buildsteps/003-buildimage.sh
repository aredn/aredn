#!/bin/sh

cd "$BUILDROOTBASE"


make defconfig
# Tools Build
make IGNORE_ERRORS=m V=99 BUILD_LOG=1 tools/install -j3
# toolchain build
make IGNORE_ERRORS=m V=99 BUILD_LOG=1 toolchain/install
#kernel compile
make IGNORE_ERRORS=m V=99 BUILD_LOG=1 target/compile -j3
# package compile
make IGNORE_ERRORS=m V=99 BUILD_LOG=1 package/compile -j3
#package installation
make IGNORE_ERRORS=m V=99 BUILD_LOG=1 package/install -j3
#package index
make IGNORE_ERRORS=m V=99 BUILD_LOG=1 package/index
#image generation
make IGNORE_ERRORS=m V=99 BUILD_LOG=1 target/install -j3

# Cleanup for now until fix cleanup module
rm -Rf build_dir/*
rm -Rf staging_dir/*

SHORT_COMMIT=$(echo "$GIT_COMMIT" | awk  '{ string=substr($0, 1, 8); print string; }' )
SHORT_BRANCH=$(echo "$GIT_BRANCH" | awk 'match($0,"/"){print substr($0,RSTART+1)}')

if [ ! -z "$BUILD_SET_VERSION" ]; then
  MYBUILDNAME="$BUILD_SET_VERSION"
else
  MYBUILDNAME="${SHORT_BRANCH}-${BUILD_NUMBER}-${SHORT_COMMIT}"
fi
rename "s/openwrt.*ar71xx-generic/AREDN-$MYBUILDNAME/g" bin/ar71xx/*

