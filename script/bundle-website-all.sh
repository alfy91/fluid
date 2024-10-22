#!/usr/bin/env bash
# run from project root
# set -x
set -e

WEBSITES=($(for FILE in src/Website/*.{purs,html}; do
   basename "$FILE" | sed 's/\.[^.]*$//'
done | sort -u))

echo "Bundling websites: ${WEBSITES[@]}"

for WEBSITE in "${WEBSITES[@]}"; do
   . script/bundle-website-new.sh $WEBSITE
   done
