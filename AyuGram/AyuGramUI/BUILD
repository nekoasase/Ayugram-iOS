# MARK: AyuGram
#
# Screens that make the ported data layer usable from the app:
# deleted-message archive, read markers, regex filters and archive import.
# Upstream sources stay untouched — the only upstream edits are the settings
# rows and the chat-history hook, kept as patches in AyuGram/patches/.

load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "AyuGramUI",
    module_name = "AyuGramUI",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//AyuGram/AyuFilterBridge:AyuFilterBridge",
        "//AyuGram/AyuSettings:AyuSettings",
        "//AyuGram/Database:AyuDatabase",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Display:Display",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/ItemListPeerActionItem:ItemListPeerActionItem",
        "//submodules/LegacyMediaPickerUI:LegacyMediaPickerUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/AccountContext:AccountContext",
    ],
    visibility = [
        "//visibility:public",
    ],
)
