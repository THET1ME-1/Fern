#!/usr/bin/env bash
# Сборка для Google Play: AAB (магазин не принимает APK).
#
# Отличия от GitHub-сборки (tool/build_release.sh):
#   * flavor «play» — из манифеста вырезано REQUEST_INSTALL_PACKAGES;
#   * STORE=play    — вместо своего апдейтера работает Play In-App Update.
# Самообновление мимо магазина запрещено политикой Play, поэтому загружать туда
# обычную GitHub-сборку нельзя.
#
# Использование:  ./tool/build_play.sh [--skip-checks]
set -euo pipefail
cd "$(dirname "$0")/.."

SKIP_CHECKS=0
[[ "${1:-}" == "--skip-checks" ]] && SKIP_CHECKS=1

VERSION=$(grep -m1 '^version:' pubspec.yaml | sed -E 's/version:[[:space:]]*([0-9.]+).*/\1/')
BUILD=$(grep -m1 '^version:' pubspec.yaml | sed -E 's/.*\+([0-9]+).*/\1/')

if [[ ! -f android/key.properties || ! -f android/fern-release.jks ]]; then
  echo "✖ Нет релизного ключа: android/key.properties + android/fern-release.jks"
  exit 1
fi

if [[ $SKIP_CHECKS -eq 0 ]]; then
  echo "▶ Проверки…"
  flutter analyze
  flutter test
fi

echo "▶ Сборка Fern $VERSION ($BUILD) для Google Play…"
flutter build appbundle --release --flavor play --dart-define=STORE=play

SRC=build/app/outputs/bundle/playRelease/app-play-release.aab
DIST=dist
mkdir -p "$DIST"
DST="$DIST/Fern-$VERSION-play.aab"
cp "$SRC" "$DST"

echo "▶ Проверка: в Play-сборке не должно быть REQUEST_INSTALL_PACKAGES"
if unzip -p "$DST" base/manifest/AndroidManifest.xml | strings | grep -q 'REQUEST_INSTALL_PACKAGES'; then
  echo "  ✖ Разрешение на месте — Play такую сборку отклонит. Проверь flavor."
  exit 1
fi
echo "  ✓ чисто"

echo "✅ Готово: app/$DST"
echo
echo "Дальше в Play Console:"
echo "  1) versionCode должен расти с каждой загрузкой (сейчас $BUILD)"
echo "  2) первый раз — отдать Google свой ключ подписи (иначе подписи Play и"
echo "     GitHub разойдутся, и версии не встанут друг поверх друга)"
