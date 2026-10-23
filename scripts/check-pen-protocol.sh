#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

javac -d "$tmp_dir" \
  "$repo_root/android/app/src/main/java/com/cmwen/lenovo_graphics_pad/PenProtocol.java" \
  "$repo_root/android/app/src/test/java/com/cmwen/lenovo_graphics_pad/PenProtocolTest.java"
java -cp "$tmp_dir" com.cmwen.lenovo_graphics_pad.PenProtocolTest
