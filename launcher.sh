#!/bin/bash

# copy the config file if it doesn't exists in user's config dir
if [[ ! -f "$HOME/.config/chillnotch-dynamic/config.jsonc" ]] && [[ -f /usr/share/chillnotch-dynamic/config.jsonc.example ]]; then
   install -Dm644 /usr/share/chillnotch-dynamic/config.jsonc.example "$HOME/.config/chillnotch-dynamic/config.jsonc"
fi

# copy the cava config if it doesn't exists in user's cache dir
if [[ ! -f "$HOME/.cache/chillnotch-dynamic/cava.conf" ]] && [[ -f /usr/share/chillnotch-dynamic/scripts/cava.conf ]]; then
   install -Dm644 /usr/share/chillnotch-dynamic/scripts/cava.conf "$HOME/.cache/chillnotch-dynamic/cava.conf"
fi

export LD_LIBRARY_PATH="$HOME/.config/quickshell/chillnotch-dynamic/IslandBackend:$LD_LIBRARY_PATH"
export QML_IMPORT_PATH="/usr/share/chillnotch-dynamic:$QML_IMPORT_PATH"
exec qs -p /usr/share/chillnotch-dynamic
