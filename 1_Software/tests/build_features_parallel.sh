#!/bin/sh
# Builds the feature table with several Octave processes at once (this PC,
# verification only). Usage: tests/build_features_parallel.sh [nParts]
cd "$(dirname "$0")/.." || exit 1
N=${1:-3}
rm -f models/parts/feat_*.mat
for aug in false true; do
  for p in $(seq 1 "$N"); do
    tests/run_octave.sh "build_features_part($aug, $p, $N);" > "models/parts_${aug}_${p}.log" 2>&1 &
  done
done
wait
tests/run_octave.sh "merge_feature_tables();" 2>&1 | grep -v warning
