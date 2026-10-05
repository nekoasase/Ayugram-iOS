import Foundation

// MARK: - AyuGram settings
//
// Mirrors the settings surface of the Android original: `AyuState` plus the
// preference keys recovered from the APK (`ayu_ghost`, `ayughostconfig`,
// `ayughostexclusionsconfig`, `save_read_marks`, `use_adblock`, …).
//
// Deliberately self-contained — it depends on Foundation only, not on Swiftgram's
// `SGSimpleSettings`. Two reasons:
//
//   * `submodules/TelegramCore/BUILD` already depends on
//     `//Swiftgram/SGSimpleSettings`, so depending on it here would work, but it
//     would also mean that removing or renaming a Swiftgram setting breaks an
//     AyuGram feature. AyuGram flags stay AyuGram flags.
//   * It keeps the patch layer reviewable on its own.
//
// Storage is `UserDefaults.standard`. Unlike Swiftgram's notification settings
// there is nothing here that an app extension (Notification Service, Share)
// needs to read, so the shared app group is not required.

public final class AyuSettings {
    public static let shared = AyuSettings()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.registerDefaults()
    }

    // MARK: - Keys

    public enum Keys: String, CaseIterable {
        // Ghost mode (Android: ayu_ghost, ayughostconfig, ayughostexclusionsconfig)
        case ghostModeEnabled
        case ghostModeStories
        case ghostModeSendOnline
        case ghostModeReadMessages
        case ghostModeTyping
        case ghostModeReadStories
        case ghostModeIndividualChats

        // Message saving (Android: the "Message Saving" preferences section)
        case saveDeletedMessages
        case saveDeletedMessagesInBots
        case saveEditedMessages
        case saveAttachments
        case deletedMessagesMarkStyle
        case editedMessagesMarkStyle

        // Spy (Android: "Spy" section, save_read_marks)
        case saveReadMarks
        case saveContentsRead

        // Filters (Android: "Filters" section, RegexFilter table)
        case regexFiltersEnabled
        case regexFiltersApplyToChatList

        // Ad blocking (Android: use_adblock, enableAdBlock)
        case adBlockEnabled

        // Attachments
        case attachmentsPath
    }

    /// How an archived message is marked in the chat.
    ///
    /// The Android APK contains exactly these five markers
    /// (`DeletedMarkCross`, `DeletedMarkEyeCrossed`, `DeletedMarkTrashBin`,
    /// `DeletedMarkText`, `DeletedMarkNothing`).
    public enum MarkStyle: String, CaseIterable {
        case cross
        case eyeCrossed
        case trashBin
        case text
        case nothing

        public static let defaultValue: MarkStyle = .cross
    }

    private func registerDefaults() {
        // `let`, not `var`: every module in this tree builds with
        // -warnings-as-errors, so a never-mutated `var` would fail the build.
        let values: [String: Any] = [
            Keys.ghostModeEnabled.rawValue: false,
            Keys.ghostModeStories.rawValue: false,
            Keys.ghostModeSendOnline.rawValue: true,
            Keys.ghostModeReadMessages.rawValue: true,
            Keys.ghostModeTyping.rawValue: true,
            Keys.ghostModeReadStories.rawValue: true,
            // dialogId (as string) -> whether ghost mode applies in that chat
            Keys.ghostModeIndividualChats.rawValue: [String: Bool](),

            Keys.saveDeletedMessages.rawValue: true,
            // The Android documentation recommends keeping this off: bots edit and
            // delete messages constantly, which floods the archive.
            Keys.saveDeletedMessagesInBots.rawValue: false,
            Keys.saveEditedMessages.rawValue: true,
            Keys.saveAttachments.rawValue: true,
            Keys.deletedMessagesMarkStyle.rawValue: MarkStyle.defaultValue.rawValue,
            Keys.editedMessagesMarkStyle.rawValue: MarkStyle.text.rawValue,

            Keys.saveReadMarks.rawValue: true,
            Keys.saveContentsRead.rawValue: true,

            Keys.regexFiltersEnabled.rawValue: false,
            Keys.regexFiltersApplyToChatList.rawValue: false,

            Keys.adBlockEnabled.rawValue: false,

            Keys.attachmentsPath.rawValue: "AyuGram/Saved Attachments",
        ]
        self.defaults.register(defaults: values)
    }

    // MARK: - Ghost mode
    //
    // The Android feature is a per-chat override on top of a global switch
    // (`GhostModeGlobalSettings` vs `GhostModeSwitchedToIndividualSettings` in the
    // recovered strings, backed by `ayughostexclusionsconfig`).

    /// Master switch, as in AyuGram's `EnableGhostMode`.
    public var ghostModeEnabled: Bool {
        get { self.defaults.bool(forKey: Keys.ghostModeEnabled.rawValue) }
        set { self.defaults.set(newValue, forKey: Keys.ghostModeEnabled.rawValue) }
    }

    public var ghostModeStories: Bool {
        get { self.defaults.bool(forKey: Keys.ghostModeStories.rawValue) }
        set { self.defaults.set(newValue, forKey: Keys.ghostModeStories.rawValue) }
    }

    public var ghostModeSendOnline: Bool {
        get { self.defaults.bool(forKey: Keys.ghostModeSendOnline.rawValue) }
        set { self.defaults.set(newValue, forKey: Keys.ghostModeSendOnline.rawValue) }
    }

    public var ghostModeReadMessages: Bool {
        get { self.defaults.bool(forKey: Keys.ghostModeReadMessages.rawValue) }
        set { self.defaults.set(newValue, forKey: Keys.ghostModeReadMessages.rawValue) }
    }

    public var ghostModeTyping: Bool {
        get { self.defaults.bool(forKey: Keys.ghostModeTyping.rawValue) }
        set { self.defaults.set(newValue, forKey: Keys.ghostModeTyping.rawValue) }
    }

    /// Per-chat overrides, keyed by `dialogId` as a string.
    ///
    /// A chat present here follows its own value; a chat absent from the map
    /// follows the global switch. This matches AyuGram's individual-vs-global
    /// ghost settings.
    public var ghostModeIndividualChats: [String: Bool] {
        get { self.defaults.dictionary(forKey: Keys.ghostModeIndividualChats.rawValue) as? [String: Bool] ?? [:] }
        set { self.defaults.set(newValue, forKey: Keys.ghostModeIndividualChats.rawValue) }
    }

    /// Whether ghost mode applies right now, ignoring the per-chat dimension.
    ///
    /// Used by the online-presence hook, which has no dialog context.
    public var isGhostModeActive: Bool {
        return self.ghostModeEnabled
    }

    /// Whether ghost mode applies to one chat.
    public func isGhostModeActive(dialogId: Int64) -> Bool {
        guard self.ghostModeEnabled else { return false }
        if let override = self.ghostModeIndividualChats["\(dialogId)"] {
            return override
        }
        return true
    }

    public func setGhostMode(_ enabled: Bool, forDialogId dialogId: Int64) {
        var chats = self.ghostModeIndividualChats
        chats["\(dialogId)"] = enabled
        self.ghostModeIndividualChats = chats
    }

    public func clearGhostModeOverride(forDialogId dialogId: Int64) {
        var chats = self.ghostModeIndividualChats
        chats.removeValue(forKey: "\(dialogId)")
        self.ghostModeIndividualChats = chats
    }

    // MARK: - Message saving

    public var saveDeletedMessages: Bool {
        get { self.defaults.bool(forKey: Keys.saveDeletedMessages.rawValue) }
        set { self.defaults.set(newValue, forKey: Keys.saveDeletedMessages.rawValue) }
    }

    public var saveDeletedMessagesInBots: Bool {
        get { self.defaults.bool(forKey: Keys.saveDeletedMessagesInBots.rawValue) }
        set { self.defaults.set(newValue, forKey: Keys.saveDeletedMessagesInBots.rawValue) }
    }

    public var saveEditedMessages: Bool {
        get { self.defaults.bool(forKey: Keys.saveEditedMessages.rawValue) }
        set { self.defaults.set(newValue, forKey: Keys.saveEditedMessages.rawValue) }
    }

    public var saveAttachments: Bool {
        get { self.defaults.bool(forKey: Keys.saveAttachments.rawValue) }
        set { self.defaults.set(newValue, forKey: Keys.saveAttachments.rawValue) }
    }

    public var attachmentsPath: String {
        get { self.defaults.string(forKey: Keys.attachmentsPath.rawValue) ?? "AyuGram/Saved Attachments" }
        set { self.defaults.set(newValue, forKey: Keys.attachmentsPath.rawValue) }
    }

    public var deletedMessagesMarkStyle: MarkStyle {
        get { MarkStyle(rawValue: self.defaults.string(forKey: Keys.deletedMessagesMarkStyle.rawValue) ?? "") ?? .defaultValue }
        set { self.defaults.set(newValue.rawValue, forKey: Keys.deletedMessagesMarkStyle.rawValue) }
    }

    public var editedMessagesMarkStyle: MarkStyle {
        get { MarkStyle(rawValue: self.defaults.string(forKey: Keys.editedMessagesMarkStyle.rawValue) ?? "") ?? .text }
        set { self.defaults.set(newValue.rawValue, forKey: Keys.editedMessagesMarkStyle.rawValue) }
    }

    // MARK: - Spy

    public var saveReadMarks: Bool {
        get { self.defaults.bool(forKey: Keys.saveReadMarks.rawValue) }
        set { self.defaults.set(newValue, forKey: Keys.saveReadMarks.rawValue) }
    }

    public var saveContentsRead: Bool {
        get { self.defaults.bool(forKey: Keys.saveContentsRead.rawValue) }
        set { self.defaults.set(newValue, forKey: Keys.saveContentsRead.rawValue) }
    }

    // MARK: - Filters

    public var regexFiltersEnabled: Bool {
        get { self.defaults.bool(forKey: Keys.regexFiltersEnabled.rawValue) }
        set { self.defaults.set(newValue, forKey: Keys.regexFiltersEnabled.rawValue) }
    }

    public var regexFiltersApplyToChatList: Bool {
        get { self.defaults.bool(forKey: Keys.regexFiltersApplyToChatList.rawValue) }
        set { self.defaults.set(newValue, forKey: Keys.regexFiltersApplyToChatList.rawValue) }
    }

    // MARK: - Ad blocking

    public var adBlockEnabled: Bool {
        get { self.defaults.bool(forKey: Keys.adBlockEnabled.rawValue) }
        set { self.defaults.set(newValue, forKey: Keys.adBlockEnabled.rawValue) }
    }

    // MARK: - Swiftgram interoperability

    /// Swiftgram already ships a story stealth mode (`storyStealthMode` +
    /// `canUseStealthMode`). AyuGram's own story setting must not fight it: ghost
    /// mode suppresses story views when *either* flag is on.
    public var suppressesStoryViews: Bool {
        return self.ghostModeEnabled && self.ghostModeStories
    }
}
