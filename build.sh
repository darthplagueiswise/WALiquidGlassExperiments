#!/usr/bin/env bash

set -e

if [ -z "$THEOS" ]; then
    if [ -d "$HOME/theos" ]; then
        export THEOS="$HOME/theos"
    else
        echo 'THEOS not set and ~/theos not found.'
        exit 1
    fi
fi

if [ "$1" == "rootless" ]; then
    make clean 2>/dev/null || true
    rm -rf .theos

    echo 'Building WALiquidGlassExperiments rootless package'

    export THEOS_PACKAGE_SCHEME=rootless
    make package

    cd packages
    BASE_DEB="$(ls -t *.deb | head -n1)"
    if [ -n "$BASE_DEB" ]; then
        NEW_NAME="${BASE_DEB%.deb}-rootless.deb"
        mv "$BASE_DEB" "$NEW_NAME"
    fi
    cd ..

    echo "Done. You can find the deb file at: $(pwd)/packages"
elif [ "$1" == "dylib" ]; then
    make clean 2>/dev/null || true
    rm -rf .theos

    echo 'Building WALiquidGlassExperiments dylib'

    make

    mkdir -p packages
    cp .theos/obj/debug/WALiquidGlassExperiments.dylib packages/WALiquidGlassExperiments.dylib

    echo "Done. You can find the dylib at: $(pwd)/packages/WALiquidGlassExperiments.dylib"
else
    echo 'Usage: ./build.sh <rootless/dylib>'
    exit 1
fi
