# MARK: AyuGram
#
# Package marker for the AyuGram patch layer.
#
# The iOS port of AyuGram lives beside `Swiftgram/` rather than inside it, so
# that upstream merges of Swiftgram stay clean and every AyuGram change is
# visible in one directory tree. All patch markers use `# MARK: AyuGram` in
# Bazel files and `// MARK: AyuGram` in Swift, mirroring the existing
# `# MARK: Swiftgram` convention.
#
# Modules:
#   //AyuGram/Database:AyuDatabase    - schema, records, migrations, Android importer
#   //AyuGram/AyuSettings:AyuSettings - feature flags, including Ghost Mode policy
#   //AyuGram/AyuArchive:AyuArchive   - anti-delete and edited-history recorder
#   //AyuGram/AyuFilters:AyuFilters   - regex filter matching
#
# The schema was recovered from vanilla-ayuGram-universal-20250101.apk; see
# AyuGram/docs/PORT-MAP.md for the feature map and the source-verified hook
# points into TelegramCore, and AyuGram/patches/ for the upstream edits.
