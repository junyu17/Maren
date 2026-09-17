#!/bin/bash
set -u
SIM="$1"; OUT="$2"; APP="$3"
ROUTES="calendar perimenopause today trends trackers paywall library search settings"
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")
for loc in en-US es-ES es-MX zh-Hans; do
  case "$loc" in
    en-US) L=en; R=US; Q="Hot flashes";;
    es-ES) L=es; R=ES; Q="Sofocos";;
    es-MX) L=es; R=MX; Q="Sofocos";;
    zh-Hans) L=zh-Hans; R=CN; Q="潮热";;
  esac
  mkdir -p "$OUT/$loc"
  xcrun simctl uninstall "$SIM" "$BUNDLE" >/dev/null 2>&1
  xcrun simctl install "$SIM" "$APP" || exit 1
  n=0
  for r in $ROUTES; do
    n=$((n+1))
    f="$OUT/$loc/$(printf %02d $n)_$r.png"
    [ -f "$f" ] && continue
    xcrun simctl terminate "$SIM" "$BUNDLE" >/dev/null 2>&1
    xcrun simctl launch "$SIM" "$BUNDLE" --seed-screenshots --shot "$r" --shot-query "$Q" -onboarding.done YES \
      -AppleLanguages "($L)" -AppleLocale "${L}_${R}" >/dev/null || exit 1
    sleep 6
    xcrun simctl io "$SIM" screenshot --type=png "$f" >/dev/null 2>&1
    echo "$loc/$r $(python3 -c "from PIL import Image;print(Image.open('$f').size)" 2>/dev/null)"
  done
done
