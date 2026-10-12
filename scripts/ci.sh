#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
scripts/test.sh
scripts/build-macos.sh
