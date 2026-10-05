// GENERATED FILE — DO NOT EDIT BY HAND.
// Source: Database/Schema/schema.sql + Database/Entities/*.swift
// Regenerate: python tools/gen_swift_dao.py
//
// Row decoding and SQL binding for every AyuGram archive record. Generated
// because the shared snapshot record has 35 columns and hand-written mappings
// drift silently. The generator fails if the entities and the schema disagree.

import Foundation

// MARK: - AyuMessageRecord (DeletedMessage, EditedMessage)

extension AyuMessageRecord {
    /// Builds a record from one row of `DeletedMessage`.
    public init(row: [String: AyuSqliteValue]) {
        self.fakeId = row["fakeId"]?.int64Value
        self.userId = row["userId"]?.int64Value ?? 0
        self.dialogId = row["dialogId"]?.int64Value ?? 0
        self.groupedId = row["groupedId"]?.int64Value ?? 0
        self.peerId = row["peerId"]?.int64Value ?? 0
        self.fromId = row["fromId"]?.int64Value ?? 0
        self.topicId = row["topicId"]?.int64Value ?? 0
        self.messageId = row["messageId"]?.int32Value ?? 0
        self.date = row["date"]?.int32Value ?? 0
        self.flags = row["flags"]?.int32Value ?? 0
        self.editDate = row["editDate"]?.int32Value ?? 0
        self.views = row["views"]?.int32Value ?? 0
        self.fwdFlags = row["fwdFlags"]?.int32Value ?? 0
        self.fwdFromId = row["fwdFromId"]?.int64Value ?? 0
        self.fwdName = row["fwdName"]?.stringValue
        self.fwdDate = row["fwdDate"]?.int32Value ?? 0
        self.fwdPostAuthor = row["fwdPostAuthor"]?.stringValue
        self.postAuthor = row["postAuthor"]?.stringValue
        self.replyFlags = row["replyFlags"]?.int32Value ?? 0
        self.replyMessageId = row["replyMessageId"]?.int32Value ?? 0
        self.replyPeerId = row["replyPeerId"]?.int64Value ?? 0
        self.replyTopId = row["replyTopId"]?.int32Value ?? 0
        self.replyForumTopic = row["replyForumTopic"]?.boolValue ?? false
        self.replySerialized = row["replySerialized"]?.dataValue
        self.replyMarkupSerialized = row["replyMarkupSerialized"]?.dataValue
        self.entityCreateDate = row["entityCreateDate"]?.int64Value ?? 0
        self.text = row["text"]?.stringValue
        self.textEntities = row["textEntities"]?.dataValue
        self.mediaPath = row["mediaPath"]?.stringValue
        self.hqThumbPath = row["hqThumbPath"]?.stringValue
        self.documentType = row["documentType"]?.int32Value ?? 0
        self.documentSerialized = row["documentSerialized"]?.dataValue
        self.thumbsSerialized = row["thumbsSerialized"]?.dataValue
        self.documentAttributesSerialized = row["documentAttributesSerialized"]?.dataValue
        self.mimeType = row["mimeType"]?.stringValue
    }

    /// Values in `Self.columnNames` order, for INSERT/UPDATE.
    public var sqlValues: [AyuSqliteValue] {
        return [
            self.fakeId.map { .integer($0) } ?? .null,
            .integer(self.userId),
            .integer(self.dialogId),
            .integer(self.groupedId),
            .integer(self.peerId),
            .integer(self.fromId),
            .integer(self.topicId),
            .integer(Int64(self.messageId)),
            .integer(Int64(self.date)),
            .integer(Int64(self.flags)),
            .integer(Int64(self.editDate)),
            .integer(Int64(self.views)),
            .integer(Int64(self.fwdFlags)),
            .integer(self.fwdFromId),
            self.fwdName.map { .text($0) } ?? .null,
            .integer(Int64(self.fwdDate)),
            self.fwdPostAuthor.map { .text($0) } ?? .null,
            self.postAuthor.map { .text($0) } ?? .null,
            .integer(Int64(self.replyFlags)),
            .integer(Int64(self.replyMessageId)),
            .integer(self.replyPeerId),
            .integer(Int64(self.replyTopId)),
            .integer(self.replyForumTopic ? 1 : 0),
            self.replySerialized.map { .blob($0) } ?? .null,
            self.replyMarkupSerialized.map { .blob($0) } ?? .null,
            .integer(self.entityCreateDate),
            self.text.map { .text($0) } ?? .null,
            self.textEntities.map { .blob($0) } ?? .null,
            self.mediaPath.map { .text($0) } ?? .null,
            self.hqThumbPath.map { .text($0) } ?? .null,
            .integer(Int64(self.documentType)),
            self.documentSerialized.map { .blob($0) } ?? .null,
            self.thumbsSerialized.map { .blob($0) } ?? .null,
            self.documentAttributesSerialized.map { .blob($0) } ?? .null,
            self.mimeType.map { .text($0) } ?? .null,
        ]
    }
}

// MARK: - AyuSpyRecord (SpyMessageContentsRead, SpyMessageRead)

extension AyuSpyRecord {
    /// Builds a record from one row of `SpyMessageContentsRead`.
    public init(row: [String: AyuSqliteValue]) {
        self.fakeId = row["fakeId"]?.int64Value
        self.userId = row["userId"]?.int64Value ?? 0
        self.dialogId = row["dialogId"]?.int64Value ?? 0
        self.messageId = row["messageId"]?.int32Value ?? 0
        self.entityCreateDate = row["entityCreateDate"]?.int64Value ?? 0
    }

    /// Values in `Self.columnNames` order, for INSERT/UPDATE.
    public var sqlValues: [AyuSqliteValue] {
        return [
            self.fakeId.map { .integer($0) } ?? .null,
            .integer(self.userId),
            .integer(self.dialogId),
            .integer(Int64(self.messageId)),
            .integer(self.entityCreateDate),
        ]
    }
}

// MARK: - DeletedDialog (DeletedDialog)

extension DeletedDialog {
    /// Builds a record from one row of `DeletedDialog`.
    public init(row: [String: AyuSqliteValue]) {
        self.fakeId = row["fakeId"]?.int64Value
        self.userId = row["userId"]?.int64Value ?? 0
        self.dialogId = row["dialogId"]?.int64Value ?? 0
        self.peerId = row["peerId"]?.int64Value ?? 0
        self.folderId = row["folderId"]?.int32Value
        self.topMessage = row["topMessage"]?.int32Value ?? 0
        self.lastMessageDate = row["lastMessageDate"]?.int32Value ?? 0
        self.flags = row["flags"]?.int32Value ?? 0
        self.entityCreateDate = row["entityCreateDate"]?.int64Value ?? 0
    }

    /// Values in `Self.columnNames` order, for INSERT/UPDATE.
    public var sqlValues: [AyuSqliteValue] {
        return [
            self.fakeId.map { .integer($0) } ?? .null,
            .integer(self.userId),
            .integer(self.dialogId),
            .integer(self.peerId),
            self.folderId.map { .integer(Int64($0)) } ?? .null,
            .integer(Int64(self.topMessage)),
            .integer(Int64(self.lastMessageDate)),
            .integer(Int64(self.flags)),
            .integer(self.entityCreateDate),
        ]
    }
}

// MARK: - DeletedMessageReaction (DeletedMessageReaction)

extension DeletedMessageReaction {
    /// Builds a record from one row of `DeletedMessageReaction`.
    public init(row: [String: AyuSqliteValue]) {
        self.fakeReactionId = row["fakeReactionId"]?.int64Value
        self.deletedMessageId = row["deletedMessageId"]?.int64Value ?? 0
        self.emoticon = row["emoticon"]?.stringValue
        self.documentId = row["documentId"]?.int64Value ?? 0
        self.isCustom = row["isCustom"]?.boolValue ?? false
        self.count = row["count"]?.int32Value ?? 0
        self.selfSelected = row["selfSelected"]?.boolValue ?? false
    }

    /// Values in `Self.columnNames` order, for INSERT/UPDATE.
    public var sqlValues: [AyuSqliteValue] {
        return [
            self.fakeReactionId.map { .integer($0) } ?? .null,
            .integer(self.deletedMessageId),
            self.emoticon.map { .text($0) } ?? .null,
            .integer(self.documentId),
            .integer(self.isCustom ? 1 : 0),
            .integer(Int64(self.count)),
            .integer(self.selfSelected ? 1 : 0),
        ]
    }
}

// MARK: - RegexFilter (RegexFilter)

extension RegexFilter {
    /// Builds a record from one row of `RegexFilter`.
    public init(row: [String: AyuSqliteValue]) {
        self.id = row["id"]?.dataValue ?? Data()
        self.text = row["text"]?.stringValue
        self.enabled = row["enabled"]?.boolValue ?? false
        self.reversed = row["reversed"]?.boolValue ?? false
        self.caseInsensitive = row["caseInsensitive"]?.boolValue ?? false
        self.dialogId = row["dialogId"]?.int64Value
    }

    /// Values in `Self.columnNames` order, for INSERT/UPDATE.
    public var sqlValues: [AyuSqliteValue] {
        return [
            .blob(self.id),
            self.text.map { .text($0) } ?? .null,
            .integer(self.enabled ? 1 : 0),
            .integer(self.reversed ? 1 : 0),
            .integer(self.caseInsensitive ? 1 : 0),
            self.dialogId.map { .integer($0) } ?? .null,
        ]
    }
}

// MARK: - RegexFilterGlobalExclusion (RegexFilterGlobalExclusion)

extension RegexFilterGlobalExclusion {
    /// Builds a record from one row of `RegexFilterGlobalExclusion`.
    public init(row: [String: AyuSqliteValue]) {
        self.fakeId = row["fakeId"]?.int64Value
        self.dialogId = row["dialogId"]?.int64Value ?? 0
        self.filterId = row["filterId"]?.dataValue
    }

    /// Values in `Self.columnNames` order, for INSERT/UPDATE.
    public var sqlValues: [AyuSqliteValue] {
        return [
            self.fakeId.map { .integer($0) } ?? .null,
            .integer(self.dialogId),
            self.filterId.map { .blob($0) } ?? .null,
        ]
    }
}
