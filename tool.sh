#!/bin/bash

# Helper script to invoke `bindgen.cr`

if [[ "$OSTYPE" == "darwin"* ]]; then
  BASE="$(dirname "$(greadlink -f "$0")")"
else
  BASE="$(dirname "$(readlink -f "$0")")"
fi

CLANG_DIR="$BASE/clang/"
SOURCE_FILE="$BASE/src/bindgen.cr"

function print_clang_error {
  echo "  Bindgen requires a full installation of Clang, its libraries and development"
  echo "  headers.  Please install these first, and restart this script."
  echo "  You can also manually run 'cmake . && make' in clang/ for debugging this issue."
  echo "  Full path to clang/: $CLANG_DIR"

  exit 1
}

if [ ! -f "$CLANG_DIR/parser" ]; then
  echo "** clang/parser not found.  Building now."
  cd "$CLANG_DIR"
  ( cmake . && make ) || print_clang_error
  cd -
fi

OLD_PWD="$PWD"
cd "$BASE"

# Build bindgen itself, unless it's up to date.
BINARY="$BASE/bin/bindgen"

if [ ! -x "$BINARY" ] || [ -n "$(find src assets builtin_types.yml shard.yml -newer "$BINARY" -print -quit)" ]; then
  echo "** Building bin/bindgen." >&2
  mkdir -p bin
  crystal build "$SOURCE_FILE" -o "$BINARY" || {
    echo '  1) Make sure you have crystal installed' >&2
    echo '  2) Make sure `crystal` is in your $PATH' >&2
    exit 127
  }
fi

if [[ "$*" == *"--chdir"* ]]; then
  exec "$BINARY" "$@"
else
  exec "$BINARY" --chdir "$OLD_PWD" "$@"
fi
