#!/bin/zsh
# Builds the signed Play Store bundle with the release defines.
# Needs secrets/release.json (copy secrets/release.example.json and fill it in).
set -e
cd "$(dirname "$0")"
if [ ! -f secrets/release.json ] || grep -q REPLACE_WITH secrets/release.json; then
  echo "Missing secrets/release.json with the RevenueCat Google public SDK key." >&2
  echo "Copy secrets/release.example.json to secrets/release.json and fill it in." >&2
  exit 1
fi
flutter build appbundle --release --dart-define-from-file=secrets/release.json
echo "Bundle: build/app/outputs/bundle/release/app-release.aab"
