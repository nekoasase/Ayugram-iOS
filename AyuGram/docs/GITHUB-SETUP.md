# Сборка и установка через GitHub Actions

Этот документ — практическая инструкция: как из кода в `D:\augram\ayugram-src\Telegram-iOS`
получитьIPA, который встанет на iPhone с iOS 27.

## 0. Что нужно заранее

| Что | Зачем |
|---|---|
| Аккаунт GitHub | Там будет твой форк и CI-раннер macOS |
| Свой `api_id` / `api_hash` | Без них приложение соберётся, но не сможет войти в Telegram |
| Apple ID (бесплатный подойдёт) | Для подписи IPA через Sideloadly / AltStore |
| Компьютер с Windows или macOS | Для самого сайдлоада (без него поставить IPA нельзя) |

Сборка **не требует Мака у тебя**: воркфлоу `build-ios.yml` запускается на hosted-раннере
`macos-26` (Xcode 26.2), а затем отдаёт готовый `.ipa` артефактом.

> Про iOS 27: приложение, собранное с Xcode 26.2 / iOS 26 SDK, запускается на iOS 27 —
> Apple сохраняет совместимость бинарников с новыми версиями iOS. Ничего дополнительного
> для iOS 27 делать не нужно.

## 1. Получить api_id и api_hash

1. Зайди на <https://my.telegram.org/apps>.
2. Войди по номеру телефона, создай новое приложение:
   - **App title** — любое, например `AyuGram iOS`;
   - **Short name** — любое без пробелов;
   - **Platform** — выбери `iOS` (важно: для desktop-платформ API-ключи ведут себя иначе);
   - остальное можно оставить пустым.
3. Скопируй `api_id` (цифры) и `api_hash` (32 hex-символа). Они понадобятся на шаге 3.

## 2. Запушить код в свой GitHub-репозиторий

Локальный репозиторий уже содержит все коммиты порта в ветке `ayugram-ios` и чистое
дерево. Сейчас `origin` указывает на апстрим `Swiftgram/Telegram-iOS` — его нужно заменить.

1. Создай **пустой** репозиторий на GitHub (без README, без .gitignore, без лицензии).
   Имя любое, например `ayugram-ios`. Публичный или приватный — неважно.
2. Выполни в PowerShell (портативный Git уже лежит в `D:\augram\ayugram-toolchain`):

```powershell
$git  = 'D:\augram\ayugram-toolchain\PortableGit\cmd\git.exe'
$repo = 'D:\augram\ayugram-src\Telegram-iOS'
$url  = 'https://github.com/<ТВОЙ_LOGIN>/<ИМЯ_REPO>.git'

# Старый апстрим оставляем под именем upstream
& $git -C $repo remote rename origin upstream
& $git -C $repo remote add origin $url

# Фиксируем все новые файлы и правки (экраны, патчи, инструкции)
& $git -C $repo add -A
& $git -C $repo commit -m "AyuGram: add archive/filter UI screens and CI fixes"

# Отправляем единственную нужную ветку
& $git -C $repo push -u origin ayugram-ios
```

> Обязательно выполни `add -A` + `commit`: новые модули `AyuGram/AyuGramUI` и
> `AyuGram/AyuFilterBridge`, а также исправленный `.github/workflows/build-ios.yml`
> сейчас не закоммичены. Если их не закоммитить, CI соберёт старую версию без
> новых экранов.

Если Git спросит пароль — используй **Personal Access Token** с правом `repo` вместо
пароля аккаунта (GitHub отключил обычную парольную аутентификацию по HTTPS).

> Репозиторий большой (~700k строк + 13 подмодулей). Первый `push` может идти несколько
> минут — это нормально. Подмодули пушить не нужно: в Git они хранятся как ссылки на
> чужие репозитории, а CI подтянет их сам (см. исправление `submodules: recursive` в
> `.github/workflows/build-ios.yml`).

## 3. Добавить секреты в GitHub

В своём репозитории: **Settings → Secrets and variables → Actions → New repository secret**.
Добавь ровно два секрета:

| Имя | Значение |
|---|---|
| `TELEGRAM_API_ID` | цифры из шага 1 |
| `TELEGRAM_API_HASH` | 32 hex-символа из шага 1 |

Названия должны совпадать **точка в точку** — воркфлоу читает именно их.

## 4. Запустить сборку

**Actions → build-ios → Run workflow:**

- `runner`: `macos-26` (если image недоступен на аккаунте — попробуй `macos-15`, но там
  может не быть Xcode 26.2; воркфлоу добавит `--overrideXcodeVersion`, и это риск);
- `configuration`: **`release_arm64`** (именно он даёт IPA для устройства;
  `release_sim_arm64` — только проверка компиляции, на телефон не ставится);
- `credentials`: **`required`** (чтобы CI упал, если секреты не заданы, вместо тихой
  сборки с заглушками).

Первый запуск долгий — до 1–2 часов (Bazel с нуля собирает весь Telegram). Следи за
логом шага `Build`. После завершения в разделе **Artifacts** появится
`ayugram-ios-release_arm64-<номер>` — скачай и распакуй, внутри будет `ayugram.ipa`.

## 5. Поставить IPA на iPhone (iOS 27)

1. Установи **Sideloadly**: <https://sideloadly.io> (Windows и macOS), либо AltStore.
2. Подключи iPhone кабелем, доверь доступ к устройству.
3. Перетащи `ayugram.ipa` в Sideloadly, введи свой Apple ID, нажми **Start**.
4. На iPhone: **Настройки → Основные → VPN и управление устройством** → подтверди
   профиль разработчика с твоим Apple ID.
5. Запусти AyuGram. Настройки порта — **Settings → Swiftgram → AyuGram**.

Ограничения бесплатного Apple ID (не дефекты сборки):

- приложение живёт **7 дней**, затем нужно переподписать (AltStore умеет автоматически);
- одновременно можно держать не больше **3 сайдлоад-приложений**;
- **push-уведомления не работают** — для APNs нужен платный Developer ($99/год).

## 6. Если сборка падает

| Симптом | Что делать |
|---|---|
| `no such package '@build_bazel_rules_apple//...'` | Проверь, что в `build-ios.yml` у `actions/checkout` стоит `submodules: recursive` (исправлено в этой версии) |
| `Xcode 26.2 is required` | Поставь `runner: macos-26`; на `macos-15` добавление `--overrideXcodeVersion` не гарантирует успех |
| Шаг `Check required secrets` падает | Проверь имена секретов и что они не пустые |
| Приложение падает сразу при запуске | Неверный `api_id` / `api_hash` — пересоздай приложение на my.telegram.org |
| «Unable to install» | Не доверен профиль разработчика или истёк 7-дневный срок |
| Нет уведомлений | Ожидаемо для бесплатного Apple ID |

## 7. Что делать с пла($)тным Apple Developer

С секретом `APPLE_TEAM_ID` и сертификатом + provisioning profile можно подписывать IPA
прямо в CI и получить working push-уведомления и год жизни вместо семи дней. Шаги — в
`README.md` корня репозитория, раздел «Advanced Compilation Guide».
