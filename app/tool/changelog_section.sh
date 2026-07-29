#!/usr/bin/env bash
# Раздел CHANGELOG.md для указанной версии: «## [1.18.1] — 21.07.2026» и всё
# до следующего заголовка. Пустой вывод означает, что раздела нет.
#
# Использование:  ./tool/changelog_section.sh 1.18.1
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?нужна версия, например 1.18.1}"

awk -v v="$VERSION" '
  $0 ~ "^## \\[" v "\\]" { found=1; next }
  found && /^## \[/       { exit }
  found                   { print }
' ../CHANGELOG.md
