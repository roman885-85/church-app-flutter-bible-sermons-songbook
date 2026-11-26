#!/bin/sh
# Збірка APK застосунку для Android.
#
#   sh scripts/build-android.sh            → build/app/outputs/flutter-apk/app-release.apk
#   ABIS=android-arm,android-arm64,android-x64 sh scripts/build-android.sh   — ще й для емулятора
#
# Працює на macOS і Linux (на Windows — з Git Bash/WSL або просто командою `flutter build apk`,
# див. docs/ПОВНИЙ-ОПИС.md, розділ «Збірка»).
#
# Типово — лише ARM (32 і 64 біти): так працюють телефони; x86_64 потрібен тільки
# емулятору й додає до файла третину розміру.
#
# Версія береться з pubspec.yaml (version: X.Y.Z+N). Номер збірки N для Android
# має лише зростати, тому рахується з версії: X*10000 + Y*100 + Z.
#
# Потрібні: Flutter (у PATH або FLUTTER_HOME), JDK 17 (JAVA_HOME), Android SDK
# (ANDROID_HOME). Ключ підпису — у теці CHURCH_APP_KEY_DIR (типово ~/.church-app-key),
# див. README. Сторож диска: якщо вільного місця лишається менше 2,5 ГБ, збірка
# зупиняється, щоб не заповнити диск до нуля.
set -eu
cd "$(dirname "$0")/.."

[ -n "${FLUTTER_HOME:-}" ] && PATH="$FLUTTER_HOME/bin:$PATH"
[ -z "${ANDROID_HOME:-}" ] && ANDROID_HOME="${ANDROID_SDK_ROOT:-}"
if [ -z "$ANDROID_HOME" ]; then
  for d in "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do [ -d "$d" ] && ANDROID_HOME="$d" && break; done
fi
export ANDROID_HOME PATH
command -v flutter >/dev/null || { echo "Не знайдено flutter: додайте його в PATH або задайте FLUTTER_HOME." >&2; exit 1; }

VERSION=$(sed -n 's/^version: \([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' pubspec.yaml)
[ -n "$VERSION" ] || { echo "не знайдено version у pubspec.yaml" >&2; exit 1; }
BUILD=$(echo "$VERSION" | awk -F. '{print $1*10000 + $2*100 + $3}')

KEY_DIR="${CHURCH_APP_KEY_DIR:-$HOME/.church-app-key}"
KEY_PROPERTIES="${VIDRODZHENNIA_KEY_PROPERTIES:-$KEY_DIR/key.properties}"
if [ ! -f "$KEY_PROPERTIES" ]; then
  echo "УВАГА: ключ підпису не знайдено ($KEY_PROPERTIES) — APK буде з debug-підписом і не оновиться поверх справжнього." >&2
fi

free_mb() { df -Pm "$PWD" | awk 'NR==2 {print $4}'; }
[ "$(free_mb)" -gt 3000 ] || { echo "На диску менше 3 ГБ вільного місця — збірку не почато." >&2; exit 3; }

# Решта аргументів (наприклад --dart-define=UPDATE_REPO=власник/репозиторій) іде в `flutter build`.
flutter build apk --release --build-name "$VERSION" --build-number "$BUILD" --target-platform "${ABIS:-android-arm,android-arm64}" "$@" &
BUILD_PID=$!
while kill -0 "$BUILD_PID" 2>/dev/null; do
  if [ "$(free_mb)" -lt 2500 ]; then
    echo "Диск майже заповнений — зупиняю збірку." >&2
    kill "$BUILD_PID" 2>/dev/null || true
    (cd android && ./gradlew --stop >/dev/null 2>&1) || true
    exit 4
  fi
  sleep 10
done
wait "$BUILD_PID"

APK=build/app/outputs/flutter-apk/app-release.apk
ls -la "$APK"
echo "версія $VERSION (збірка $BUILD)"
