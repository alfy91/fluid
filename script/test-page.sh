#!/usr/bin/env bash
set -e

. script/util/lisp-case.sh

yarn puppeteer browsers install chrome
yarn puppeteer browsers install firefox

WEBSITE=$1
MODULE=$2

SRC_PATH=${MODULE//./\/}
if [ ! -e "src/Website/$SRC_PATH.purs" ]; then
  echo "Error: 'Website/$SRC_PATH.purs' not found."
  exit 1
fi

# don't need to have "deployed" this to dist/
# instead the following just picks up from output-es/
WEBSITE_LISP_CASE=$(toLispCase "$WEBSITE")
node puppeteer.js Website.Test.$MODULE $WEBSITE_LISP_CASE
