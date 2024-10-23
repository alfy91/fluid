#!/usr/bin/env bash
set -xe

toLispCase() {
   INPUT="$1"
   RESULT=$(echo "$INPUT" | sed -E 's/([a-z0-9])([A-Z])/\1-\2/g' | tr '[:upper:]' '[:lower:]')
   echo "$RESULT"
}

WEBSITE=FluidOrg
yarn bundle-website $WEBSITE

WEBSITE_LISP_CASE=$(toLispCase "$WEBSITE")
unzip archive/0.3.1.zip -d dist/$WEBSITE_LISP_CASE # already has 0.3.1 as top-level folder
unzip archive/0.6.1.zip -d dist/$WEBSITE_LISP_CASE/0.6.1
cp -r web/pdf dist/$WEBSITE_LISP_CASE
