#!/usr/bin/env bash
set -xe

toLispCase() {
   INPUT="$1"
   RESULT=$(echo "$INPUT" | sed -E 's/([a-z0-9])([A-Z])/\1-\2/g' | tr '[:upper:]' '[:lower:]')
   echo "$RESULT"
}

rm -rf dist/
./script/compile.sh
./script/bundle.sh test Test.Test
./script/bundle-fluid-org
