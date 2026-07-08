#!/bin/bash
# VacuumTube - YouTube (Leanback/TV) for ROCKNIX via PortMaster.
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
if [ -d "/opt/system/Tools/PortMaster/" ]; then controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then controlfolder="$XDG_DATA_HOME/PortMaster"
else controlfolder="/roms/ports/PortMaster"; fi
source $controlfolder/control.txt
get_controls
GAMEDIR="/$directory/ports/vacuumtube"
APPDIR="$GAMEDIR/vacuumtube-app"; CONF="$GAMEDIR/conf"
VTBASE="https://github.com/shy1132/VacuumTube/releases"
VTASSET="VacuumTube-arm64.tar.gz"
VTURL="$VTBASE/latest/download/$VTASSET"
VERFILE="$APPDIR/.version"
mkdir -p "$GAMEDIR" "$APPDIR" "$CONF"
cd "$GAMEDIR"
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1
echo "VacuumTube starting $(date)"

NAGPID=""
nag_show(){
  command -v swaynag >/dev/null 2>&1 || return 0
  swaynag -m "$1" -t warning >/dev/null 2>&1 &
  NAGPID=$!
}
nag_hide(){ [ -n "$NAGPID" ] && kill "$NAGPID" 2>/dev/null; NAGPID=""; }
nag_error(){ 
  command -v swaynag >/dev/null 2>&1 && \
    swaynag -m "$1" -t error -b "OK" "true" >/dev/null 2>&1 &
}

resolve_latest() {
  curl -fsSL --connect-timeout 4 --max-time 8 -o /dev/null -w '%{url_effective}' \
    "$VTBASE/latest" 2>/dev/null | sed -n 's#.*/tag/##p'
}

fetch_app() {
  local tag="$1" tmp="$GAMEDIR/.app.new" ok=0
  echo "Fetching VacuumTube ${tag:-latest}..."
  nag_show "Downloading VacuumTube ${tag} (~120 MB) — please wait…"
  rm -rf "$tmp"; mkdir -p "$tmp"
  if curl -Lf --retry 3 -o "$GAMEDIR/vt.tar.gz" "$VTURL"; then
    if tar -xzf "$GAMEDIR/vt.tar.gz" -C "$tmp"; then
      rm -rf "$APPDIR"; mv "$tmp" "$APPDIR"
      echo "${tag:-installed}" > "$VERFILE"; ok=1
    fi
  fi
  nag_hide
  rm -rf "$tmp" "$GAMEDIR/vt.tar.gz"
  return $((1-ok))
}

VTBIN="$(find "$APPDIR" -maxdepth 3 -type f -name vacuumtube 2>/dev/null | head -1)"
installed_ver="$(cat "$VERFILE" 2>/dev/null)"
latest_ver="$(resolve_latest)"
echo "installed=${installed_ver:-none} latest=${latest_ver:-offline}"

if [ -z "$VTBIN" ]; then
  if ! fetch_app "${latest_ver:-latest}"; then
    nag_error "VacuumTube download failed — check Wi-Fi / network."
    echo "ERROR: no cached app and download failed. Aborting."; exit 1
  fi
elif [ -n "$latest_ver" ] && [ "$latest_ver" != "$installed_ver" ]; then
  fetch_app "$latest_ver" || echo "update failed; keeping installed ${installed_ver:-?}"
else
  echo "using cached VacuumTube ${installed_ver:-?}"
fi

VTBIN="$(find "$APPDIR" -maxdepth 3 -type f -name vacuumtube 2>/dev/null | head -1)"
[ -z "$VTBIN" ] && { echo "ERROR: vacuumtube binary not found under $APPDIR"; exit 1; }
chmod +x "$VTBIN"

$GPTOKEYB "vacuumtube" &
sleep 0.3

export HOME="$CONF"; export XDG_CONFIG_HOME="$CONF/.config"; mkdir -p "$XDG_CONFIG_HOME"

export ELECTRON_OZONE_PLATFORM_HINT=wayland
"$VTBIN" --ozone-platform=wayland --enable-features=UseOzonePlatform \
  --start-fullscreen --no-sandbox --user-data-dir="$CONF/userdata" --force-device-scale-factor=1

$ESUDO kill -9 $(pidof gptokeyb) 2>/dev/null
echo "VacuumTube exited $(date)"
