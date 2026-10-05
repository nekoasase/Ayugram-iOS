// GENERATED FILE — DO NOT EDIT BY HAND.
// Source: AyuGram/Database/Schema/schema.sql
// Regenerate: python tools/gen_swift_schema.py
//
// The statements below are the AyuGram patch-layer schema, extracted from
// vanilla-ayuGram-universal-20250101.apk (Room v32 final state) and verified
// by executing them in SQLite (tools/verify_schema.py).

import Foundation

enum AyuSchema {
    /// Statements creating the patch-layer schema from scratch.
    /// Executed inside a single GRDB migration.
    static let createStatements: [String] = [
        "PRAGMA foreign_keys = ON",
        "CREATE TABLE IF NOT EXISTS `DeletedMessage` ( `fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `userId` INTEGER NOT NULL, `dialogId` INTEGER NOT NULL, `groupedId` INTEGER NOT NULL, `peerId` INTEGER NOT NULL, `fromId` INTEGER NOT NULL, `topicId` INTEGER NOT NULL, `messageId` INTEGER NOT NULL, `date` INTEGER NOT NULL, `flags` INTEGER NOT NULL, `editDate` INTEGER NOT NULL, `views` INTEGER NOT NULL, `fwdFlags` INTEGER NOT NULL, `fwdFromId` INTEGER NOT NULL, `fwdName` TEXT, `fwdDate` INTEGER NOT NULL, `fwdPostAuthor` TEXT, `postAuthor` TEXT, `replyFlags` INTEGER NOT NULL, `replyMessageId` INTEGER NOT NULL, `replyPeerId` INTEGER NOT NULL, `replyTopId` INTEGER NOT NULL, `replyForumTopic` INTEGER NOT NULL, `replySerialized` BLOB, `replyMarkupSerialized` BLOB, `entityCreateDate` INTEGER NOT NULL, `text` TEXT, `textEntities` BLOB, `mediaPath` TEXT, `hqThumbPath` TEXT, `documentType` INTEGER NOT NULL, `documentSerialized` BLOB, `thumbsSerialized` BLOB, `documentAttributesSerialized` BLOB, `mimeType` TEXT )",
        "CREATE INDEX IF NOT EXISTS `index_DeletedMessage_groupedId` ON `DeletedMessage` (`groupedId`)",
        "CREATE INDEX IF NOT EXISTS `index_DeletedMessage_userId_dialogId_topicId_messageId` ON `DeletedMessage` (`userId`, `dialogId`, `topicId`, `messageId`)",
        "CREATE TABLE IF NOT EXISTS `DeletedMessageReaction` ( `fakeReactionId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `deletedMessageId` INTEGER NOT NULL, `emoticon` TEXT, `documentId` INTEGER NOT NULL, `isCustom` INTEGER NOT NULL, `count` INTEGER NOT NULL, `selfSelected` INTEGER NOT NULL )",
        "CREATE INDEX IF NOT EXISTS `index_DeletedMessageReaction_deletedMessageId` ON `DeletedMessageReaction` (`deletedMessageId`)",
        "CREATE TABLE IF NOT EXISTS `DeletedDialog` ( `fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `userId` INTEGER NOT NULL, `dialogId` INTEGER NOT NULL, `peerId` INTEGER NOT NULL, `folderId` INTEGER, `topMessage` INTEGER NOT NULL, `lastMessageDate` INTEGER NOT NULL, `flags` INTEGER NOT NULL, `entityCreateDate` INTEGER NOT NULL )",
        "CREATE INDEX IF NOT EXISTS `index_DeletedDialog_userId_dialogId` ON `DeletedDialog` (`userId`, `dialogId`)",
        "CREATE TABLE IF NOT EXISTS `EditedMessage` ( `fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `userId` INTEGER NOT NULL, `dialogId` INTEGER NOT NULL, `groupedId` INTEGER NOT NULL, `peerId` INTEGER NOT NULL, `fromId` INTEGER NOT NULL, `topicId` INTEGER NOT NULL, `messageId` INTEGER NOT NULL, `date` INTEGER NOT NULL, `flags` INTEGER NOT NULL, `editDate` INTEGER NOT NULL, `views` INTEGER NOT NULL, `fwdFlags` INTEGER NOT NULL, `fwdFromId` INTEGER NOT NULL, `fwdName` TEXT, `fwdDate` INTEGER NOT NULL, `fwdPostAuthor` TEXT, `postAuthor` TEXT, `replyFlags` INTEGER NOT NULL, `replyMessageId` INTEGER NOT NULL, `replyPeerId` INTEGER NOT NULL, `replyTopId` INTEGER NOT NULL, `replyForumTopic` INTEGER NOT NULL, `replySerialized` BLOB, `replyMarkupSerialized` BLOB, `entityCreateDate` INTEGER NOT NULL, `text` TEXT, `textEntities` BLOB, `mediaPath` TEXT, `hqThumbPath` TEXT, `documentType` INTEGER NOT NULL, `documentSerialized` BLOB, `thumbsSerialized` BLOB, `documentAttributesSerialized` BLOB, `mimeType` TEXT )",
        "CREATE INDEX IF NOT EXISTS `index_EditedMessage_userId_dialogId_messageId` ON `EditedMessage` (`userId`, `dialogId`, `messageId`)",
        "CREATE INDEX IF NOT EXISTS `index_EditedMessage_userId_dialogId_messageId_entityCreateDate` ON `EditedMessage` (`userId`, `dialogId`, `messageId`, `entityCreateDate`)",
        "CREATE INDEX IF NOT EXISTS `index_EditedMessage_userId_dialogId_messageId_fakeId` ON `EditedMessage` (`userId`, `dialogId`, `messageId`, `fakeId`)",
        "CREATE INDEX IF NOT EXISTS `index_EditedMessage_userId_dialogId_messageId_mediaPath` ON `EditedMessage` (`userId`, `dialogId`, `messageId`, `mediaPath`)",
        "CREATE TABLE IF NOT EXISTS `SpyMessageRead` ( `fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `userId` INTEGER NOT NULL, `dialogId` INTEGER NOT NULL, `messageId` INTEGER NOT NULL, `entityCreateDate` INTEGER NOT NULL )",
        "CREATE INDEX IF NOT EXISTS `index_SpyMessageRead_userId_dialogId_messageId` ON `SpyMessageRead` (`userId`, `dialogId`, `messageId`)",
        "CREATE TABLE IF NOT EXISTS `SpyMessageContentsRead` ( `fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `userId` INTEGER NOT NULL, `dialogId` INTEGER NOT NULL, `messageId` INTEGER NOT NULL, `entityCreateDate` INTEGER NOT NULL )",
        "CREATE INDEX IF NOT EXISTS `index_SpyMessageContentsRead_userId_dialogId_messageId` ON `SpyMessageContentsRead` (`userId`, `dialogId`, `messageId`)",
        "CREATE TABLE IF NOT EXISTS `RegexFilter` ( `id` BLOB NOT NULL, `text` TEXT, `enabled` INTEGER NOT NULL, `reversed` INTEGER NOT NULL DEFAULT false, `caseInsensitive` INTEGER NOT NULL, `dialogId` INTEGER, PRIMARY KEY (`id`) )",
        "CREATE TABLE IF NOT EXISTS `RegexFilterGlobalExclusion` ( `fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `dialogId` INTEGER NOT NULL, `filterId` BLOB )",
    ]
}
