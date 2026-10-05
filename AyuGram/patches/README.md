# AyuGram patch set

The port is split in two on purpose:

* **`AyuGram/` module tree** — the patch layer itself: archive database, settings,
  feature logic. A normal Bazel package; upstream files are untouched.
* **this patch set** — the only edits made to upstream `submodules/` sources: the
  build dependency plus the Ghost Mode hooks into `TelegramCore`.

Keeping the upstream edits as patches means a Swiftgram update can be merged and
the patch set re-applied, and the complete diff of the fork stays reviewable in
one place.

## Applying

```bash
git clone --recursive -j8 https://github.com/Swiftgram/Telegram-iOS.git
cd Telegram-iOS
git apply --whitespace=nowarn ../AyuGram/patches/0001-telegramcore-ayudeps.patch
# ... or all of them at once:
../AyuGram/patches/apply-patches.sh .
```

Revert with `apply-patches.sh -R .`.

## Contents

| Patch | File | What it does |
|---|---|---|
| `0001-telegramcore-ayudeps` | `submodules/TelegramCore/BUILD` | adds the `ayudeps` list and wires it into `deps`, mirroring the existing `sgdeps` convention |
| `0002-ghost-mode-presence` | `.../State/ManagedAccountPresence.swift` | suppresses `account.updateStatus`, so the account never appears online |
| `0003-ghost-mode-read-receipts` | `.../State/SynchronizePeerReadState.swift` | suppresses `messages.readHistory` and `channels.readHistory`; the dialog is still marked read **locally** |
| `0004-ghost-mode-typing` | `.../State/ManagedLocalInputActivities.swift` | suppresses `messages.setTyping` |
| `0005-ghost-mode-stories` | `.../TelegramEngine/Messages/TelegramEngineMessages.swift` | suppresses story views via AyuGram's own switch, independent of Swiftgram's stealth mode |

Every hunk is marked `// MARK: AyuGram` (or `# MARK: AyuGram` in Bazel files),
matching the existing `// MARK: Swiftgram` convention, so `git log -p -S"AyuGram"`
finds the whole port.

## Why these five points

They were located by reading the sources, not guessed — see section 8 of
`docs/PORT-MAP.md`. Verified tool calls:

* presence → `account.updateStatus(offline:)`
* read receipts → `messages.readHistory`, `channels.readHistory`
* typing → `messages.setTyping`
* stories → `markStoryAsSeen` (the same place Swiftgram patched)

## Verification

`tools/verify_patches.py` checks that

* every patch is marked as an AyuGram change,
* every `AyuSettings` flag a patch guards on actually exists in
  `AyuSettings/Sources/AyuSettings.swift`,
* the patch set touches only the five expected files,
* and, when a checkout is available, that each patch is applied
  (`git apply --check --reverse`).
