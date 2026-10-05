import Foundation

/// A filter rule in the form the matching engine needs.
///
/// Deliberately not the database record: keeping the engine free of the archive
/// schema means it depends on Foundation alone, so it can be compiled and executed
/// by the test harness rather than merely parsed. The caller maps a stored
/// `RegexFilter` onto this.
public struct AyuFilterRule: Hashable {
    public let pattern: String
    public let isCaseInsensitive: Bool
    /// Act on text that does **not** match, i.e. turn the rule into a whitelist.
    public let isReversed: Bool

    public init(pattern: String, isCaseInsensitive: Bool = true, isReversed: Bool = false) {
        self.pattern = pattern
        self.isCaseInsensitive = isCaseInsensitive
        self.isReversed = isReversed
    }
}

/// Applies AyuGram's regex filters.
///
/// Mirrors `AyuFilterUtils` and its `HashablePattern` cache from the Android
/// original, including the two properties that matter for behaviour:
///
/// * **`reversed`** inverts the rule. The Android schema gained this column in a
///   migration, and a reversed rule means "hide everything that does *not* match",
///   which turns a filter into an allow-list.
/// * **Invalid patterns must not break anything.** The pattern is typed by the
///   user by hand, so `[` is a normal thing to type mid-edit. An unusable rule is
///   ignored and remembered as unusable, so it is not recompiled on every message.
public final class AyuFilterEngine {
    public static let shared = AyuFilterEngine()

    private struct PatternKey: Hashable {
        let pattern: String
        let isCaseInsensitive: Bool
    }

    /// `nil` records a pattern that failed to compile.
    private var cache: [PatternKey: NSRegularExpression?] = [:]
    private let lock = NSLock()

    public init() {
    }

    /// Number of distinct patterns compiled or rejected. Exposed for tests: it is
    /// how the cache is observed without reaching into private state.
    public var cachedPatternCount: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.cache.count
    }

    public func clearCache() {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.cache.removeAll()
    }

    /// Compiles a pattern, or returns `nil` if it is unusable.
    ///
    /// An empty or whitespace-only pattern is treated as unusable rather than as
    /// "matches everything": a rule with no text is a half-finished edit, and
    /// letting it match everything would hide the user's entire chat.
    public func compiledPattern(for rule: AyuFilterRule) -> NSRegularExpression? {
        let trimmed = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let key = PatternKey(pattern: rule.pattern, isCaseInsensitive: rule.isCaseInsensitive)

        self.lock.lock()
        if let cached = self.cache[key] {
            self.lock.unlock()
            return cached
        }
        self.lock.unlock()

        let options: NSRegularExpression.Options = rule.isCaseInsensitive ? [.caseInsensitive] : []
        let compiled = try? NSRegularExpression(pattern: rule.pattern, options: options)

        self.lock.lock()
        self.cache[key] = compiled
        self.lock.unlock()

        return compiled
    }

    /// Whether the rule matches `text`, honouring `isReversed`.
    ///
    /// Returns `false` for an unusable rule: a rule that cannot be evaluated must
    /// never be the reason a message disappears.
    public func matches(_ text: String, rule: AyuFilterRule) -> Bool {
        guard let regex = self.compiledPattern(for: rule) else {
            return false
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        let found = regex.firstMatch(in: text, options: [], range: range) != nil
        return rule.isReversed ? !found : found
    }

    /// Whether any rule matches. Filters combine as OR, matching Android's
    /// behaviour of hiding a message as soon as one rule rejects it.
    public func isFiltered(_ text: String, by rules: [AyuFilterRule]) -> Bool {
        return self.firstMatchingIndex(of: text, in: rules) != nil
    }

    /// Index of the first rule that matches, or `nil`.
    ///
    /// Returned rather than a plain `Bool` so a caller can attribute the decision
    /// to a specific rule — useful for a "why was this hidden?" affordance.
    public func firstMatchingIndex(of text: String, in rules: [AyuFilterRule]) -> Int? {
        for (index, rule) in rules.enumerated() {
            if self.matches(text, rule: rule) {
                return index
            }
        }
        return nil
    }
}
