#!/bin/sh
# Builds Gigs.app and installs it into /Applications.
set -e
cd "$(dirname "$0")"

./package.sh
pkill -x Gigs || true
# Older installs opened at login through a launch agent; the app registers itself now.
launchctl bootout "gui/$(id -u)/local.gigs" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/local.gigs.plist"
rm -rf /Applications/Gigs.app
cp -R .build/Gigs.app /Applications/
open /Applications/Gigs.app
