-- AyuGram iOS: schema extracted verbatim from vanilla-ayuGram APK
-- Source: com.radolyn.ayugram (AyuDatabase), tables of the patch layer
-- Do not edit by hand: regenerate with tools/extract_schema.py

-- ---------- DeletedMessage ----------
CREATE TABLE IF NOT EXISTS `DeletedMessage` (`fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `userId` INTEGER NOT NULL, `dialogId` INTEGER NOT NULL, `groupedId` INTEGER NOT NULL, `peerId` INTEGER NOT NULL, `fromId` INTEGER NOT NULL, `topicId` INTEGER NOT NULL, `messageId` INTEGER NOT NULL, `date` INTEGER NOT NULL, `flags` INTEGER NOT NULL, `editDate` INTEGER NOT NULL, `views` INTEGER NOT NULL, `fwdFlags` INTEGER NOT NULL, `fwdFromId` INTEGER NOT NULL, `fwdName` TEXT, `fwdDate` INTEGER NOT NULL, `fwdPostAuthor` TEXT, `postAuthor` TEXT, `replyFlags` INTEGER NOT NULL, `replyMessageId` INTEGER NOT NULL, `replyPeerId` INTEGER NOT NULL, `replyTopId` INTEGER NOT NULL, `replyForumTopic` INTEGER NOT NULL, `replySerialized` BLOB, `replyMarkupSerialized` BLOB, `entityCreateDate` INTEGER NOT NULL, `text` TEXT, `textEntities` BLOB, `mediaPath` TEXT, `hqThumbPath` TEXT, `documentType` INTEGER NOT NULL, `documentSerialized` BLOB, `thumbsSerialized` BLOB, `documentAttributesSerialized` BLOB, `mimeType` TEXT);
CREATE INDEX IF NOT EXISTS `index_DeletedMessage_groupedId` ON `DeletedMessage` (`groupedId`);
CREATE INDEX IF NOT EXISTS `index_DeletedMessage_userId_dialogId_topicId_messageId` ON `DeletedMessage` (`userId`, `dialogId`, `topicId`, `messageId`);

-- !! no CREATE TABLE captured for DeletedMessageFull

-- ---------- DeletedMessageReaction ----------
CREATE TABLE IF NOT EXISTS `DeletedMessageReaction` (`fakeReactionId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `deletedMessageId` INTEGER NOT NULL, `emoticon` TEXT, `documentId` INTEGER NOT NULL, `isCustom` INTEGER NOT NULL, `count` INTEGER NOT NULL, `selfSelected` INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS `index_DeletedMessageReaction_deletedMessageId` ON `DeletedMessageReaction` (`deletedMessageId`);

-- ---------- DeletedDialog ----------
CREATE TABLE IF NOT EXISTS `DeletedDialog` (`fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `userId` INTEGER NOT NULL, `dialogId` INTEGER NOT NULL, `peerId` INTEGER NOT NULL, `folderId` INTEGER, `topMessage` INTEGER NOT NULL, `lastMessageDate` INTEGER NOT NULL, `flags` INTEGER NOT NULL, `entityCreateDate` INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS `index_DeletedDialog_userId_dialogId` ON `DeletedDialog` (`userId`, `dialogId`);

-- ---------- EditedMessage ----------
CREATE TABLE IF NOT EXISTS `EditedMessage` (`fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `userId` INTEGER NOT NULL, `dialogId` INTEGER NOT NULL, `groupedId` INTEGER NOT NULL, `peerId` INTEGER NOT NULL, `fromId` INTEGER NOT NULL, `topicId` INTEGER NOT NULL, `messageId` INTEGER NOT NULL, `date` INTEGER NOT NULL, `flags` INTEGER NOT NULL, `editDate` INTEGER NOT NULL, `views` INTEGER NOT NULL, `fwdFlags` INTEGER NOT NULL, `fwdFromId` INTEGER NOT NULL, `fwdName` TEXT, `fwdDate` INTEGER NOT NULL, `fwdPostAuthor` TEXT, `postAuthor` TEXT, `replyFlags` INTEGER NOT NULL, `replyMessageId` INTEGER NOT NULL, `replyPeerId` INTEGER NOT NULL, `replyTopId` INTEGER NOT NULL, `replyForumTopic` INTEGER NOT NULL, `replySerialized` BLOB, `replyMarkupSerialized` BLOB, `entityCreateDate` INTEGER NOT NULL, `text` TEXT, `textEntities` BLOB, `mediaPath` TEXT, `hqThumbPath` TEXT, `documentType` INTEGER NOT NULL, `documentSerialized` BLOB, `thumbsSerialized` BLOB, `documentAttributesSerialized` BLOB, `mimeType` TEXT);
CREATE INDEX IF NOT EXISTS `index_EditedMessage_userId_dialogId_messageId_entityCreateDate` ON `EditedMessage` (`userId`, `dialogId`, `messageId`, `entityCreateDate`);
CREATE INDEX IF NOT EXISTS `index_EditedMessage_userId_dialogId_messageId_fakeId` ON `EditedMessage` (`userId`, `dialogId`, `messageId`, `fakeId`);
CREATE INDEX IF NOT EXISTS `index_EditedMessage_userId_dialogId_messageId_mediaPath` ON `EditedMessage` (`userId`, `dialogId`, `messageId`, `mediaPath`);
CREATE INDEX IF NOT EXISTS `index_EditedMessage_userId_dialogId_messageId` ON `EditedMessage` (`userId`, `dialogId`, `messageId`);

-- ---------- SpyMessageRead ----------
CREATE TABLE IF NOT EXISTS `SpyMessageRead` (`fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `userId` INTEGER NOT NULL, `dialogId` INTEGER NOT NULL, `messageId` INTEGER NOT NULL, `entityCreateDate` INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS `index_SpyMessageRead_userId_dialogId_messageId` ON `SpyMessageRead` (`userId`, `dialogId`, `messageId`);

-- ---------- SpyMessageContentsRead ----------
CREATE TABLE IF NOT EXISTS `SpyMessageContentsRead` (`fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `userId` INTEGER NOT NULL, `dialogId` INTEGER NOT NULL, `messageId` INTEGER NOT NULL, `entityCreateDate` INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS `index_SpyMessageContentsRead_userId_dialogId_messageId` ON `SpyMessageContentsRead` (`userId`, `dialogId`, `messageId`);

-- ---------- RegexFilter ----------
CREATE TABLE IF NOT EXISTS `RegexFilter` (`fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `text` TEXT, `enabled` INTEGER NOT NULL, `caseInsensitive` INTEGER NOT NULL, `dialogId` INTEGER);
CREATE TABLE IF NOT EXISTS `RegexFilter` (`id` BLOB NOT NULL, `text` TEXT, `enabled` INTEGER NOT NULL, `reversed` INTEGER NOT NULL DEFAULT false, `caseInsensitive` INTEGER NOT NULL, `dialogId` INTEGER, PRIMARY KEY(`id`));

-- ---------- RegexFilterGlobalExclusion ----------
CREATE TABLE IF NOT EXISTS `RegexFilterGlobalExclusion` (`fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `dialogId` INTEGER NOT NULL, `filterId` BLOB);

-- ================= raw statement dump =================
ALTER TABLE RegexFilter_new RENAME TO RegexFilter;
ALTER TABLE `DeletedDialog` ADD COLUMN `folderId` INTEGER DEFAULT NULL;
ALTER TABLE `DeletedMessage` ADD COLUMN `postAuthor` TEXT DEFAULT NULL;
ALTER TABLE `DeletedMessage` ADD COLUMN `replyMarkupSerialized` BLOB DEFAULT NULL;
ALTER TABLE `DeletedMessage` ADD COLUMN `replySerialized` BLOB DEFAULT NULL;
ALTER TABLE `EditedMessage` ADD COLUMN `postAuthor` TEXT DEFAULT NULL;
ALTER TABLE `EditedMessage` ADD COLUMN `replyMarkupSerialized` BLOB DEFAULT NULL;
ALTER TABLE `EditedMessage` ADD COLUMN `replySerialized` BLOB DEFAULT NULL;
ALTER TABLE `RegexFilter` ADD COLUMN `reversed` INTEGER NOT NULL DEFAULT false;
ALTER TABLE `_new_DeletedDialog` RENAME TO `DeletedDialog`;
ALTER TABLE `_new_DeletedMessageReaction` RENAME TO `DeletedMessageReaction`;
ALTER TABLE `_new_DeletedMessage` RENAME TO `DeletedMessage`;
ALTER TABLE `_new_EditedMessage` RENAME TO `EditedMessage`;
ALTER TABLE `_new_SpyMessageContentsRead` RENAME TO `SpyMessageContentsRead`;
ALTER TABLE `_new_SpyMessageRead` RENAME TO `SpyMessageRead`;
CREATE INDEX IF NOT EXISTS `index_DeletedDialog_userId_dialogId` ON `DeletedDialog` (`userId`, `dialogId`);
CREATE INDEX IF NOT EXISTS `index_DeletedMessageReaction_deletedMessageId` ON `DeletedMessageReaction` (`deletedMessageId`);
CREATE INDEX IF NOT EXISTS `index_DeletedMessage_groupedId` ON `DeletedMessage` (`groupedId`);
CREATE INDEX IF NOT EXISTS `index_DeletedMessage_userId_dialogId_topicId_messageId` ON `DeletedMessage` (`userId`, `dialogId`, `topicId`, `messageId`);
CREATE INDEX IF NOT EXISTS `index_EditedMessage_userId_dialogId_messageId_entityCreateDate` ON `EditedMessage` (`userId`, `dialogId`, `messageId`, `entityCreateDate`);
CREATE INDEX IF NOT EXISTS `index_EditedMessage_userId_dialogId_messageId_fakeId` ON `EditedMessage` (`userId`, `dialogId`, `messageId`, `fakeId`);
CREATE INDEX IF NOT EXISTS `index_EditedMessage_userId_dialogId_messageId_mediaPath` ON `EditedMessage` (`userId`, `dialogId`, `messageId`, `mediaPath`);
CREATE INDEX IF NOT EXISTS `index_EditedMessage_userId_dialogId_messageId` ON `EditedMessage` (`userId`, `dialogId`, `messageId`);
CREATE INDEX IF NOT EXISTS `index_SpyMessageContentsRead_userId_dialogId_messageId` ON `SpyMessageContentsRead` (`userId`, `dialogId`, `messageId`);
CREATE INDEX IF NOT EXISTS `index_SpyMessageRead_userId_dialogId_messageId` ON `SpyMessageRead` (`userId`, `dialogId`, `messageId`);
CREATE TABLE IF NOT EXISTS RegexFilterGlobalExclusion (fakeId INTEGER PRIMARY KEY NOT NULL, dialogId INTEGER NOT NULL, filterId BLOB);
CREATE TABLE IF NOT EXISTS RegexFilter_new (id BLOB PRIMARY KEY NOT NULL, text TEXT, enabled INTEGER NOT NULL, caseInsensitive INTEGER NOT NULL, dialogId INTEGER);
CREATE TABLE IF NOT EXISTS `DeletedDialog` (`fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `userId` INTEGER NOT NULL, `dialogId` INTEGER NOT NULL, `peerId` INTEGER NOT NULL, `folderId` INTEGER, `topMessage` INTEGER NOT NULL, `lastMessageDate` INTEGER NOT NULL, `flags` INTEGER NOT NULL, `entityCreateDate` INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS `DeletedMessageReaction` (`fakeReactionId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `deletedMessageId` INTEGER NOT NULL, `emoticon` TEXT, `documentId` INTEGER NOT NULL, `isCustom` INTEGER NOT NULL, `count` INTEGER NOT NULL, `selfSelected` INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS `DeletedMessage` (`fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `userId` INTEGER NOT NULL, `dialogId` INTEGER NOT NULL, `groupedId` INTEGER NOT NULL, `peerId` INTEGER NOT NULL, `fromId` INTEGER NOT NULL, `topicId` INTEGER NOT NULL, `messageId` INTEGER NOT NULL, `date` INTEGER NOT NULL, `flags` INTEGER NOT NULL, `editDate` INTEGER NOT NULL, `views` INTEGER NOT NULL, `fwdFlags` INTEGER NOT NULL, `fwdFromId` INTEGER NOT NULL, `fwdName` TEXT, `fwdDate` INTEGER NOT NULL, `fwdPostAuthor` TEXT, `postAuthor` TEXT, `replyFlags` INTEGER NOT NULL, `replyMessageId` INTEGER NOT NULL, `replyPeerId` INTEGER NOT NULL, `replyTopId` INTEGER NOT NULL, `replyForumTopic` INTEGER NOT NULL, `replySerialized` BLOB, `replyMarkupSerialized` BLOB, `entityCreateDate` INTEGER NOT NULL, `text` TEXT, `textEntities` BLOB, `mediaPath` TEXT, `hqThumbPath` TEXT, `documentType` INTEGER NOT NULL, `documentSerialized` BLOB, `thumbsSerialized` BLOB, `documentAttributesSerialized` BLOB, `mimeType` TEXT);
CREATE TABLE IF NOT EXISTS `EditedMessage` (`fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `userId` INTEGER NOT NULL, `dialogId` INTEGER NOT NULL, `groupedId` INTEGER NOT NULL, `peerId` INTEGER NOT NULL, `fromId` INTEGER NOT NULL, `topicId` INTEGER NOT NULL, `messageId` INTEGER NOT NULL, `date` INTEGER NOT NULL, `flags` INTEGER NOT NULL, `editDate` INTEGER NOT NULL, `views` INTEGER NOT NULL, `fwdFlags` INTEGER NOT NULL, `fwdFromId` INTEGER NOT NULL, `fwdName` TEXT, `fwdDate` INTEGER NOT NULL, `fwdPostAuthor` TEXT, `postAuthor` TEXT, `replyFlags` INTEGER NOT NULL, `replyMessageId` INTEGER NOT NULL, `replyPeerId` INTEGER NOT NULL, `replyTopId` INTEGER NOT NULL, `replyForumTopic` INTEGER NOT NULL, `replySerialized` BLOB, `replyMarkupSerialized` BLOB, `entityCreateDate` INTEGER NOT NULL, `text` TEXT, `textEntities` BLOB, `mediaPath` TEXT, `hqThumbPath` TEXT, `documentType` INTEGER NOT NULL, `documentSerialized` BLOB, `thumbsSerialized` BLOB, `documentAttributesSerialized` BLOB, `mimeType` TEXT);
CREATE TABLE IF NOT EXISTS `RegexFilterGlobalExclusion` (`fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `dialogId` INTEGER NOT NULL, `filterId` BLOB);
CREATE TABLE IF NOT EXISTS `RegexFilter` (`fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `text` TEXT, `enabled` INTEGER NOT NULL, `caseInsensitive` INTEGER NOT NULL, `dialogId` INTEGER);
CREATE TABLE IF NOT EXISTS `RegexFilter` (`id` BLOB NOT NULL, `text` TEXT, `enabled` INTEGER NOT NULL, `reversed` INTEGER NOT NULL DEFAULT false, `caseInsensitive` INTEGER NOT NULL, `dialogId` INTEGER, PRIMARY KEY(`id`));
CREATE TABLE IF NOT EXISTS `SpyMessageContentsRead` (`fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `userId` INTEGER NOT NULL, `dialogId` INTEGER NOT NULL, `messageId` INTEGER NOT NULL, `entityCreateDate` INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS `SpyMessageRead` (`fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `userId` INTEGER NOT NULL, `dialogId` INTEGER NOT NULL, `messageId` INTEGER NOT NULL, `entityCreateDate` INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS `_new_DeletedDialog` (`fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `userId` INTEGER NOT NULL, `dialogId` INTEGER NOT NULL, `peerId` INTEGER NOT NULL, `folderId` INTEGER, `topMessage` INTEGER NOT NULL, `lastMessageDate` INTEGER NOT NULL, `flags` INTEGER NOT NULL, `entityCreateDate` INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS `_new_DeletedMessageReaction` (`fakeReactionId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `deletedMessageId` INTEGER NOT NULL, `emoticon` TEXT, `documentId` INTEGER NOT NULL, `isCustom` INTEGER NOT NULL, `count` INTEGER NOT NULL, `selfSelected` INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS `_new_DeletedMessage` (`fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `userId` INTEGER NOT NULL, `dialogId` INTEGER NOT NULL, `groupedId` INTEGER NOT NULL, `peerId` INTEGER NOT NULL, `fromId` INTEGER NOT NULL, `topicId` INTEGER NOT NULL, `messageId` INTEGER NOT NULL, `date` INTEGER NOT NULL, `flags` INTEGER NOT NULL, `editDate` INTEGER NOT NULL, `views` INTEGER NOT NULL, `fwdFlags` INTEGER NOT NULL, `fwdFromId` INTEGER NOT NULL, `fwdName` TEXT, `fwdDate` INTEGER NOT NULL, `fwdPostAuthor` TEXT, `postAuthor` TEXT, `replyFlags` INTEGER NOT NULL, `replyMessageId` INTEGER NOT NULL, `replyPeerId` INTEGER NOT NULL, `replyTopId` INTEGER NOT NULL, `replyForumTopic` INTEGER NOT NULL, `replySerialized` BLOB, `replyMarkupSerialized` BLOB, `entityCreateDate` INTEGER NOT NULL, `text` TEXT, `textEntities` BLOB, `mediaPath` TEXT, `hqThumbPath` TEXT, `documentType` INTEGER NOT NULL, `documentSerialized` BLOB, `thumbsSerialized` BLOB, `documentAttributesSerialized` BLOB, `mimeType` TEXT);
CREATE TABLE IF NOT EXISTS `_new_EditedMessage` (`fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `userId` INTEGER NOT NULL, `dialogId` INTEGER NOT NULL, `groupedId` INTEGER NOT NULL, `peerId` INTEGER NOT NULL, `fromId` INTEGER NOT NULL, `topicId` INTEGER NOT NULL, `messageId` INTEGER NOT NULL, `date` INTEGER NOT NULL, `flags` INTEGER NOT NULL, `editDate` INTEGER NOT NULL, `views` INTEGER NOT NULL, `fwdFlags` INTEGER NOT NULL, `fwdFromId` INTEGER NOT NULL, `fwdName` TEXT, `fwdDate` INTEGER NOT NULL, `fwdPostAuthor` TEXT, `postAuthor` TEXT, `replyFlags` INTEGER NOT NULL, `replyMessageId` INTEGER NOT NULL, `replyPeerId` INTEGER NOT NULL, `replyTopId` INTEGER NOT NULL, `replyForumTopic` INTEGER NOT NULL, `replySerialized` BLOB, `replyMarkupSerialized` BLOB, `entityCreateDate` INTEGER NOT NULL, `text` TEXT, `textEntities` BLOB, `mediaPath` TEXT, `hqThumbPath` TEXT, `documentType` INTEGER NOT NULL, `documentSerialized` BLOB, `thumbsSerialized` BLOB, `documentAttributesSerialized` BLOB, `mimeType` TEXT);
CREATE TABLE IF NOT EXISTS `_new_SpyMessageContentsRead` (`fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `userId` INTEGER NOT NULL, `dialogId` INTEGER NOT NULL, `messageId` INTEGER NOT NULL, `entityCreateDate` INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS `_new_SpyMessageRead` (`fakeId` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `userId` INTEGER NOT NULL, `dialogId` INTEGER NOT NULL, `messageId` INTEGER NOT NULL, `entityCreateDate` INTEGER NOT NULL);
DROP TABLE IF EXISTS `DeletedDialog`;
DROP TABLE IF EXISTS `DeletedMessageReaction`;
DROP TABLE IF EXISTS `DeletedMessage`;
DROP TABLE IF EXISTS `EditedMessage`;
DROP TABLE IF EXISTS `RegexFilterGlobalExclusion`;
DROP TABLE IF EXISTS `RegexFilter`;
DROP TABLE IF EXISTS `SpyMessageContentsRead`;
DROP TABLE IF EXISTS `SpyMessageRead`;
DROP TABLE RegexFilter;
DROP TABLE `DeletedDialog`;
DROP TABLE `DeletedMessageReaction`;
DROP TABLE `DeletedMessage`;
DROP TABLE `EditedMessage`;
DROP TABLE `SpyMessageContentsRead`;
DROP TABLE `SpyMessageRead`;
