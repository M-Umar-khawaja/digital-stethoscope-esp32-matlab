#!/bin/sh
# Runs MATLAB code in the portable Octave on this PC (for verification only).
O=/c/Users/umark/AppData/Local/Temp/hnosar-octave-runtime/bin/octave-cli-9.4.0.exe
ROOT=/cygdrive/c$(cd "$(dirname "$0")/.." && pwd | sed "s|^/c||")
exec "$O" --no-gui --no-window-system --quiet --eval "addpath('$ROOT/core'); addpath('$ROOT/tests'); addpath('$ROOT/scripts'); addpath('$ROOT'); $1"
