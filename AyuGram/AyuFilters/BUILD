# MARK: AyuGram
#
# Regex filter matching.
#
# Mirrors `AyuFilterUtils` and its `HashablePattern` cache from the Android
# original. Foundation only — it does not know about the archive schema, so the
# test harness can compile and execute it on the Mac mini rather than merely parse
# it, and the caller maps a stored `RegexFilter` onto an `AyuFilterRule`.

load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "AyuFilters",
    module_name = "AyuFilters",
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
