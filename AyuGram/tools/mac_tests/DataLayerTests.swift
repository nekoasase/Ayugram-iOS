// Executable data-layer test harness, run on the Mac mini.
//
// Why this exists: the schema was recovered from the APK and verified by Python
// scripts, but those scripts verify SQL and a *model* of the records — not the
// Swift that ships. This harness runs the real Swift data layer against a real
// SQLite engine, which is the only way to prove the generated mappings, the
// store's queries and the Android importer actually work.
//
// It runs on macOS 10.15 even though the app cannot be built there, because the
// Command Line Tools ship swiftc and the system SQLite3 module exists. The build
// script compiles a stub module named `sqlcipher` that re-exports the real
// SQLite3, so `import sqlcipher` resolves to genuine sqlite3 symbols rather than
// hand-written fakes — no false results either way.

import Foundation

var failures: [String] = []

func expect(_ label: String, _ condition: Bool, _ detail: String = "") {
    if condition {
        print("  ok   \(label)")
    } else {
        print("  FAIL \(label)\(detail.isEmpty ? "" : ": " + detail)")
        failures.append(label)
    }
}

func expectEqual<T: Equatable>(_ label: String, _ actual: T, _ expected: T) {
    expect(label, actual == expected, "expected \(expected), got \(actual)")
}

let accountId: Int64 = 777000

func columnNames(_ sqlite: AyuSqlite, _ table: String) -> [String] {
    let rows = (try? sqlite.query("PRAGMA table_info(`\(table)`)")) ?? []
    return rows.compactMap { $0["name"]?.stringValue }
}

func tableNames(_ sqlite: AyuSqlite) -> [String] {
    let rows = (try? sqlite.query("SELECT name FROM sqlite_master WHERE type = 'table'")) ?? []
    return rows.compactMap { $0["name"]?.stringValue }.sorted()
}

/// Columns the Android importer adds, keyed by table, taken from the importer's
/// own declarations so the fixture cannot drift away from it.
func columnsAddedByImporter() -> [String: Set<String>] {
    var result: [String: Set<String>] = [:]
    for addition in AyuAndroidImporter.preRebuildAdditions {
        result[addition.table, default: []].insert(addition.column)
    }
    for addition in AyuAndroidImporter.postRebuildAdditions {
        result[addition.table, default: []].insert(addition.column)
    }
    return result
}

/// Recreates `table` in its pre-migration shape: exactly the current columns minus
/// the ones the importer adds.
///
/// Deriving the legacy shape from the live schema is what makes this fixture
/// trustworthy — hand-written old DDL would silently stop matching reality as soon
/// as a column is added.
func rewindTableToLegacyShape(_ sqlite: AyuSqlite, _ table: String) throws {
    let added = columnsAddedByImporter()[table] ?? []
    let info = try sqlite.query("PRAGMA table_info(`\(table)`)")

    var definitions: [String] = []
    for row in info {
        guard let name = row["name"]?.stringValue, !added.contains(name) else {
            continue
        }
        let type = row["type"]?.stringValue ?? "TEXT"
        let isPrimaryKey = (row["pk"]?.int64Value ?? 0) != 0
        let isNotNull = (row["notnull"]?.int64Value ?? 0) != 0

        var definition = "`\(name)` \(type)"
        if isPrimaryKey {
            // Our archive's primary keys are INTEGER rowids.
            definition += type.uppercased() == "INTEGER" ? " PRIMARY KEY AUTOINCREMENT" : " PRIMARY KEY"
        } else if isNotNull {
            definition += " NOT NULL"
        }
        definitions.append(definition)
    }

    try sqlite.execute("DROP TABLE `\(table)`")
    try sqlite.execute("CREATE TABLE `\(table)` (\(definitions.joined(separator: ", ")))")
}

/// Inserts a row into a legacy table, filling every NOT NULL column.
///
/// A real Android archive row has values everywhere; a fixture that only supplies
/// the interesting columns would be rejected by the NOT NULL constraints — which
/// is exactly how the wrapper's swallowed-error bug was noticed in the first place.
func insertLegacyRow(_ sqlite: AyuSqlite, _ table: String, values: [String: AyuSqliteValue]) throws {
    let info = try sqlite.query("PRAGMA table_info(`\(table)`)")

    var columns: [String] = []
    var bindings: [AyuSqliteValue] = []

    for row in info {
        guard let name = row["name"]?.stringValue else { continue }
        let isPrimaryKey = (row["pk"]?.int64Value ?? 0) != 0
        if isPrimaryKey {
            continue  // let SQLite assign the rowid
        }
        if let provided = values[name] {
            columns.append(name)
            bindings.append(provided)
        } else if (row["notnull"]?.int64Value ?? 0) != 0 {
            let type = (row["type"]?.stringValue ?? "TEXT").uppercased()
            columns.append(name)
            if type.contains("INT") {
                bindings.append(.integer(0))
            } else if type.contains("BLOB") {
                bindings.append(.blob(Data()))
            } else {
                bindings.append(.text(""))
            }
        }
    }

    let list = columns.map { "`\($0)`" }.joined(separator: ", ")
    let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ", ")
    try sqlite.run("INSERT INTO `\(table)` (\(list)) VALUES (\(placeholders))", bindings)
}

// MARK: - 1. Fresh install

print("fresh install")

let fresh = AyuDatabase(inMemory: true)
let freshSqlite = fresh.sqlite

expectEqual("schema version stamped as 32 (Android's final Room version)",
            fresh.userVersion, Int32(32))

let expectedTables = [
    "DeletedDialog", "DeletedMessage", "DeletedMessageReaction", "EditedMessage",
    "RegexFilter", "RegexFilterGlobalExclusion", "SpyMessageContentsRead", "SpyMessageRead",
]
let actualTables = tableNames(freshSqlite).filter { !$0.hasPrefix("sqlite_") }
expectEqual("all eight archive tables exist", actualTables, expectedTables)

let indexes = (try? freshSqlite.query("SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'index_%'")) ?? []
expectEqual("ten indexes exist", indexes.count, 10)

expectEqual("DeletedMessage has 36 columns (35 from Android + messageSerialized)",
            columnNames(freshSqlite, "DeletedMessage").count, 36)
expectEqual("EditedMessage has 36 columns", columnNames(freshSqlite, "EditedMessage").count, 36)

// The schema is created inside a transaction; running it twice must be a no-op
// rather than an error, because migrate() is called on every launch.
do {
    try freshSqlite.transaction { connection in
        for statement in AyuSchema.createStatements {
            try connection.execute(statement)
        }
    }
    expect("re-running the schema is idempotent", true)
} catch {
    expect("re-running the schema is idempotent", false, "\(error)")
}

// MARK: - 2. Records round-trip

print("record round-trip")

let store = AyuArchiveStore(database: fresh)

let dialogId: Int64 = -1001234567890
let snapshot = DeletedMessage(
    userId: accountId,
    dialogId: dialogId,
    peerId: dialogId,
    fromId: 424242,
    topicId: 9,
    messageId: 4242,
    date: 1_700_000_000,
    flags: 259,
    fwdFlags: 1,
    fwdFromId: 555,
    fwdName: "channel name",
    fwdDate: 1_699_000_000,
    entityCreateDate: 1_700_000_111,
    text: "секретное сообщение",
    messageSerialized: Data([0x01, 0x02, 0x03])
)

do {
    let rowId = try store.insert(snapshot)
    expect("insert returns a rowid", rowId > 0, "rowid=\(rowId)")

    let fetched = try store.deletedMessages(accountId: accountId, dialogId: dialogId)
    expectEqual("one snapshot is returned", fetched.count, 1)

    if let first = fetched.first {
        expectEqual("text survives the round-trip", first.text ?? "", "секретное сообщение")
        expectEqual("negative channel dialogId survives", first.dialogId, dialogId)
        expectEqual("Int32 field survives", first.messageId, 4242)
        expectEqual("Int32 flags survive", first.flags, 259)
        expectEqual("Int64 fwdFromId survives", first.fwdFromId, 555)
        expectEqual("optional string survives", first.fwdName ?? "", "channel name")
        expectEqual("topicId survives", first.topicId, 9)
        expectEqual("BLOB payload survives", first.messageSerialized ?? Data(), Data([0x01, 0x02, 0x03]))
        expect("fakeId is assigned by SQLite", first.fakeId != nil)

        // --- reactions attached to that snapshot ---
        let messageRowId = first.fakeId ?? 0
        try store.insert(DeletedMessageReaction(
            deletedMessageId: messageRowId,
            emoticon: "🔥",
            documentId: 0,
            isCustom: false,
            count: 3,
            selfSelected: true
        ))

        let grouped = try store.reactions(forDeletedMessageIds: [messageRowId])
        expectEqual("reactions are grouped by snapshot", grouped[messageRowId]?.count ?? 0, 1)
        expectEqual("emoji survives", grouped[messageRowId]?.first?.emoticon ?? "", "🔥")
        expectEqual("Bool selfSelected survives", grouped[messageRowId]?.first?.selfSelected ?? false, true)

        let full = try store.deletedMessagesFull(accountId: accountId, dialogId: dialogId)
        expectEqual("DeletedMessageFull carries the snapshot", full.count, 1)
        expectEqual("DeletedMessageFull carries the reactions", full.first?.reactions.count ?? 0, 1)
    }
} catch {
    expect("deleted message round-trip", false, "\(error)")
}

// A cheap way to get the row ids we need for the edited-message section.
let archivedIds = (try? store.deletedMessages(accountId: accountId, dialogId: dialogId)) ?? []

do {
    let ids = try store.archivedMessageIds(
        accountId: accountId, dialogId: dialogId, messageIds: [4242, 9999]
    )
    expect("archivedMessageIds finds the archived one", ids.contains(4242))
    expect("archivedMessageIds excludes the absent one", !ids.contains(9999))
    expectEqual("count is reported", try store.deletedMessageCount(accountId: accountId), 1)
} catch {
    expect("archivedMessageIds", false, "\(error)")
}

// MARK: - 3. Pagination

print("pagination")

do {
    for id in Int32(1)...Int32(5) {
        try store.insert(DeletedMessage(
            userId: accountId,
            dialogId: 555,
            peerId: 555,
            messageId: id,
            date: 1_700_000_000 + id,
            entityCreateDate: 1_700_000_000
        ))
    }
    let page = try store.deletedMessages(accountId: accountId, dialogId: 555, limit: 2)
    expectEqual("limit is honoured", page.count, 2)
    expectEqual("newest first", page.first?.messageId ?? 0, 5)

    let older = try store.deletedMessages(
        accountId: accountId, dialogId: 555, limit: 10, beforeMessageId: 3
    )
    expectEqual("beforeMessageId pages backwards", older.map { $0.messageId }, [2, 1])
} catch {
    expect("pagination", false, "\(error)")
}

// MARK: - 4. Edited history

print("edited history")

do {
    for revision in 0 ..< 3 {
        try store.insert(EditedMessage(
            userId: accountId,
            dialogId: dialogId,
            peerId: dialogId,
            messageId: 4242,
            date: 1_700_000_000,
            editDate: 1_700_000_000 + Int32(revision),
            entityCreateDate: 1_700_000_500 + Int64(revision),
            text: "revision \(revision)"
        ))
    }
    let history = try store.editedHistory(accountId: accountId, dialogId: dialogId, messageId: 4242)
    expectEqual("all revisions are returned", history.count, 3)
    expectEqual("oldest revision first", history.first?.text ?? "", "revision 0")
    expectEqual("newest revision last", history.last?.text ?? "", "revision 2")

    let editedIds = try store.editedMessageIds(
        accountId: accountId, dialogId: dialogId, messageIds: [4242, 1]
    )
    expect("editedMessageIds finds the edited one", editedIds.contains(4242))
    expect("editedMessageIds excludes the untouched one", !editedIds.contains(1))
} catch {
    expect("edited history", false, "\(error)")
}

// MARK: - 5. Spy

print("spy")

do {
    let first = try store.recordRead(dialogId: dialogId, messageId: 11, readerId: 1001, date: 1)
    let duplicate = try store.recordRead(dialogId: dialogId, messageId: 11, readerId: 1001, date: 2)
    let second = try store.recordRead(dialogId: dialogId, messageId: 11, readerId: 1002, date: 3)

    expect("first read is recorded", first)
    expect("the same reader is not recorded twice", !duplicate)
    expect("a different reader is recorded", second)

    let readers = try store.readersOfMessage(dialogId: dialogId, messageId: 11)
    expectEqual("both readers are listed", readers.count, 2)
    expectEqual("userId holds the reader, not the account", readers.first?.userId ?? 0, 1001)

    try store.insert(SpyMessageContentsRead(
        userId: 2002, dialogId: dialogId, messageId: 11, entityCreateDate: 4
    ))
    let contentReaders = try store.contentReaderIds(dialogId: dialogId, messageId: 11)
    expectEqual("content readers are separate from read marks", contentReaders, [2002])
} catch {
    expect("spy", false, "\(error)")
}

// MARK: - 6. Regex filters

print("regex filters")

do {
    let global = RegexFilter.make(text: "спам", caseInsensitive: true)
    let scoped = RegexFilter.make(text: "реклама", reversed: true, dialogId: dialogId)
    try store.saveFilter(global)
    try store.saveFilter(scoped)

    let all = try store.allFilters()
    expectEqual("both filters are stored", all.count, 2)
    expect("reversed flag survives", all.contains { $0.reversed })
    expect("filter ids are 16-byte BLOBs", all.allSatisfy { $0.id.count == 16 })

    // Saving the same id must update rather than duplicate (UPSERT on the BLOB PK).
    var edited = global
    edited.text = "спам и реклама"
    edited.enabled = false
    try store.saveFilter(edited)
    let afterUpsert = try store.allFilters()
    expectEqual("UPSERT does not duplicate rows", afterUpsert.count, 2)
    expect("UPSERT updated the text",
           afterUpsert.contains { $0.text == "спам и реклама" && !$0.enabled })

    // Global filters apply everywhere; a disabled one must not.
    let applicableHere = try store.applicableFilters(dialogId: dialogId)
    expect("the scoped filter applies to its dialog",
           applicableHere.contains { $0.text == "реклама" })
    expect("the disabled global filter does not apply",
           !applicableHere.contains { $0.text == "спам и реклама" })

    let applicableElsewhere = try store.applicableFilters(dialogId: -42)
    expect("the scoped filter does not leak into other dialogs",
           !applicableElsewhere.contains { $0.text == "реклама" })

    // Re-enable it and exclude it for this dialog only.
    try store.setFilterEnabled(id: global.id, enabled: true)
    let exclusionId = try store.excludeFilter(id: global.id, from: dialogId)
    expect("exclusion row is inserted", exclusionId > 0)

    let withExclusion = try store.applicableFilters(dialogId: dialogId)
    expect("an excluded global filter no longer applies to that dialog",
           !withExclusion.contains { $0.text == "спам и реклама" })

    let stillGlobal = try store.applicableFilters(dialogId: -42)
    expect("the same global filter still applies elsewhere",
           stillGlobal.contains { $0.text == "спам и реклама" })

    try store.removeExclusion(filterId: global.id, dialogId: dialogId)
    let restored = try store.applicableFilters(dialogId: dialogId)
    expect("removing the exclusion restores the filter",
           restored.contains { $0.text == "спам и реклама" })

    try store.deleteFilter(id: scoped.id)
    expectEqual("deleteFilter removes exactly one row", try store.allFilters().count, 1)
} catch {
    expect("regex filters", false, "\(error)")
}

// MARK: - 7. Transactions

print("transactions")

do {
    let before = try store.deletedMessageCount(accountId: accountId)
    do {
        try freshSqlite.transaction { connection in
            try connection.run(
                "INSERT INTO `DeletedMessage` (`userId`,`dialogId`,`peerId`,`messageId`,`date`,`entityCreateDate`) "
                + "VALUES (?,?,?,?,?,?)",
                [.integer(accountId), .integer(1), .integer(1), .integer(1), .integer(1), .integer(1)]
            )
            throw AyuSqliteError(message: "deliberate failure")
        }
    } catch {
        // expected
    }
    let after = try store.deletedMessageCount(accountId: accountId)
    expectEqual("a failed transaction rolls back", after, before)
} catch {
    expect("transactions", false, "\(error)")
}

// MARK: - 8. Android import path

print("android import")

do {
    let legacy = AyuSqlite(path: ":memory:")!

    // Build the fixture from the current schema, then rewind the four tables the
    // Android importer is responsible for into their pre-migration shape. That
    // keeps the fixture honest (all eight tables exist, as they would in a real
    // exported archive) without hand-copying DDL that would drift.
    for statement in AyuSchema.createStatements {
        try legacy.execute(statement)
    }

    let legacyStatements = [
        "DROP TABLE `RegexFilter`",
        "CREATE TABLE `RegexFilter` (`fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, "
        + "`text` TEXT, `enabled` INTEGER NOT NULL, `caseInsensitive` INTEGER NOT NULL, `dialogId` INTEGER)",
    ]
    for statement in legacyStatements {
        try legacy.execute(statement)
    }

    // The three tables the importer alters by adding columns: rewind them to
    // final-minus-added. RegexFilter is handled above because its primary key
    // changed type, which is a rebuild rather than an addition.
    for table in ["DeletedMessage", "EditedMessage", "DeletedDialog"] {
        try rewindTableToLegacyShape(legacy, table)
    }
    expect("the legacy DeletedMessage shape is much smaller than the final one",
           columnNames(legacy, "DeletedMessage").count
           < columnNames(freshSqlite, "DeletedMessage").count)

    try insertLegacyRow(legacy, "DeletedMessage", values: [
        "userId": .integer(accountId),
        "dialogId": .integer(dialogId),
        "messageId": .integer(4242),
        "date": .integer(1),
        "entityCreateDate": .integer(2),
        "text": .text("из Android"),
    ])
    try legacy.run("INSERT INTO `RegexFilter` (`text`,`enabled`,`caseInsensitive`,`dialogId`) VALUES (?,?,?,?)",
                   [.text("спам"), .integer(1), .integer(1), .null])
    try legacy.run("INSERT INTO `RegexFilter` (`text`,`enabled`,`caseInsensitive`,`dialogId`) VALUES (?,?,?,?)",
                   [.text("реклама"), .integer(0), .integer(1), .integer(dialogId)])

    expect("legacy RegexFilter starts on an INTEGER primary key",
           columnNames(legacy, "RegexFilter").contains("fakeId"))

    try legacy.transaction { connection in
        try AyuAndroidImporter.upgrade(connection)
    }

    // Compare column *sets*, not lists. An upgraded database legitimately ends up
    // with a different physical order, because `ALTER TABLE ... ADD COLUMN` always
    // appends. Nothing in the data layer may depend on that order, and this is
    // what proves it: rows are read by column name and INSERTs carry an explicit
    // column list, so the two shapes are interchangeable.
    for table in expectedTables {
        expectEqual("\(table): upgraded column set matches a fresh install",
                    Set(columnNames(legacy, table)), Set(columnNames(freshSqlite, table)))
    }

    // The order really is different for the rebuilt tables — otherwise the note
    // above would be describing a situation that never occurs.
    expect("an upgraded table may differ in column order",
           columnNames(legacy, "DeletedDialog") != columnNames(freshSqlite, "DeletedDialog"))

    let migratedText = (try legacy.query(
        "SELECT `text` FROM `DeletedMessage` WHERE `messageId` = 4242"
    )).first?["text"]?.stringValue ?? ""
    expectEqual("deleted message survived the upgrade", migratedText, "из Android")

    let filters = try legacy.query("SELECT `id`, `text`, `reversed` FROM `RegexFilter` ORDER BY `text`")
    expectEqual("both filters survived the rebuild", filters.count, 2)
    expect("the rebuild generated BLOB ids",
           filters.allSatisfy { ($0["id"]?.dataValue?.count ?? 0) == 16 })
    expect("the reversed column was added after the rebuild, not dropped",
           filters.allSatisfy { $0["reversed"]?.int64Value == 0 })

    // A selected NULL arrives as `.null`, not as a missing key.
    let androidRows = try legacy.query("SELECT `messageSerialized` FROM `DeletedMessage`")
    expectEqual("the query returned the imported row", androidRows.count, 1)
    expect("imported rows have a NULL messageSerialized payload",
           androidRows.first?["messageSerialized"]?.isNull ?? false)

    // Running the upgrade again must change nothing.
    try legacy.transaction { connection in
        try AyuAndroidImporter.upgrade(connection)
    }
    expectEqual("a second upgrade is a no-op",
                Set(columnNames(legacy, "DeletedMessage")), Set(columnNames(freshSqlite, "DeletedMessage")))
    expectEqual("and does not duplicate filters",
                (try legacy.query("SELECT COUNT(*) AS c FROM `RegexFilter`")).first?["c"]?.int32Value ?? 0, 2)
} catch {
    expect("android import", false, "\(error)")
}

// MARK: - Summary

_ = archivedIds

print("")
if failures.isEmpty {
    print("ALL TESTS PASSED")
    exit(0)
} else {
    print("\(failures.count) FAILED")
    for failure in failures {
        print("  - \(failure)")
    }
    exit(1)
}
