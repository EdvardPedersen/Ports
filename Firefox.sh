#!/bin/bash
# Firefox - official arm64 Mozilla build as a ROCKNIX PortMaster port.
# Same machinery as the other ports (self-download latest, run against /usr/lib,
# launch into the running sway session). Browser = pointer-driven, so gptokeyb
# runs in mouse mode and wvkbd-mobintl provides a touchscreen keyboard.
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
if [ -d "/opt/system/Tools/PortMaster/" ]; then controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then controlfolder="$XDG_DATA_HOME/PortMaster"
else controlfolder="/roms/ports/PortMaster"; fi
source $controlfolder/control.txt
get_controls
GAMEDIR="/$directory/ports/firefox"
APPDIR="$GAMEDIR/firefox-app"; CONF="$GAMEDIR/conf"
# firefox-latest-ssl always redirects to the current stable aarch64 tarball
FFURL="https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64-aarch64&lang=en-US"
VERFILE="$APPDIR/.version"
mkdir -p "$GAMEDIR" "$APPDIR" "$CONF"
cd "$GAMEDIR"
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1
echo "Firefox starting $(date)"

# --- on-screen notes via swaynag (sway message bar); no-ops if unavailable ---
NAGPID=""
nag_show(){ command -v swaynag >/dev/null 2>&1 || return 0; swaynag -m "$1" -t warning >/dev/null 2>&1 & NAGPID=$!; }
nag_hide(){ [ -n "$NAGPID" ] && kill "$NAGPID" 2>/dev/null; NAGPID=""; }
nag_error(){ command -v swaynag >/dev/null 2>&1 && swaynag -m "$1" -t error -b "OK" "true" >/dev/null 2>&1 & }

resolve_latest(){   # echo latest version (e.g. 152.0.5) from the download redirect (HEAD, no file pull)
  curl -fsS --connect-timeout 4 --max-time 8 -I "$FFURL" 2>/dev/null \
    | tr -d '\r' | grep -i '^location:' \
    | sed -n 's#.*/firefox-\([^/]*\)\.tar\.xz.*#\1#p' | head -1
}

fetch_app(){        # $1 = version label; downloads latest + extracts, swaps in only on success
  local ver="$1" tmp="$GAMEDIR/.app.new" ok=0
  echo "Fetching Firefox ${ver:-latest} ..."
  nag_show "Downloading Firefox ${ver} (~75 MB) — please wait…"
  rm -rf "$tmp"; mkdir -p "$tmp"
  if curl -Lf --retry 3 -o "$GAMEDIR/ff.tar.xz" "$FFURL"; then
    if xzcat "$GAMEDIR/ff.tar.xz" | tar -x -C "$tmp"; then
      rm -rf "$APPDIR"; mv "$tmp" "$APPDIR"; echo "${ver:-installed}" > "$VERFILE"; ok=1
    fi
  fi
  nag_hide
  rm -rf "$tmp" "$GAMEDIR/ff.tar.xz"
  return $((1-ok))
}

find_bin(){ find "$APPDIR" -maxdepth 3 -type f -name firefox 2>/dev/null | head -1; }

FFBIN="$(find_bin)"
installed_ver="$(cat "$VERFILE" 2>/dev/null)"
latest_ver="$(resolve_latest)"
echo "installed=${installed_ver:-none} latest=${latest_ver:-offline}"

if [ -z "$FFBIN" ]; then
  # no cached app: must download
  if ! fetch_app "${latest_ver}"; then
    nag_error "Firefox download failed — check Wi-Fi / network."
    echo "ERROR: no cached app and download failed. Aborting."; exit 1
  fi
elif [ -n "$latest_ver" ] && [ "$latest_ver" != "$installed_ver" ]; then
  # newer release available and we're online: update, keep cache on failure
  fetch_app "$latest_ver" || echo "update failed; keeping installed ${installed_ver:-?}"
else
  echo "using cached Firefox ${installed_ver:-?}"
fi

FFBIN="$(find_bin)"
[ -z "$FFBIN" ] && { echo "ERROR: firefox binary not found under $APPDIR"; exit 1; }
chmod +x "$FFBIN"

# controls: browser is pointer-driven, so gptokeyb runs in mouse/keyboard mode.
# Map written inline to keep this a single-file port.
GPTKFILE="$GAMEDIR/firefox.gptk"
cat > "$GPTKFILE" <<'GPTK'
back = esc
start = enter
guide = \\
a = mouse_left
b = esc
x = space
y = enter
l1 = \\
r1 = \\
l2 = \\
r2 = \\
l3 = \\
r3 = mouse_right
up = up
down = down
left = left
right = right
left_analog_up = mouse_movement_up
left_analog_down = mouse_movement_down
left_analog_left = mouse_movement_left
left_analog_right = mouse_movement_right
right_analog_up = up
right_analog_down = down
right_analog_left = left
right_analog_right = right
deadzone_y = 2100
deadzone_x = 1900
mouse_scale = 512
mouse_delay = 16
GPTK
export TEXTINPUTINTERACTIVE="Y"
$GPTOKEYB "firefox" -c "$GPTKFILE" &
sleep 0.3

# On-screen keyboard: ROCKNIX's system OSK is mis-sized in landscape (its service
# sets -H portrait height but no -L landscape height), so run our own correctly
# sized wvkbd. Stop the system service so the two don't fight; input_sense's
# Function-button + touchscreen-tap still toggles ours (it signals pidof wvkbd).
OSK_STOPPED=0
if command -v wvkbd-mobintl >/dev/null 2>&1; then
  $ESUDO systemctl stop touchkeyboard.service 2>/dev/null && OSK_STOPPED=1
  $ESUDO killall -9 wvkbd-mobintl 2>/dev/null
  wvkbd-mobintl -L 384 -fn 24 --hidden >/dev/null 2>&1 &
fi

cleanup(){
  $ESUDO killall -9 wvkbd-mobintl 2>/dev/null
  [ "$OSK_STOPPED" = 1 ] && $ESUDO systemctl start touchkeyboard.service 2>/dev/null
  $ESUDO killall -9 firefox firefox-bin 2>/dev/null
  $ESUDO kill -9 $(pidof gptokeyb) 2>/dev/null
  [ -n "$NAGPID" ] && kill "$NAGPID" 2>/dev/null
}
trap cleanup EXIT

# keep all profile/config data inside the port dir
export HOME="$CONF"
PROFILE="$CONF/profile"; mkdir -p "$PROFILE"

# Clear any orphaned instance + stale profile lock (same single-instance class
# of issue as the other ports); --no-remote --new-instance forces a fresh one.
$ESUDO killall -9 firefox firefox-bin 2>/dev/null
rm -f "$PROFILE"/lock "$PROFILE"/.parentlock 2>/dev/null

# Wayland (sway/wlroots) rendering + private D-Bus session bus
export MOZ_ENABLE_WAYLAND=1
DBUS_RUN=""
command -v dbus-run-session >/dev/null 2>&1 && DBUS_RUN="dbus-run-session --"

$DBUS_RUN "$FFBIN" --no-remote --new-instance --profile "$PROFILE"
echo "firefox exit code: $?"

# cleanup handled by trap (kills wvkbd/firefox/gptokeyb, restores system OSK)
echo "Firefox exited $(date)"
