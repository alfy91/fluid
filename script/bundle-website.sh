#!/usr/bin/env bash
# run from project root
set -xe

WEBSITE=$1
. script/bundle-page.sh $WEBSITE

# Only support one level of nesting for now
shopt -s nullglob

set +x
PAGES=($(for FILE in src/Website/$WEBSITE/*.{purs,html}; do
   basename "$FILE" | sed 's/\.[^.]*$//'
done | sort -u))
set -x

echo "Processing ${WEBSITE} pages: ${PAGES[@]}"

for PAGE in "${PAGES[@]}"; do
   . script/bundle-page.sh $WEBSITE.$PAGE
   done
shopt -u nullglob

WEBSITE_LISP_CASE=$(./script/util/lisp-case.sh "$WEBSITE")
./script/util/copy-static.sh $WEBSITE_LISP_CASE

echo "Bundled website $WEBSITE"
