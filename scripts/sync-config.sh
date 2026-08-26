#!/usr/bin/env bash
# scripts/sync-config.sh
set -euo pipefail
cd "$(dirname "$0")/.."

sed -e 's|apiKey: "[^"]*"|apiKey: "DEIN_API_KEY"|' \
    -e 's|clientID: "[^"]*"|clientID: "DEINE_SPOTIFY_CLIENT_ID"|' \
    -e 's|clientSecret: "[^"]*"|clientSecret: "DEIN_SPOTIFY_CLIENT_SECRET"|' \
    -e 's|accessToken: "[^"]*"|accessToken: "DEIN_ACCESS_TOKEN"|' \
    -e 's|refreshToken: "[^"]*"|refreshToken: "DEIN_REFRESH_TOKEN"|' \
    -e 's|P:[^;]*;;|P:DEIN_WLAN_PASSWORT;;|' \
    -e 's|url: "https://calendar.google.com[^"]*"|url: "DEINE_GOOGLE_ICAL_URL"|' \
    config/config.js > config/config.js.example

echo "config.js.example aktualisiert. Bitte durchsehen:"
grep -nE 'DEIN|DEINE' config/config.js.example
