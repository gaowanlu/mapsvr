#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
echo "Working directory: $SCRIPT_DIR"

cd "$SCRIPT_DIR"

./clean.sh
cd "$SCRIPT_DIR"
git submodule update --remote thirdparty/avant
