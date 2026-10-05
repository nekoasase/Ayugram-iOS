import Foundation

/// A message filter rule.
///
/// Mirrors `com.radolyn.ayugram.database.entities.RegexFilter`, including the
/// migration that changed the primary key: the Android schema originally used an
/// autoincrement `fakeId INTEGER`, and a later version rebuilt the table around a
/// BLOB `id` primary key and added `reversed`. Both facts come from the DDL
/// recovered out of the APK (`docs/raw-schema.sql`).
public struct RegexFilter: AyuTableRecord {
    public static let databaseTableName = "RegexFilter"

    public static var columnNames: [String] { CodingKeys.allCases.map(\.rawValue) }

    /// Stable 16-byte identifier. Unlike the Android v23 shape this is no longer
    /// a rowid, so a filter keeps its identity across edits.
    public var id: Data
    public var text: String?
    public var enabled: Bool
    /// Invert the match: act on messages that do **not** match `text`.
    public var reversed: Bool
    public var caseInsensitive: Bool
    /// `nil` means the rule is global; a value scopes it to one dialog.
    public var dialogId: Int64?

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id = "id"
        case text = "text"
        case enabled = "enabled"
        case reversed = "reversed"
        case caseInsensitive = "caseInsensitive"
        case dialogId = "dialogId"
    }

    public init(
        id: Data,
        text: String? = nil,
        enabled: Bool = true,
        reversed: Bool = false,
        caseInsensitive: Bool = true,
        dialogId: Int64? = nil
    ) {
        self.id = id
        self.text = text
        self.enabled = enabled
        self.reversed = reversed
        self.caseInsensitive = caseInsensitive
        self.dialogId = dialogId
    }
}

extension RegexFilter {
    /// A fresh, enabled, case-insensitive global filter.
    public static func make(
        text: String,
        reversed: Bool = false,
        caseInsensitive: Bool = true,
        dialogId: Int64? = nil
    ) -> RegexFilter {
        return RegexFilter(
            id: newIdentifier(),
            text: text,
            enabled: true,
            reversed: reversed,
            caseInsensitive: caseInsensitive,
            dialogId: dialogId
        )
    }

    /// 16 random bytes, matching the `randomblob(16)` used when importing an
    /// Android database that still had the old INTEGER primary key.
    public static func newIdentifier() -> Data {
        return Data((0 ..< 16).map { _ in UInt8.random(in: UInt8.min ... UInt8.max) })
    }

    /// Filters that apply to `dialogId`: filters scoped to that dialog, plus
    /// global filters (`dialogId IS NULL`) that are not excluded for it.
    ///
    /// The exclusion lives in a second table, hence the subquery. `enabled = 1`
    /// is filtered here so callers cannot forget it.
    public static let applicableQuery = """
        SELECT * FROM `RegexFilter`
        WHERE `enabled` = 1 AND (
            `dialogId` = ? OR (
                `dialogId` IS NULL AND `id` NOT IN (
                    SELECT `filterId` FROM `RegexFilterGlobalExclusion` WHERE `dialogId` = ?
                )
            )
        )
        """
}

/// Ties a global filter to the dialogs it is excluded from.
///
/// Mirrors `com.radolyn.ayugram.database.entities.RegexFilterGlobalExclusion`.
public struct RegexFilterGlobalExclusion: AyuTableRecord {
    public static let databaseTableName = "RegexFilterGlobalExclusion"

    public static var columnNames: [String] { CodingKeys.allCases.map(\.rawValue) }

    /// `nil` on insert lets SQLite assign the rowid.
    public var fakeId: Int64?
    public var dialogId: Int64
    public var filterId: Data?

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case fakeId = "fakeId"
        case dialogId = "dialogId"
        case filterId = "filterId"
    }

    public init(fakeId: Int64? = nil, dialogId: Int64, filterId: Data? = nil) {
        self.fakeId = fakeId
        self.dialogId = dialogId
        self.filterId = filterId
    }
}
