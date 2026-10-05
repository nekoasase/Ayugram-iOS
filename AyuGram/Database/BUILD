# MARK: AyuGram
#
# Storage and data model of the AyuGram patch layer.
#
# Mirrors `com.radolyn.ayugram.database.*` from the Android original: the schema
# was extracted verbatim from the APK (`Schema/schema.sql`) and is verified by
# `tools/verify_schema.py`, `tools/verify_importer.py` and `tools/verify_models.py`.
#
# Storage is the same `sqlcipher` the rest of the tree links (Postbox uses it),
# so the archive needs no third-party dependency. GRDB is deliberately not used:
# it is not vendored here, and Postbox's store is key-value based, which cannot
# express the relational schema recovered from the APK.

load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "AyuDatabase",
    module_name = "AyuDatabase",
    srcs = glob([
        "**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/sqlcipher:sqlcipher",
    ],
    visibility = [
        "//visibility:public",
    ],
)
