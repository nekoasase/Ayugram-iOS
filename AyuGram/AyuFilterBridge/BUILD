# MARK: AyuGram
#
# Glue between the archive database and the regex engine.
#
# AyuFilters stays Foundation-only so its test harness can run on the Mac;
# the database-backed lookup lives here instead. Both the settings UI and the
# chat-history hook consume this single class, so the applicable-filter
# semantics are implemented in exactly one place.

load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "AyuFilterBridge",
    module_name = "AyuFilterBridge",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//AyuGram/AyuFilters:AyuFilters",
        "//AyuGram/AyuSettings:AyuSettings",
        "//AyuGram/Database:AyuDatabase",
    ],
    visibility = [
        "//visibility:public",
    ],
)
