#!/bin/bash
# Apply the AyuGram patch layer to a clean Swiftgram/Telegram-iOS checkout.
#
#   git clone --recursive -j8 https://github.com/Swiftgram/Telegram-iOS.git
#   AyuGram/patches/apply-patches.sh Telegram-iOS
#
# The patches only touch TelegramCore: they add the AYUGRAM_Ayudeps build
# dependency and the four Ghost Mode hooks. Everything else lives in the
# AyuGram/ module tree, which needs no patching.
#
# Use -R to revert:
#   AyuGram/patches/apply-patches.sh -R Telegram-iOS

set -euo pipefail

REVERSE=""
if [ "${1:-}" = "-R" ]; then
    REVERSE="-R"
    shift
fi

REPO="${1:-.}"
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "$REPO/.git" ]; then
    echo "not a git checkout: $REPO" >&2
    exit 1
fi

shopt -s nullglob
patches=("$HERE"/*.patch)
if [ ${#patches[@]} -eq 0 ]; then
    echo "no patches found in $HERE" >&2
    exit 1
fi

for patch in "${patches[@]}"; do
    echo "applying $(basename "$patch")"
    git -C "$REPO" apply $REVERSE --whitespace=nowarn "$patch"
done

echo "done: ${#patches[@]} patches"
