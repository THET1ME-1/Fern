#!/usr/bin/env bash
# Сборка для RuStore: один универсальный APK.
#
# Отличия от других каналов:
#   * flavor «rustore» — из манифеста вырезано REQUEST_INSTALL_PACKAGES;
#   * STORE=rustore    — свой апдейтер выключен, обновляет магазин;
#   * подпись НАША (fern-release.jks), а не магазина: RuStore принимает APK как
#     есть и не переподписывает, поэтому версии из магазина и с GitHub встают
#     друг поверх друга.
#
# Почему APK, а не AAB: бандл RuStore переподписал бы своим ключом, и переход
# между каналами потребовал бы удаления приложения.
#
# Использование:  ./tool/build_rustore.sh [--skip-checks]
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

echo "▶ Сборка Fern $VERSION ($BUILD) для RuStore…"
# Только ARM: x86_64 стоил 52 МБ ради устройств, которых у людей нет. Флаг
# убирает библиотеки самого Flutter, нативные части плагинов выбрасывает
# androidComponents в build.gradle.kts. Нужны оба.
flutter build apk --release --flavor rustore \
  --dart-define=STORE=rustore \
  --target-platform android-arm,android-arm64

SRC=build/app/outputs/flutter-apk/app-rustore-release.apk
DIST=dist
mkdir -p "$DIST"
DST="$DIST/Fern-$VERSION-rustore.apk"
cp "$SRC" "$DST"

echo "▶ Проверка: в магазинной сборке не должно быть REQUEST_INSTALL_PACKAGES"
if unzip -p "$DST" AndroidManifest.xml | strings | grep -q 'REQUEST_INSTALL_PACKAGES'; then
  echo "  ✖ Разрешение на месте — проверь flavor."
  exit 1
fi
echo "  ✓ чисто"

# Подпись важнее самой сборки: APK с чужим ключом не встанет поверх
# установленного, а человек увидит только «установка не удалась».
FINGERPRINT=516efd44e8af672ba7a9b101090db54698f5bb42e109c1b00ad4aaa52a2ce3a1
APKSIGNER=$(ls "${ANDROID_HOME:-$HOME/Android/Sdk}"/build-tools/*/apksigner 2>/dev/null | tail -1 || true)
if [[ -n "$APKSIGNER" ]]; then
  echo "▶ Проверка подписи…"
  FP=$("$APKSIGNER" verify --print-certs "$DST" | grep -m1 'SHA-256 digest' | awk '{print $NF}')
  if [[ "$FP" != "$FINGERPRINT" ]]; then
    echo "  ✖ APK подписан НЕ тем ключом ($FP). Обновление поверх установленного не встанет."
    exit 1
  fi
  echo "  ✓ ключ тот же, что у GitHub-сборки"
else
  echo "⚠ apksigner не найден, подпись не проверена"
fi

SIZE=$(du -h "$DST" | cut -f1)
echo "✅ Готово: app/$DST ($SIZE)"
echo
echo "Дальше в RuStore Консоли:"
echo "  1) versionCode должен расти с каждой загрузкой (сейчас $BUILD)"
echo "  2) публикация после модерации — вручную (загрузка идёт с publishType=MANUAL)"
