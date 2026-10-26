#!/bin/bash
# Installs Dynamic Island (Acord edition) from GitHub: builds it on this Mac, puts it in
# Applications and starts it. After that the app keeps itself up to date.
# Needs the Command Line Tools (xcode-select --install) the first time.
set -e
if ! xcode-select -p >/dev/null 2>&1; then
    echo "Installing Apple's Command Line Tools first – run this again when they're done."
    xcode-select --install
    exit 1
fi
mkdir -p "$HOME/Library/Logs"
curl -fsSL "https://raw.githubusercontent.com/rubenleijer/mac-appar/main/DynamicIsland/Scripts/update.sh" -o /tmp/dynamic-island-update.sh
/bin/bash /tmp/dynamic-island-update.sh rubenleijer/mac-appar main 2>&1 | tee -a "$HOME/Library/Logs/Dynamic Island Update.log"
echo
echo "Done – Dynamic Island is in Applications and running. You can close this window."
