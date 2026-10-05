# MARK: AyuGram
#
# Sponsored-message ad blocking.
#
# The decision is pure logic over an explicit configuration value, depending on
# Foundation alone, so the test harness can compile and execute it on the Mac mini.
# The TelegramCore hook that calls it lives in AyuGram/patches/ (AdMessages.swift)
# and drops the entry before it is parsed or cached, so a blocked ad never reaches
# the UI.
#
# Scope note: AyuGram for Android also consumes ABP-style filter lists and rewrites
# in-app web pages through a native library. That surface is deliberately not
# reproduced here; see AyuGram/docs/PORT-MAP.md.

load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "AyuAds",
    module_name = "AyuAds",
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
