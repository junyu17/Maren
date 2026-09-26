#!/bin/bash
set -u
SIM="$1"; OUT="$2"; APP="$3"
ROUTES="calendar perimenopause today trends trackers paywall library search settings"
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")

boot_wait() {
  xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1 || { xcrun simctl boot "$SIM" >/dev/null 2>&1; xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1; }
}

for loc in ${LOCALES:-en-US es-ES es-MX zh-Hans ja}; do
  case "$loc" in
    en-US) L=en; R=US; Q="Hot flashes";;
    es-ES) L=es; R=ES; Q="Sofocos";;
    es-MX) L=es; R=MX; Q="Sofocos";;
    zh-Hans) L=zh-Hans; R=CN; Q="潮热";;
    zh-Hant) L=zh-Hant; R=TW; Q="潮熱";;
    ja) L=ja; R=JP; Q="ホットフラッシュ";;
  esac
  mkdir -p "$OUT/$loc"
  # 设备级语言要跟着截图语言走,否则状态栏日期会是英文
  boot_wait
  xcrun simctl spawn "$SIM" defaults write -g AppleLanguages -array "$L" >/dev/null 2>&1
  xcrun simctl spawn "$SIM" defaults write -g AppleLocale -string "${L}_${R}" >/dev/null 2>&1
  xcrun simctl shutdown "$SIM" >/dev/null 2>&1
  boot_wait
  xcrun simctl status_bar "$SIM" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 >/dev/null 2>&1
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
