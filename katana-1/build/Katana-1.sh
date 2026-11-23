#!/bin/sh
printf '\033c\033]0;%s\a' Katana-1
base_path="$(dirname "$(realpath "$0")")"
"$base_path/Katana-1.x86_64" "$@"
