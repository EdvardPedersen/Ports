#!/bin/bash

adjust() {
  local direction="$1"
  local path max cur new
  path="$(ls /sys/class/backlight/*/brightness 2>/dev/null | head -n1)"
  [ -z "${path}" ] && exit 1
  max="$(cat "$(dirname "${path}")/max_brightness" 2>/dev/null || echo 255)"
  cur="$(cat "${path}")"
  case "${direction}" in
    up)   new=$(( cur * 2 )); [ "${new}" -gt "${max}" ] && new="${max}" ;;
    down) new=$(( cur / 2 )); [ "${new}" -lt 1 ]       && new=1 ;;
  esac
  echo "${new}" > "${path}"
}

case "$1" in
  up|down) adjust "$1"; exit 0 ;;
esac

SELF="$(readlink -f "$0")"
swaynag \
  --message "Adjust brightness" \
  --button "Brighter" "${SELF} up" \
  --button "Dimmer"   "${SELF} down" \
  --font "monospace 70"
