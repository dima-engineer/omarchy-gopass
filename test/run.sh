#!/bin/bash

set -o pipefail
cd "$(dirname "$0")/.." || exit 1

echo "== GopassSearch.js =="
node test/search.js
