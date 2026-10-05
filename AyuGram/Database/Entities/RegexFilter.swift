import Foundation
import GRDB

/// A message filter rule.
///
/// Mirrors `com.radolyn.ayugram.database.entities.RegexFilter`, including the
/// migration that changed the primary key: the Android schema originally used an
/// autoincrement `fakeId INTEGER`, and a later version rebuilt the table around a
/// BLOB `id` primary key and added `reversed`. Both facts come from the DDL
/// recovered out of the APK (`docs/raw-schema.sql`).
struct RegexFilter: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "RegexFilter"

    /// Stable 16-byte identifier. Unlike the Android v23 shape this is no longer
    /// a rowid, so a filter keeps its identity across edits.
    var id: Data
    var text: String?
    var enabled: Bool
    /// Invert the match: act on messages that do **not** match `text`.
    var reversed: Bool
    var caseInsensitive: Bool
    /// `nil` means the rule is global; a value scopes it to one dialog.
    var dialogId: Int64?

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case text = "text"
        case enabled = "enabled"
        case reversed = "reversed"
        case caseInsensitive = "caseInsensitive"
        case dialogId = "dialogId"
    }
}

extension RegexFilter {
    /// A fresh, enabled, case-insensitive global filter.
    static func make(text: String, reversed: Bool = false,
                     caseInsensitive: Bool = true, dialogId: Int64? = nil) -> RegexFilter {
        RegexFilter(
            id: RegexFilter.newIdentifier(),
            text: text,
            enabled: true,
            reversed: reversed,
            caseInsensitive: caseInsensitive,
            dialogId: dialogId
        )
    }

    /// 16 random bytes, matching the `randomblob(16)` used when importing an
    /// Android database that still had the old INTEGER primary key.
    static func newIdentifier() -> Data {
        Data((0 ..< 16).map { _ in UInt8.random(in: UInt8.min ... UInt8.max) })
    }
}

/// Ties a global filter to the dialogs it is excluded from.
///
/// Mirrors `com.radolyn.ayugram.database.entities.RegexFilterGlobalExclusion`.
struct RegexFilterGlobalExclusion: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "RegexFilterGlobalExclusion"

    /// `nil` on insert lets SQLite assign the rowid.
    var fakeId: Int64?
    var dialogId: Int64
    var filterId: Data?

    enum CodingKeys: String, CodingKey {
        case fakeId = "fakeId"
        case dialogId = "dialogId"
        case filterId = "filterId"
    }
}

extension RegexFilterGlobalExclusion {
    static let filter = belongsTo(
        RegexFilter.self,
        using: ForeignKey(["filterId"])
    )
}

extension RegexFilter {
    static let globalExclusions = hasMany(
        RegexFilterGlobalExclusion.self,
        using: ForeignKey(["filterId"])
    )

    /// Filters that apply to `dialogId`: filters scoped to that dialog, plus
    /// global filters (`dialogId IS NULL`) that are not excluded for it.
    ///
    /// Written as SQL because the exclusion lives in a second table; GRDB's
    /// `filter(sql:arguments:)` keeps it readable and index-friendly.
    static func applicable(to dialogId: Int64) -> QueryInterfaceRequest<RegexFilter> {
        RegexFilter
            .filter(Column("enabled") == true)
            .filter(sql: """
                `dialogId` = ? OR (
                    `dialogId` IS NULL AND `id` NOT IN (
                        SELECT `filterId` FROM `RegexFilterGlobalExclusion` WHERE `dialogId` = ?
                    )
                )
                """, arguments: [dialogId, dialogId])
    }
}
