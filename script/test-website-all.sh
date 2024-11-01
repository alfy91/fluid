#!/usr/bin/env bash
# run from project root
set -xe

set +x
WEBSITES2=($(for FILE in src/Website/Test/* src/Website/Test/*.purs; do
    basename "$FILE" | sed 's/\.[^.]*$//'
done | sort -u))
set -x

echo "HOW ABOUT THIS: ${WEBSITES2[@]}"

set +x
WEBSITES=($(for FILE in src/Website/*.{purs,html}; do
   basename "$FILE" | sed 's/\.[^.]*$//'
done | sort -u))
set -x

echo "Checking for website tests: ${WEBSITES[@]}"

for WEBSITE in "${WEBSITES[@]}"; do
   . script/test-website.sh $WEBSITE
   done
