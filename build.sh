#!/bin/bash
set -e

# Compatibility wrapper (some folks expect ./build.sh)
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

exec ./build-app.sh


