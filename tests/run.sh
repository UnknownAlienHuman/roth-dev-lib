#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."

for file in tests/test_*.lua; do
  printf '== %s\n' "$file"
  texlua "$file"
done
