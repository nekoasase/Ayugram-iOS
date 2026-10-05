load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

sgdeps = [
    "//Swiftgram/SGGTranslate:SGGTranslate",
    "//Swiftgram/SGSimpleSettings:SGSimpleSettings",
    "//Swiftgram/SGTranslationLangFix:SGTranslationLangFix",
    "//Swiftgram/SGWebSettingsScheme:SGWebSettingsScheme",
    "//Swiftgram/SGGHSettingsScheme:SGGHSettingsScheme",
    "//Swiftgram/SGConfig:SGConfig",
    "//Swiftgram/SGLogging:SGLogging",
]

# MARK: AyuGram
# The AyuGram patch layer hooks Ghost Mode into this module, the same way the
# Swiftgram markers above hook their own settings in.
ayudeps = [
    "//AyuGram/AyuAds:AyuAds",
    "//AyuGram/AyuArchive:AyuArchive",
    "//AyuGram/AyuSettings:AyuSettings",
]

sgsrc = [
    "//Swiftgram/SGIQTP:SGIQTP",
]

swift_library(
    name = "TelegramCore",
    module_name = "TelegramCore",
    srcs = sgsrc + glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = sgdeps + ayudeps + [
        "//submodules/TelegramApi:TelegramApi",
        "//submodules/MtProtoKit:MtProtoKit",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/CloudData:CloudData",
        "//submodules/EncryptionProvider:EncryptionProvider",
        "//submodules/CryptoUtils:CryptoUtils",
        "//submodules/NetworkLogging:NetworkLogging",
        "//submodules/Reachability:Reachability",
        "//submodules/ManagedFile:ManagedFile",
        "//submodules/Utils/RangeSet:RangeSet",
        "//submodules/Utils/DarwinDirStat",
        "//submodules/Emoji",
        "//submodules/TelegramCore/FlatBuffers",
        "//submodules/TelegramCore/FlatSerialization",
        "//submodules/MurMurHash32"
    ],
    visibility = [
        "//visibility:public",
    ],
)
