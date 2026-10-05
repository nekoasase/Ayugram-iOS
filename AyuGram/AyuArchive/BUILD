# MARK: AyuGram
#
# Anti-delete recorder: snapshots messages that are about to be deleted.
#
# Mirrors AyuGram's "Message Saving" (the Android original keeps its own Room
# database, see https://docs.ayugram.one/android/saving/). Fed from the single
# deletion funnel in TelegramCore, `_internal_deleteMessages`.
#
# Depends on Postbox only to read messages inside the transaction that performs
# the deletion; the write itself goes to //AyuGram/Database on a private queue.

load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "AyuArchive",
    module_name = "AyuArchive",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//AyuGram/AyuSettings:AyuSettings",
        "//AyuGram/Database:AyuDatabase",
        "//submodules/Postbox:Postbox",
    ],
    visibility = [
        "//visibility:public",
    ],
)
