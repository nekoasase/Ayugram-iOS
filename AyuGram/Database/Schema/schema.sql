-- AyuGram iOS — каноническая схема БД патч-слоя.
-- Извлечено дословно из vanilla-ayuGram-universal-20250101.apk
-- (см. docs/raw-schema.sql и tools/extract_schema.py).
-- Это ФИНАЛЬНОЕ состояние после миграций Room 23 -> 32.
-- Проверяется скриптом tools/verify_schema.py (реальный прогон в SQLite).

PRAGMA foreign_keys = ON;

-- ============================================================
-- Anti-delete: снапшоты удалённых сообщений
-- ============================================================

CREATE TABLE IF NOT EXISTS `DeletedMessage` (
    `fakeId`                       INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    `userId`                       INTEGER NOT NULL,
    `dialogId`                     INTEGER NOT NULL,
    `groupedId`                    INTEGER NOT NULL,
    `peerId`                       INTEGER NOT NULL,
    `fromId`                       INTEGER NOT NULL,
    `topicId`                      INTEGER NOT NULL,
    `messageId`                    INTEGER NOT NULL,
    `date`                         INTEGER NOT NULL,
    `flags`                        INTEGER NOT NULL,
    `editDate`                     INTEGER NOT NULL,
    `views`                        INTEGER NOT NULL,
    `fwdFlags`                     INTEGER NOT NULL,
    `fwdFromId`                    INTEGER NOT NULL,
    `fwdName`                      TEXT,
    `fwdDate`                      INTEGER NOT NULL,
    `fwdPostAuthor`                TEXT,
    `postAuthor`                   TEXT,
    `replyFlags`                   INTEGER NOT NULL,
    `replyMessageId`               INTEGER NOT NULL,
    `replyPeerId`                  INTEGER NOT NULL,
    `replyTopId`                   INTEGER NOT NULL,
    `replyForumTopic`              INTEGER NOT NULL,
    `replySerialized`              BLOB,
    `replyMarkupSerialized`        BLOB,
    `entityCreateDate`             INTEGER NOT NULL,
    `text`                         TEXT,
    `textEntities`                 BLOB,
    `mediaPath`                    TEXT,
    `hqThumbPath`                  TEXT,
    `documentType`                 INTEGER NOT NULL,
    `documentSerialized`           BLOB,
    `thumbsSerialized`             BLOB,
    `documentAttributesSerialized` BLOB,
    `mimeType`                     TEXT,
    `messageSerialized`            BLOB
);
CREATE INDEX IF NOT EXISTS `index_DeletedMessage_groupedId`
    ON `DeletedMessage` (`groupedId`);
CREATE INDEX IF NOT EXISTS `index_DeletedMessage_userId_dialogId_topicId_messageId`
    ON `DeletedMessage` (`userId`, `dialogId`, `topicId`, `messageId`);

-- Реакции, снятые в момент удаления.
CREATE TABLE IF NOT EXISTS `DeletedMessageReaction` (
    `fakeReactionId`    INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    `deletedMessageId`  INTEGER NOT NULL,
    `emoticon`          TEXT,
    `documentId`        INTEGER NOT NULL,
    `isCustom`          INTEGER NOT NULL,
    `count`             INTEGER NOT NULL,
    `selfSelected`      INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS `index_DeletedMessageReaction_deletedMessageId`
    ON `DeletedMessageReaction` (`deletedMessageId`);

-- Удалённые диалоги (чат целиком).
-- `folderId` добавлен миграцией: ALTER TABLE `DeletedDialog` ADD COLUMN `folderId` INTEGER DEFAULT NULL.
CREATE TABLE IF NOT EXISTS `DeletedDialog` (
    `fakeId`           INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    `userId`           INTEGER NOT NULL,
    `dialogId`         INTEGER NOT NULL,
    `peerId`           INTEGER NOT NULL,
    `folderId`         INTEGER,
    `topMessage`       INTEGER NOT NULL,
    `lastMessageDate`  INTEGER NOT NULL,
    `flags`            INTEGER NOT NULL,
    `entityCreateDate` INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS `index_DeletedDialog_userId_dialogId`
    ON `DeletedDialog` (`userId`, `dialogId`);

-- ПРИМЕЧАНИЕ: `DeletedMessageFull` — не таблица. В dex нет CREATE TABLE для неё:
-- это @Embedded/@Relation DTO, склеивающий DeletedMessage + DeletedMessageReaction.
-- На iOS — GRDB-структура с associations, без собственной таблицы.

-- ============================================================
-- История правок
-- ============================================================

CREATE TABLE IF NOT EXISTS `EditedMessage` (
    `fakeId`                       INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    `userId`                       INTEGER NOT NULL,
    `dialogId`                     INTEGER NOT NULL,
    `groupedId`                    INTEGER NOT NULL,
    `peerId`                       INTEGER NOT NULL,
    `fromId`                       INTEGER NOT NULL,
    `topicId`                      INTEGER NOT NULL,
    `messageId`                    INTEGER NOT NULL,
    `date`                         INTEGER NOT NULL,
    `flags`                        INTEGER NOT NULL,
    `editDate`                     INTEGER NOT NULL,
    `views`                        INTEGER NOT NULL,
    `fwdFlags`                     INTEGER NOT NULL,
    `fwdFromId`                    INTEGER NOT NULL,
    `fwdName`                      TEXT,
    `fwdDate`                      INTEGER NOT NULL,
    `fwdPostAuthor`                TEXT,
    `postAuthor`                   TEXT,
    `replyFlags`                   INTEGER NOT NULL,
    `replyMessageId`               INTEGER NOT NULL,
    `replyPeerId`                  INTEGER NOT NULL,
    `replyTopId`                   INTEGER NOT NULL,
    `replyForumTopic`              INTEGER NOT NULL,
    `replySerialized`              BLOB,
    `replyMarkupSerialized`        BLOB,
    `entityCreateDate`             INTEGER NOT NULL,
    `text`                         TEXT,
    `textEntities`                 BLOB,
    `mediaPath`                    TEXT,
    `hqThumbPath`                  TEXT,
    `documentType`                 INTEGER NOT NULL,
    `documentSerialized`           BLOB,
    `thumbsSerialized`             BLOB,
    `documentAttributesSerialized` BLOB,
    `mimeType`                     TEXT,
    `messageSerialized`            BLOB
);
CREATE INDEX IF NOT EXISTS `index_EditedMessage_userId_dialogId_messageId`
    ON `EditedMessage` (`userId`, `dialogId`, `messageId`);
CREATE INDEX IF NOT EXISTS `index_EditedMessage_userId_dialogId_messageId_entityCreateDate`
    ON `EditedMessage` (`userId`, `dialogId`, `messageId`, `entityCreateDate`);
CREATE INDEX IF NOT EXISTS `index_EditedMessage_userId_dialogId_messageId_fakeId`
    ON `EditedMessage` (`userId`, `dialogId`, `messageId`, `fakeId`);
CREATE INDEX IF NOT EXISTS `index_EditedMessage_userId_dialogId_messageId_mediaPath`
    ON `EditedMessage` (`userId`, `dialogId`, `messageId`, `mediaPath`);

-- ============================================================
-- Spy: кто прочитал сообщения
-- ============================================================

CREATE TABLE IF NOT EXISTS `SpyMessageRead` (
    `fakeId`           INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    `userId`           INTEGER NOT NULL,
    `dialogId`         INTEGER NOT NULL,
    `messageId`        INTEGER NOT NULL,
    `entityCreateDate` INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS `index_SpyMessageRead_userId_dialogId_messageId`
    ON `SpyMessageRead` (`userId`, `dialogId`, `messageId`);

-- Отдельно от факта прочтения: прочитано ли СОДЕРЖИМОЕ
-- (updateReadMessagesContents / updateChannelReadMessagesContents).
CREATE TABLE IF NOT EXISTS `SpyMessageContentsRead` (
    `fakeId`           INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    `userId`           INTEGER NOT NULL,
    `dialogId`         INTEGER NOT NULL,
    `messageId`        INTEGER NOT NULL,
    `entityCreateDate` INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS `index_SpyMessageContentsRead_userId_dialogId_messageId`
    ON `SpyMessageContentsRead` (`userId`, `dialogId`, `messageId`);

-- ============================================================
-- Regex-фильтры
-- ============================================================
-- ВАЖНО: в схеме 23 PK был `fakeId INTEGER`; миграция пересоздала таблицу как
-- `RegexFilter_new` с `id BLOB PRIMARY KEY` и добавила `reversed` (инверсия),
-- затем ALTER TABLE RegexFilter_new RENAME TO RegexFilter.
-- Ниже — финальное состояние.

CREATE TABLE IF NOT EXISTS `RegexFilter` (
    `id`              BLOB NOT NULL,
    `text`            TEXT,
    `enabled`         INTEGER NOT NULL,
    `reversed`        INTEGER NOT NULL DEFAULT false,
    `caseInsensitive` INTEGER NOT NULL,
    `dialogId`        INTEGER,
    PRIMARY KEY (`id`)
);

-- Исключения для глобального фильтра: связь dialogId <-> filterId.
CREATE TABLE IF NOT EXISTS `RegexFilterGlobalExclusion` (
    `fakeId`     INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    `dialogId`   INTEGER NOT NULL,
    `filterId`   BLOB
);
