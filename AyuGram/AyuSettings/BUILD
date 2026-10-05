# MARK: AyuGram
#
# Settings surface of the AyuGram patch layer.
#
# Mirrors `AyuState` and the preference keys recovered from the APK
# (`ayu_ghost`, `ayughostconfig`, `ayughostexclusionsconfig`, `save_read_marks`,
# `use_adblock`, …). Foundation only — it deliberately does not depend on
# `//Swiftgram/SGSimpleSettings`, so a change to a Swiftgram setting cannot break
# an AyuGram feature, and the patch layer stays reviewable on its own.
#
# This is the module TelegramCore hooks import to make Ghost Mode work; see
# `AyuGram/patches/`.

load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "AyuSettings",
    module_name = "AyuSettings",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [],
    visibility = [
        "//visibility:public",
    ],
)
