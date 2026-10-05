# AyuGram → iOS: карта переноса

Документ составлен по фактам, извлечённым из `vanilla-ayuGram-universal-20250101.apk`
(см. `apk-ayu-inventory.txt`, скрипт `../tools/apk_ayu_inventory.py`).

## 0. Что представляет собой оригинал

| Параметр | Значение |
|---|---|
| Пакет | `com.radolyn.ayugram` |
| База | Telegram Android **11.5.3** |
| Родительский форк | [exteraGram](https://github.com/exteraSquad/exteraGram) |
| Код | 5 × `classes*.dex`, ~30 МБ байткода, 136 425 уникальных строк |
| Нативка | `libtmessages.49.so` (21–28 МБ/арх), `libmaps-mobile`, `libvosk`, `libetgadblock`, `libjnidispatch` |
| Слои | AyuGram: 75 классов `com.radolyn.ayugram.*`<br>exteraGram: 159 классов `com.exteragram.messenger.*` |

Ключевой вывод аудита: **фичи AyuGram — это не UI-косметика, а тонкий патч-слой поверх
готового клиента.** 75 классов — это data layer (Room/SQLite) + настройки + хуки в
обработчики MTProto-апдейтов. Именно поэтому перенос на iOS реален: переносится не
клиент, а этот слой.

## 1. Стратегия

**Не делаем:** переписывание Telegram-клиента с нуля (Android-версия >1 млн строк,
iOS-версия ~700k строк Swift/ObjC — это человеко-годы).

**Делаем:** форк [Swiftgram/Telegram-iOS](https://github.com/Swiftgram/Telegram-iOS)
(живой мод-форк Telegram-iOS, тот же, что продаётся в App Store) и переносим в него
патч-слой AyuGram как отдельный модуль `AyuGram/`. Структура слоя повторяет
android-оригинал, чтобы апстримные изменения AyuGram можно было переносить механически:

```
AyuGram/
├── Database/          # порт Room → GRDB/SQLite, схема 1:1 из DEX
│   ├── Entities/
│   └── DAOs/
├── Features/
│   ├── GhostMode/
│   ├── AntiDelete/
│   ├── EditedHistory/
│   ├── SpyRead/
│   ├── RegexFilters/
│   └── AdBlock/
├── Settings/          # UI настроек + хранение флагов
└── AyuState.swift     # аналог com.radolyn.ayugram.AyuState
```

## 2. Data layer — портируется буквально

Схемы таблиц извлечены из DEX дословно, поэтому порт однозначен.

### Anti-delete / история правок

```
DeletedMessage, DeletedMessageFull, DeletedMessageReaction,
DeletedDialog, EditedMessage
```

### Spy (кто прочитал)

```sql
CREATE TABLE SpyMessageRead (
  fakeId INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  userId INTEGER NOT NULL, dialogId INTEGER NOT NULL,
  messageId INTEGER NOT NULL, entityCreateDate INTEGER NOT NULL);
CREATE INDEX index_SpyMessageRead_userId_dialogId_messageId
  ON SpyMessageRead (userId, dialogId, messageId);
-- SpyMessageContentsRead — идентична по структуре
```

### Regex-фильтры

```
RegexFilter, RegexFilterGlobalExclusion  (+ HashablePattern, AyuFilterUtils)
```

Порт: Room → [GRDB](https://github.com/groue/GRDB.swift). Миграции
(`AyuDatabase_AutoMigration_23_24_Impl` … `_31_32_Impl`, т.е. версии 23→32) переносятся
как последовательность GRDB-миграций с теми же номерами.

## 3. Матрица фич и точки врезки в iOS

| # | Фича | Android-реализация | Точка врезки в Telegram-iOS | Сложность |
|---|---|---|---|---|
| 1 | **Ghost Mode** — не отправлять read/online/typing | `AyuState`, `ayughostconfig`, `ayughostexclusionsconfig`, per-chat исключения | Перехват исходящих запросов в `TelegramCore`: `messages.readHistory`, `channels.readHistory`, `messages.setTyping`, `account.updateStatus`, `stories.readStories`. Флаг на уровне `Account`/`Network` | средняя |
| 2 | **Anti-delete** — архив удалённого | `DeletedMessageDao`, `DeletedMessageReaction`, `updateDeleteMessages` | Обработка `updateDeleteMessages` / `updateDeleteChannelMessages` / `updateDeleteScheduledMessages` до удаления из `MessageHistory`; сохранять снапшот сообщения | высокая |
| 3 | **История правок** | `EditedMessageDao` | `updateEditMessage` / `updateEditChannelMessage` — снапшот предыдущей ревизии | средняя |
| 4 | **Spy: кто прочитал** | `SpyDao`, таблицы выше | `updateReadMessagesContents`, `updateChannelReadMessagesContents`, `messages.getMessageReadParticipants` | средняя |
| 5 | **Regex-фильтры** | `AyuFilterUtils`, `HashablePattern` | Фильтрация на вставке в историю чата и в списке диалогов | низкая |
| 6 | **Adblock** | `AdBlockClient` + нативный `libetgadblock.so`, косметические правила | Нативного аналога нет. Порт: локальные filter-списки + блокировка sponsored-сообщений на уровне апдейтов; `WKContentRuleList` для встроенного веба (Instant View) | высокая |
| 7 | **Локальная транскрипция** | `libvosk.so` + модель (в APK — `vosk-model-small-cs`) | **Не нужен Vosk:** в iOS 17+ есть `SFSpeechRecognizer` с on-device распознаванием — нативный и более качественный путь | низкая |
| 8 | **Настройки** | exteraGram settings screens | Отдельный `AyuGramSettingsController` + раздел в настройках | средняя |
| 9 | **Визуальные маркеры** | `DeletedMarkCross/EyeCrossed/TrashBin/Text/Nothing`, `EditedMarkText` | Кастомные атрибуты в рендере сообщений (`ChatMessageItemView`) | средняя |

## 4. Что уже есть на iOS и не пишется заново

- **Telegram-iOS** — MTProto-стек `TelegramCore` (не TDLib), рендер чатов, медиа, звонки.
- **Swiftgram** — мод-слой: свои настройки, скрытие статусов и т.п. Точный список
  пересечений сверить после клонирования (`rg -i "ghost|antidelete|noread"` по репе).
- **ghostgram** ([ichmagmaus111/ghostgram](https://github.com/ichmagmaus111/ghostgram)) —
  iOS-форк с Anti-Delete, Ghost Mode и локальной транскрипцией. Полезен как **референс
  реализации**, те же фичи уже решены на Swift.

## 5. Требования сборки

Из `versions.json` Swiftgram master:

| Компонент | Версия |
|---|---|
| Telegram iOS | 12.9.2 |
| Xcode | **26.2** |
| macOS | **26** |
| Bazel | 8.4.2 |

Сборка:

```bash
git clone --recursive -j8 https://github.com/Swiftgram/Telegram-iOS.git
python3 build-system/Make/Make.py \
    --cacheDir="$HOME/telegram-bazel-cache" generateProject \
    --configurationPath=build-system/template_minimal_development_configuration.json \
    --xcodeManagedCodesigning
```

## 6. Риски и честные ограничения

1. **Xcode 26.2 требует macOS 26.** Если Mac mini не поддерживает macOS 26 — берём
   более старый тег Swiftgram или флаг `--overrideXcodeVersion` (с риском ошибок сборки).
2. **api_id/api_hash обязательны.** Без своего `api_id` с
   [core.telegram.org](https://core.telegram.org/api/obtaining_api_id) приложение не
   подключится к Telegram. Это требование Telegram, обойти нельзя.
3. **Push-уведомления при сайдлоаде.** С бесплатным Apple ID сборка живёт 7 дней и
   **теряет APNs-пуши** (нужны entitlements платного аккаунта). TrollStore снимает
   проблему срока, но не с пушами.
4. **App Store закрыт.** Apple отклоняет форки Telegram — только сайдлоад.
5. **Правовая сторона.** Telegram-iOS под GPLv2: свой форк обязан быть открытым.
   Название и логотип Telegram использовать нельзя (тоже требование Telegram).

## 7. Статус работ

### Готово и проверено (не требует macOS)

Весь data layer патч-слоя — то, что в Android живёт в `com.radolyn.ayugram.database.*`.

| Артефакт | Что это | Проверка |
|---|---|---|
| `docs/raw-schema.sql` | дословный дамп DDL из APK (57 statements) | извлечён из dex |
| `AyuGram/Database/Schema/schema.sql` | каноническая финальная схема, 8 таблиц + 10 индексов | `tools/verify_schema.py` — 20 проверок в реальном SQLite |
| `AyuGram/Database/Schema/AyuSchema.generated.swift` | те же statements как Swift-константы | `tools/gen_swift_schema.py --check` |
| `AyuGram/Database/AyuDatabase.swift` | GRDB-мигратор + импортёр базы из Android | `tools/verify_importer.py` — 23 проверки |
| `AyuGram/Database/Entities/*.swift` | 8 сущностей, включая generic-рекорд на 35 колонок | `tools/verify_models.py` — 36 проверок |
| `tools/verify_all.py` | единая точка входа для CI | `all 4 checks passed` |
| `.github/workflows/verify.yml` | проверки на ubuntu/windows/macos | YAML валиден |
| `.github/workflows/build-ios.yml` | сборка на macOS-раннере (ручной запуск) | YAML валиден, требует первого прогона |

Две ошибки, найденные тестами, а не глазами:

1. **Порядок операций в импортёре.** `ADD COLUMN reversed` до пересоздания
   `RegexFilter` молча теряет колонку, потому что rebuild не копирует её.
   Верный порядок: rebuild → `reversed`. Закреплено регрессионным тестом.
2. **Парсер чекера** путал enum-ы таблиц (`AyuDeletedMessageTable`) с самими
   сущностями, потому что они тоже объявляют `databaseTableName`.

### Требует Mac (заблокировано до включения Remote Login)

- Клонирование базы Swiftgram/Telegram-iOS с сабмодулями.
- Установка Xcode 26.2 (сверить с версией macOS; если macOS < 26 — брать более
  старый тег Swiftgram или `--overrideXcodeVersion`).
- Первая сборка базы без патч-слоя (проверка, что окружение живое).
- Реализация фич, требующих исходников Telegram-iOS: перехват апдейтов
  MTProto (`updateDeleteMessages`, `updateReadMessagesContents`, …),
  Ghost Mode на уровне исходящих запросов, UI настроек.
- Сборка IPA и сайдлоад.

### Осознанно не начато

Код, который невозможно скомпилировать и проверить, писать вредно: он создаёт
видимость прогресса и копит ошибки. Фичи, требующие исходников Telegram-iOS,
будут написаны после клонирования базы — тогда каждая из них проверяется сборкой.

## 8. Точные точки врезки (найдены в исходниках, не предположения)

База склонирована локально: `D:\ayugram-src\Telegram-iOS` — 30 292 файла, 396 МБ,
Telegram iOS 12.9.2. Всё ниже найдено чтением кода.

### 8.1 Ghost Mode — четыре точки

| Что подавляем | Файл | Строки | Вызов |
|---|---|---|---|
| Онлайн-статус | `submodules/TelegramCore/Sources/State/ManagedAccountPresence.swift` | 56, 60 | `account.updateStatus(offline:)` |
| Отметка прочтения | `submodules/TelegramCore/Sources/State/SynchronizePeerReadState.swift` | 254, 284 | `channels.readHistory`, `messages.readHistory` |
| Индикатор печати | `submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift` | 184 | `messages.setTyping` |
| Просмотр сторис | `.../TelegramEngine/Messages/TelegramEngineMessages.swift` | 1634–1640 | **уже сделано Swiftgram** |

Шаблон, которым это делает сам Swiftgram (тот же файл, строки 1634–1640):

```swift
public func markStoryAsSeen(peerId: EnginePeer.Id, id: Int32, asPinned: Bool) -> Signal<Never, NoError> {
    // MARK: Swiftgram
    if SGSimpleSettings.shared.isStealthModeEnabled {
        return .never()
    }
    return _internal_markStoryAsSeen(account: self.account, peerId: peerId, id: id, asPinned: asPinned)
}
```

Паттерн — обернуть публичный метод движка и оборвать вызов. Для AyuGram то же самое
в трёх оставшихся точках, плюс per-chat исключения (в Android — `ayughostexclusionsconfig`).

### 8.2 Что на iOS уже есть — не пишем заново

Найдено в `Swiftgram/SGSimpleSettings/Sources/SimpleSettings.swift`:

- `storyStealthMode` + `canUseStealthMode` + `isStealthModeEnabled` — стелс-режим для сторис;
- `messageFilterKeywords` — фильтр по ключевым словам (**но не regex**);
- `transcriptionBackend` = `default | apple` — **локальная транскрипция через Apple**, то есть
  Vosk из Android-версии не нужен, что подтверждает вывод раздела 3;
- `hideReactions`, `secondsInMessages`, `showRegDate`, `showDC`, `showProfileId`,
  `hideStories`, `warnOnStoriesOpen`, `translationBackend` (`default|gtranslate|system`).

Чего в дереве **нет** (grep по всему репозиторию пуст): анти-удаление, история правок,
spy «кто прочитал», regex-фильтры, Ghost Mode для чатов (есть только для сторис).
Ровно это и составляет работу.

### 8.3 Как устроен форк: фича = Bazel-модуль

```
Swiftgram/SGSimpleSettings/BUILD
Swiftgram/SGSimpleSettings/Sources/SimpleSettings.swift
```

```python
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SGSimpleSettings",
    module_name = "SGSimpleSettings",
    srcs = glob(["Sources/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [
        "//Swiftgram/SGAppGroupIdentifier:SGAppGroupIdentifier",
        "//Swiftgram/SGLogging:SGLogging",
    ],
    visibility = ["//visibility:public"],
)
```

Подключение к движку: `submodules/TelegramCore/BUILD`, строка 5 —
`"//Swiftgram/SGSimpleSettings:SGSimpleSettings"`. То есть форк правит TelegramCore напрямую.

Соглашение о разметке правок: `# MARK: Swiftgram` в Bazel-файлах и `// MARK: Swiftgram`
в Swift. Для AyuGram делаем симметрично: каталог `AyuGram/` со своими модулями и метки
`# MARK: AyuGram` / `// MARK: AyuGram` — так правки не смешиваются с апстримом и видны в diff.

### 8.4 ИСПРАВЛЕНИЕ решения: хранилище — не GRDB

Проверка исходников отменила первоначальный выбор. **GRDB в дереве отсутствует.**
Postbox (штатное хранилище Telegram) — это key-value `ValueBox` поверх sqlite
(`submodules/Postbox/Sources/SqliteValueBox.swift`), а не реляционная СУБД: «таблицы»
вроде `MessageHistoryTable` реализованы как ключ→значение, а не как SQL-таблицы с индексами.

Следствия:

- Писать на GRDB нельзя, не вендорив стороннюю зависимость и не настроив её под Bazel.
- Переписывать схему AyuGram под key-value — значит потерять реляционную схему
  (индексы, JOIN'ы) и всю уже проверенную работу.

**Решение:** raw SQL через sqlcipher, который в дереве уже слинкован, плюс тонкая
типизированная обёртка (open / prepare / bind / step / column) — порядка 200–300 строк,
без сторонних зависимостей.

Что при этом **сохраняется без изменений**: `AyuGram/Database/Schema/schema.sql`
(8 таблиц, 10 индексов), миграции и импортёр базы из Android — это чистый SQL,
он не зависит от движка. Сущности остаются `Codable`-структурами с маппингом колонок
через `CodingKeys`, поэтому автосверка `tools/verify_models.py` продолжает работать.
Убираются только GRDB-специфичные conformance'ы (`FetchableRecord`, `PersistableRecord`)
и `DatabaseMigrator`.

## 9. Что дала документация AyuGram (и что осталось подтвердить)

Источник: [docs.ayugram.one/android/saving](https://docs.ayugram.one/android/saving/).

**Подтверждает наше решение по хранилищу.** AyuGram хранит архив в **собственной
Room-базе**, а не в базе Telegram: «we use **our own**, powered by Android Room»,
файлы `/data/data/PACKAGE/databases/ayu-data*`. Это ровно то, что реализовано здесь:
отдельный файл `ayugram.sqlite` и своя схема. Плюсы, которые перечисляет
документация (архив не зависит от обновлений Telegram, чистится отдельно от кэша),
на iOS сохраняются по той же причине.

**Поведение, которое надо воспроизвести в UI:**

- Режим **«View Deleted»** — отдельный чат только с удалёнными сообщениями, с поиском
  по ним. Это отдельный экран, а не фильтр в обычном чате.
- **Стратегия загрузки при скролле.** AyuGram вклинивается в батч-загрузку истории
  (20–50 сообщений), берёт id первого и последнего загруженного и подтягивает
  удалённые **между ними**. Отсюда запрос
  `deletedMessages(accountId:dialogId:limit:beforeMessageId:)` и
  `archivedMessageIds(...)` в `AyuArchiveStore`.
- **Известное ограничение, которое разработчики не собираются чинить:**
  удалённые сообщения, попавшие *между батчами*, не подгружаются (в документации
  это признано: «It won't be changed in the near future»). При порте это стоит
  воспроизвести осознанно, а не случайно.
- Автозагрузка медиа **до истечения** на сервере, плюс отдельная папка
  `Saved Attachments` — то есть `mediaPath` в снапшоте должен указывать на копию
  в контейнере приложения, а не на кэш Telegram.
- В диалогах с ботами сохранение по умолчанию выключено (боты часто правят и удаляют).

**Осталось подтвердить (внесено как допущение, а не как факт):**
семантика колонки `userId` в таблицах Spy. В `DeletedMessage`/`EditedMessage`/`DeletedDialog`
это идентификатор аккаунта (запросы вида `WHERE userId = ? AND dialogId = ?`),
а в `SpyMessageRead`/`SpyMessageContentsRead` — идентификатор **читателя**, иначе
в этих таблицах читатель не хранился бы вообще. Вывод сделан из извлечённых DDL и SQL,
а не из исходников: релизный APK собран на exteraGram, и соответствующее дерево
исходников пока не найдено (`AyuGram/AyuGram4A` — старая Java-линия, там таблиц Spy нет).
Место, где это используется, помечено комментарием в `AyuArchiveStore`.


