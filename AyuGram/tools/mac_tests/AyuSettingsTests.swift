// Executable test harness for AyuSettings, run on the Mac mini.
//
// AyuSettings depends on Foundation only, which means it can be compiled and
// *executed* on the project's macOS 10.15 machine even though that machine cannot
// build the app (Xcode 12.4 cannot build a tree that wants Xcode 26.2). That makes
// this the one part of the port whose behaviour is genuinely testable rather than
// merely parseable.
//
// The logic under test is exactly what the TelegramCore patches consult: whether
// ghost mode applies to a given chat. A bug here would silently disable the
// feature in one direction (leaking read receipts) or break the UI in the other.

import Foundation

var failures: [String] = []

func expect(_ label: String, _ actual: Bool, _ expected: Bool) {
    if actual == expected {
        print("  ok   \(label)")
    } else {
        print("  FAIL \(label): expected \(expected), got \(actual)")
        failures.append(label)
    }
}

func makeSettings() -> AyuSettings {
    // A throwaway suite keeps the test from touching real preferences.
    let suiteName = "ayugram.tests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fatalError("could not create a UserDefaults suite")
    }
    defaults.removePersistentDomain(forName: suiteName)
    return AyuSettings(defaults: defaults)
}

print("AyuSettings behaviour")

// --- defaults -------------------------------------------------------------
do {
    let settings = makeSettings()
    expect("ghost off by default", settings.ghostModeEnabled, false)
    expect("ghost inactive with no override", settings.isGhostModeActive(dialogId: 42), false)
    expect("stories not suppressed by default", settings.suppressesStoryViews, false)
    expect("deleted messages saved by default", settings.saveDeletedMessages, true)
    // The Android documentation warns that bots edit and delete constantly.
    expect("bot dialogs not saved by default", settings.saveDeletedMessagesInBots, false)
    expect("deleted mark style defaults to cross", settings.deletedMessagesMarkStyle == .cross, true)
}

// --- global switch --------------------------------------------------------
do {
    let settings = makeSettings()
    settings.ghostModeEnabled = true
    expect("ghost active in a chat without override", settings.isGhostModeActive(dialogId: 42), true)
    expect("ghost active in another chat too", settings.isGhostModeActive(dialogId: -1001234), true)
    expect("presence flag read", settings.isGhostModeActive, true)
}

// --- per-chat overrides ---------------------------------------------------
do {
    let settings = makeSettings()
    settings.ghostModeEnabled = true
    settings.setGhostMode(false, forDialogId: 42)

    expect("override disables ghost in that chat", settings.isGhostModeActive(dialogId: 42), false)
    expect("override leaves other chats alone", settings.isGhostModeActive(dialogId: 43), true)

    settings.setGhostMode(true, forDialogId: 43)
    expect("explicit enable is honoured", settings.isGhostModeActive(dialogId: 43), true)

    settings.clearGhostModeOverride(forDialogId: 42)
    expect("after clearing, the global switch applies", settings.isGhostModeActive(dialogId: 42), true)
}

// --- the global switch must win over a per-chat enable --------------------
do {
    let settings = makeSettings()
    // A stale "enabled for this chat" entry must not resurrect the feature.
    settings.setGhostMode(true, forDialogId: 7)
    settings.ghostModeEnabled = false
    expect("global off beats a per-chat enable", settings.isGhostModeActive(dialogId: 7), false)
}

// --- story suppression needs both switches --------------------------------
do {
    let settings = makeSettings()
    settings.ghostModeEnabled = true
    settings.ghostModeStories = false
    expect("stories survive with the story switch off", settings.suppressesStoryViews, false)

    settings.ghostModeStories = true
    expect("stories suppressed when both are on", settings.suppressesStoryViews, true)

    settings.ghostModeEnabled = false
    expect("stories survive when ghost mode is off", settings.suppressesStoryViews, false)
}

// --- independent sub-switches ---------------------------------------------
do {
    let settings = makeSettings()
    settings.ghostModeEnabled = true
    settings.ghostModeReadMessages = false
    settings.ghostModeTyping = false
    settings.ghostModeSendOnline = true

    // The patches consult these individually, so they must stay independent of
    // one another; only isGhostModeActive gates them.
    expect("read suppression can be disabled alone", settings.ghostModeReadMessages, false)
    expect("typing suppression can be disabled alone", settings.ghostModeTyping, false)
    expect("presence suppression stays on", settings.ghostModeSendOnline, true)
    expect("ghost mode itself is still active", settings.isGhostModeActive(dialogId: 1), true)
}

// --- persistence across instances -----------------------------------------
do {
    let suiteName = "ayugram.tests.persist.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let first = AyuSettings(defaults: defaults)
    first.ghostModeEnabled = true
    first.setGhostMode(false, forDialogId: -100999)

    let second = AyuSettings(defaults: defaults)
    expect("ghost flag persisted", second.ghostModeEnabled, true)
    expect("per-chat override persisted", second.isGhostModeActive(dialogId: -100999), false)
}

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
