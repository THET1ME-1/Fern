#!/usr/bin/env bash
# Сборка релиза Fern: сплит-APK по ABI + понятные имена «Fern-<версия>-<abi>.apk»
# (а не безликие app-arm64-v8a-release.apk). Готовые файлы кладутся в app/dist/.
#
# Перед сборкой прогоняются analyze и тесты: выложить релиз с красным деревом
# дороже, чем подождать минуту.
#
# Использование:  ./tool/build_release.sh [--skip-checks]
set -euo pipefail
cd "$(dirname "$0")/.."

SKIP_CHECKS=0
[[ "${1:-}" == "--skip-checks" ]] && SKIP_CHECKS=1

# Версия из pubspec (строка вида "version: 1.6.0+8" → берём 1.6.0).
VERSION=$(grep -m1 '^version:' pubspec.yaml | sed -E 's/version:[[:space:]]*([0-9.]+).*/\1/')

# Без ключа сборка молча уедет на debug-подпись, а такой APK не встанет поверх
# боевого — останавливаемся сразу.
if [[ ! -f android/key.properties || ! -f android/fern-release.jks ]]; then
  echo "✖ Нет релизного ключа: android/key.properties + android/fern-release.jks"
  echo "  Копия должна лежать в ~/keys/. Без неё релиз собирать нельзя."
  exit 1
fi

if [[ $SKIP_CHECKS -eq 0 ]]; then
  echo "▶ Проверки…"
  flutter analyze
  flutter test
fi

# flavor «github» = со встроенным апдейтером (в Play такая сборка запрещена,
# для магазина есть tool/build_play.sh).
echo "▶ Сборка Fern $VERSION (split-per-abi, канал github)…"
flutter build apk --release --flavor github --split-per-abi

OUT=build/app/outputs/flutter-apk
DIST=dist
mkdir -p "$DIST"
rm -f "$DIST"/Fern-*.apk

for abi in arm64-v8a armeabi-v7a x86_64; do
  src="$OUT/app-$abi-github-release.apk"
  dst="$DIST/Fern-$VERSION-$abi.apk"
  cp "$src" "$dst"
  echo "  ✓ $dst"
done

# Кем подписан APK. «CN=Android Debug» здесь = ключ не тот, релиз выкладывать нельзя.
APKSIGNER=$(ls "$HOME"/Android/Sdk/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1 || true)
if [[ -n "$APKSIGNER" ]]; then
  echo "▶ Подпись:"
  "$APKSIGNER" verify --print-certs "$DIST/Fern-$VERSION-arm64-v8a.apk" \
    | grep -E 'Signer #1 certificate (DN|SHA-256)' || true
fi

echo "▶ SHA-256:"
(cd "$DIST" && sha256sum Fern-"$VERSION"-*.apk)

echo "✅ Готово: app/$DIST/Fern-$VERSION-*.apk"
