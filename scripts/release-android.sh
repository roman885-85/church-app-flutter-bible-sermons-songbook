#!/bin/sh
# Випуск оновлення застосунку для Android на GitHub.
#
#   1. Підніміть version у pubspec.yaml (наприклад 1.0.15+10015 → 1.0.16+10016).
#   2. sh scripts/release-android.sh "Що нового — кілька рядків для людей"
#      (або: sh scripts/release-android.sh -F notes.md)
#
# Скрипт збирає APK, перевіряє, що він підписаний справжнім ключем (а не debug), і
# створює на GitHub випуск `vX.Y.Z` з файлом `vidrodzhennia-X.Y.Z.apk`. Застосунки на
# телефонах питають GitHub (`releases/latest`) і самі пропонують оновитися.
# Опис випуску пишіть розгорнуто: що нового, що виправлено, що перевірено.
#
# Змінні: RELEASE_REPO (типово — репозиторій цієї теки), CHURCH_APP_KEY_DIR (тека з ключем
# підпису), DRAFT=1 (створити чернетку замість публічного випуску), SITE_URL (адреса
# сайту церкви: після випуску йому надсилається «перепитай GitHub» — він одразу покаже
# новий файл; без змінної крок пропускається).
set -eu
cd "$(dirname "$0")/.."

REPO="${RELEASE_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)}"
[ -n "$REPO" ] || { echo "Не вдалося визначити репозиторій: задайте RELEASE_REPO=власник/назва." >&2; exit 1; }
KEY_DIR="${CHURCH_APP_KEY_DIR:-$HOME/.church-app-key}"
KEY_PROPERTIES="${VIDRODZHENNIA_KEY_PROPERTIES:-$KEY_DIR/key.properties}"
[ -z "${ANDROID_HOME:-}" ] && ANDROID_HOME="${ANDROID_SDK_ROOT:-}"
if [ -z "$ANDROID_HOME" ]; then
  for d in "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do [ -d "$d" ] && ANDROID_HOME="$d" && break; done
fi
export ANDROID_HOME
[ -n "${JAVA_HOME:-}" ] && PATH="$JAVA_HOME/bin:$PATH"   # apksigner і keytool шукають java тут
export PATH

if [ "${1:-}" = "-F" ]; then
  [ -f "${2:-}" ] || { echo "немає файла з описом: ${2:-}" >&2; exit 1; }
  NOTES=$(cat "$2")
else
  NOTES="${1:-}"
fi
[ -n "$NOTES" ] || { echo "Опишіть, що нового: sh scripts/release-android.sh \"…\"" >&2; exit 1; }

VERSION=$(sed -n 's/^version: \([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' pubspec.yaml)
TAG="v$VERSION"
command -v gh >/dev/null || { echo "потрібен GitHub CLI (gh)" >&2; exit 1; }
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "Випуск $TAG уже є — підніміть version у pubspec.yaml." >&2
  exit 1
fi
LATEST=$(gh release list --repo "$REPO" --limit 100 --json tagName --jq '.[].tagName' | sed -n 's/^v//p' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
if [ -n "$LATEST" ] && [ "$(printf '%s\n%s\n' "$LATEST" "$VERSION" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" != "$VERSION" ]; then
  echo "Версія $VERSION не новіша за вже випущену $LATEST." >&2
  exit 1
fi
[ -f "$KEY_PROPERTIES" ] || { echo "Немає ключа підпису ($KEY_PROPERTIES) — без нього оновлення не встановиться поверх." >&2; exit 1; }

sh scripts/build-android.sh

APK="build/vidrodzhennia-$VERSION.apk"
cp build/app/outputs/flutter-apk/app-release.apk "$APK"

# Той самий ключ, що й у попередніх версій? Порівнюємо відбиток сертифіката.
STORE=$(sed -n 's/^storeFile=//p' "$KEY_PROPERTIES")
PASS=$(sed -n 's/^storePassword=//p' "$KEY_PROPERTIES")
ALIAS=$(sed -n 's/^keyAlias=//p' "$KEY_PROPERTIES")
EXPECTED=$(keytool -list -keystore "$STORE" -storepass "$PASS" -alias "$ALIAS" 2>/dev/null \
  | sed -n 's/.*SHA-256): //p' | tr -d ':' | tr 'A-F' 'a-f')
APKSIGNER=$(ls -d "$ANDROID_HOME"/build-tools/*/apksigner | tail -1)
ACTUAL=$("$APKSIGNER" verify --print-certs "$APK" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')
if [ -z "$EXPECTED" ] || [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "APK підписаний не тим ключем (очікувався $EXPECTED, є $ACTUAL) — випуск не створено." >&2
  exit 1
fi

gh release create "$TAG" "$APK" \
  --repo "$REPO" \
  --target main \
  --title "Застосунок «Відродження» $VERSION" \
  --notes "$NOTES" \
  ${DRAFT:+--draft}

if [ -n "${DRAFT:-}" ]; then
  echo "Створено чернетку $TAG (не публічна). Опублікувати: gh release edit $TAG --repo $REPO --draft=false --latest"
  exit 0
fi

# Сайт церкви одразу перепитує GitHub і показує новий випуск (він сам пересилає людей на цей файл).
if [ -n "${SITE_URL:-}" ]; then
  if curl -fsS -m 60 -X POST -A "app-release" "$SITE_URL/api/releases/refresh" >/dev/null; then
    echo "Готово: $TAG. Сайт уже знає про випуск — телефони побачать оновлення при наступній перевірці."
  else
    echo "Готово: $TAG. Сайт не відповів — він побачить випуск сам протягом ~10 хвилин."
  fi
else
  echo "Готово: $TAG. Телефони побачать оновлення при наступному запуску застосунку."
fi
