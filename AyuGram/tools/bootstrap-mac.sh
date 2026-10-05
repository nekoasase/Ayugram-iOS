#!/bin/bash
# AyuGram iOS — сбор информации о Mac mini и подготовка окружения.
# Запуск на маке:  bash bootstrap-mac.sh
# Скрипт идемпотентный: повторный запуск ничего не ломает.

set -uo pipefail

REPO_URL="${REPO_URL:-https://github.com/Swiftgram/Telegram-iOS.git}"
WORKDIR="${WORKDIR:-$HOME/ayugram-ios}"
BAZEL_CACHE="${BAZEL_CACHE:-$HOME/telegram-bazel-cache}"

hr() { printf '\n========== %s ==========\n' "$1"; }

hr "SYSTEM"
sw_vers 2>/dev/null || echo "sw_vers: FAILED"
printf 'arch: %s\n' "$(uname -m)"
printf 'kernel: %s\n' "$(uname -r)"
printf 'model: %s\n' "$(sysctl -n hw.model 2>/dev/null)"
printf 'cpu: %s cores\n' "$(sysctl -n hw.ncpu 2>/dev/null)"
printf 'ram: %s GB\n' "$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))"

hr "DISK"
df -h / /Users 2>/dev/null | sort -u

hr "XCODE"
if xcode-select -p >/dev/null 2>&1; then
  printf 'developer dir: %s\n' "$(xcode-select -p)"
else
  echo "developer dir: NOT CONFIGURED"
fi
if xcodebuild -version >/dev/null 2>&1; then
  xcodebuild -version
else
  echo "xcodebuild: NOT AVAILABLE (Xcode не установлен)"
fi
if [ -d /Applications/Xcode.app ]; then
  printf 'Xcode.app: %s\n' "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
      /Applications/Xcode.app/Contents/Info.plist 2>/dev/null || echo present)"
else
  echo "Xcode.app: ОТСУТСТВУЕТ в /Applications"
fi

hr "TOOLING"
for tool in git python3 curl openssl brew bazelisk; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '%-9s %s\n' "$tool" "$(command -v "$tool")"
  else
    printf '%-9s MISSING\n' "$tool"
  fi
done
python3 --version 2>&1 | sed 's/^/python3   /'
git --version 2>&1 | sed 's/^/git       /'

hr "SUDO (нужен для xcode-select/установок)"
if sudo -n true 2>/dev/null; then
  echo "passwordless sudo: YES"
else
  echo "passwordless sudo: NO (пароль спросят интерактивно)"
fi

hr "РЕПОЗИТОРИЙ"
if [ -d "$WORKDIR/.git" ]; then
  echo "уже склонирован: $WORKDIR"
  git -C "$WORKDIR" log --oneline -1 2>/dev/null
else
  echo "клонирую $REPO_URL -> $WORKDIR (это долго, ~несколько ГБ с сабмодулями)"
  git clone --recursive -j8 "$REPO_URL" "$WORKDIR" || {
    echo "clone FAILED"; exit 1; }
fi

if [ -d "$WORKDIR/.git" ]; then
  hr "ВЕРСИИ БАЗЫ (versions.json)"
  cat "$WORKDIR/versions.json" 2>/dev/null || echo "versions.json не найден"
  printf '\nbazel cache dir: %s (свободно нужно ~50+ GB)\n' "$BAZEL_CACHE"
fi

hr "ГОТОВО"
cat <<'EOF'
Дальше (когда Xcode установлен):
  1. openssl rand -hex 8                      # organization identifier
  2. отредактировать build-system/template_minimal_development_configuration.json
  3. python3 build-system/Make/Make.py --cacheDir="$HOME/telegram-bazel-cache" \
       generateProject --configurationPath=build-system/template_minimal_development_configuration.json \
       --xcodeManagedCodesigning
EOF
