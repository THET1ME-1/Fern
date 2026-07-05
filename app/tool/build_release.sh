#!/usr/bin/env bash
# Сборка релиза Fern: сплит-APK по ABI + понятные имена «Fern-<версия>-<abi>.apk»
# (а не безликие app-arm64-v8a-release.apk). Готовые файлы кладутся в app/dist/.
#
# Использование:  ./tool/build_release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# Версия из pubspec (строка вида "version: 1.6.0+8" → берём 1.6.0).
VERSION=$(grep -m1 '^version:' pubspec.yaml | sed -E 's/version:[[:space:]]*([0-9.]+).*/\1/')
echo "▶ Сборка Fern $VERSION (split-per-abi)…"

flutter build apk --release --split-per-abi

OUT=build/app/outputs/flutter-apk
DIST=dist
mkdir -p "$DIST"
rm -f "$DIST"/Fern-*.apk

for abi in arm64-v8a armeabi-v7a x86_64; do
  src="$OUT/app-$abi-release.apk"
  dst="$DIST/Fern-$VERSION-$abi.apk"
  cp "$src" "$dst"
  echo "  ✓ $dst"
done

echo "✅ Готово: app/$DIST/Fern-$VERSION-*.apk"
