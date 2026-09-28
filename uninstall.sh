#!/bin/bash

if [[ ! "$EUID" -eq 0 ]]; then
   echo "Please run this script as root, i need permissions to delete few files in '/'"
   exit 1
fi

if [[ -e /usr/share/chillnotch-dynamic ]]; then
   rm -rf /usr/share/chillnotch-dynamic
fi

if [[ -e /usr/local/bin/chillnotch-dynamic ]]; then
   rm /usr/local/bin/chillnotch-dynamic
fi

if [[ -e /usr/share/applications/chillnotch-dynamic.desktop ]]; then
   rm /usr/share/applications/chillnotch-dynamic.desktop
fi

if [[ -e /etc/systemd/user/chillnotch-dynamic.service ]]; then
   rm /etc/systemd/user/chillnotch-dynamic.service
fi

pkill qs

echo "ChillNotch-Dynamic uninstalled successfully :("
