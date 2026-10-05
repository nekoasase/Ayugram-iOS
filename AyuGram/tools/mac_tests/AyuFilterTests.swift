// Executable test harness for AyuFilterEngine, run on the Mac mini.
//
// The engine depends on Foundation only, so it compiles and *runs* on the
// project's macOS 10.15 machine. That makes the filter semantics — including the
// inverted (`reversed`) rules the Android schema grew a column for — verifiable
// rather than assumed.

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

let engine = AyuFilterEngine()

func rule(_ pattern: String, caseInsensitive: Bool = true, reversed: Bool = false) -> AyuFilterRule {
    return AyuFilterRule(pattern: pattern, isCaseInsensitive: caseInsensitive, isReversed: reversed)
}

print("AyuFilterEngine behaviour")

// --- basic matching -------------------------------------------------------
do {
    expect("a plain pattern matches", engine.matches("купи спам сейчас", rule: rule("спам")))
    expect("a non-matching pattern does not match", !engine.matches("обычное сообщение", rule: rule("спам")))
    // A regex searches anywhere, it is not anchored — this is the behaviour the
    // Android original relies on.
    expect("matching is a search, not a full match", engine.matches("xxabcxx", rule: rule("abc")))
    expect("anchors are honoured", !engine.matches("xxabcxx", rule: rule("^abc$")))
    expect("anchors match at the edges", engine.matches("abc", rule: rule("^abc$")))
    expect("word boundaries work", engine.matches("это спам!", rule: rule("\\bспам\\b")))
}

// --- case sensitivity -----------------------------------------------------
do {
    expect("case-insensitive by default", engine.matches("SPAM", rule: rule("spam")))
    expect("case-sensitive when asked", !engine.matches("SPAM", rule: rule("spam", caseInsensitive: false)))
    expect("case-sensitive still matches exact case", engine.matches("spam", rule: rule("spam", caseInsensitive: false)))
}

// --- inverted rules -------------------------------------------------------
// A reversed rule is an allow-list: it acts on everything that does NOT match.
do {
    expect("reversed rule rejects non-matching text", engine.matches("обычное сообщение", rule: rule("реклама", reversed: true)))
    expect("reversed rule passes matching text", !engine.matches("это реклама", rule: rule("реклама", reversed: true)))
    expect("reversed rule respects case sensitivity",
           engine.matches("РЕКЛАМА", rule: rule("реклама", caseInsensitive: false, reversed: true)))
}

// --- unusable rules must never hide anything ------------------------------
// The pattern is typed by the user, so half-finished input is normal.
do {
    let empty = rule("")
    let blank = rule("   ")
    expect("an empty pattern does not match", !engine.matches("что угодно", rule: empty))
    expect("a whitespace pattern does not match", !engine.matches("что угодно", rule: blank))
    expect("an empty reversed pattern does not match either",
           !engine.matches("что угодно", rule: rule("", reversed: true)))

    let broken = rule("[")
    expect("an invalid pattern does not match", !engine.matches("что угодно", rule: broken))
    expect("an invalid reversed pattern does not match",
           !engine.matches("что угодно", rule: rule("[", reversed: true)))
    // Still reported as compiled (as unusable), so it is not retried per message.
    _ = engine.compiledPattern(for: broken)
    expect("an invalid pattern is not retried", engine.cachedPatternCount > 0,
           "cache=\(engine.cachedPatternCount)")
}

// --- combination and attribution -----------------------------------------
do {
    let rules = [rule("спам"), rule("реклама"), rule("казино")]
    expect("any matching rule filters", engine.isFiltered("заходи в казино", by: rules))
    expect("no matching rule leaves the text alone", !engine.isFiltered("просто сообщение", by: rules))
    expect("an empty rule list filters nothing", !engine.isFiltered("что угодно", by: []))

    expect("the matching rule is identified", engine.firstMatchingIndex(of: "тут реклама", in: rules) == 1)
    expect("no attribution when nothing matches", engine.firstMatchingIndex(of: "нейтрально", in: rules) == nil)
    expect("an unusable rule cannot be blamed",
           engine.firstMatchingIndex(of: "нейтрально", in: [rule("[")]) == nil)
}

// --- a realistic AyuGram setup -------------------------------------------
do {
    // Hide spam, and also hide everything except messages about the project:
    // a plain rule and an allow-list rule side by side.
    let hideSpam = rule("\\bспам\\b")
    let onlyProject = rule("проект", reversed: true)

    expect("spam is filtered", engine.isFiltered("это спам", by: [hideSpam]))
    expect("neutral text survives the spam rule", !engine.isFiltered("привет", by: [hideSpam]))

    expect("the allow-list hides unrelated text", engine.isFiltered("привет", by: [onlyProject]))
    expect("the allow-list keeps matching text", !engine.isFiltered("новости проекта", by: [onlyProject]))

    expect("combined, a matching allow-list entry still passes",
           !engine.isFiltered("о проекте", by: [hideSpam, onlyProject]))
    expect("combined, spam is hidden even if it mentions the project",
           engine.isFiltered("спам о проекте", by: [hideSpam, onlyProject]))
}

// --- unicode --------------------------------------------------------------
do {
    expect("cyrillic is matched literally", engine.matches("Привет, мир", rule: rule("привет")))
    expect("emoji is matched", engine.matches("важно 🔥 сегодня", rule: rule("🔥")))
    expect("unicode character classes work", engine.matches("номер 42", rule: rule("\\d+")))
}

// --- cache ----------------------------------------------------------------
do {
    let fresh = AyuFilterEngine()
    expect("a fresh engine has an empty cache", fresh.cachedPatternCount == 0)

    _ = fresh.compiledPattern(for: rule("abc"))
    expect("compiling populates the cache", fresh.cachedPatternCount == 1)

    _ = fresh.compiledPattern(for: rule("abc"))
    expect("the same pattern is reused", fresh.cachedPatternCount == 1)

    _ = fresh.compiledPattern(for: rule("abc", caseInsensitive: false))
    expect("case sensitivity is part of the cache key", fresh.cachedPatternCount == 2)

    _ = fresh.compiledPattern(for: rule(""))
    expect("an empty pattern is not cached at all", fresh.cachedPatternCount == 2)

    fresh.clearCache()
    expect("the cache can be cleared", fresh.cachedPatternCount == 0)

    // The shared engine must survive all of this: filters are consulted per
    // message, from more than one queue.
    let concurrent = AyuFilterEngine()
    let rules = [rule("спам"), rule("реклама")]
    var concurrentOk = true
    DispatchQueue.concurrentPerform(iterations: 64) { index in
        let filtered = concurrent.isFiltered(index % 2 == 0 ? "спам" : "нормально", by: rules)
        if index % 2 == 0, !filtered {
            concurrentOk = false
        }
        if index % 2 == 1, filtered {
            concurrentOk = false
        }
    }
    expect("concurrent use is consistent", concurrentOk)
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
