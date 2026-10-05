import Foundation

/// The ad-blocking settings the policy needs.
///
/// Passed as a value rather than read from `AyuSettings` so the policy stays a pure
/// function of its inputs: it has no dependency outside Foundation, which is what
/// lets the test harness compile and execute it, and it cannot quietly consult
/// global state while being tested.
public struct AyuAdPolicyConfiguration: Hashable {
    public let isEnabled: Bool
    /// Hide every sponsored message regardless of content.
    public let hideAllSponsored: Bool
    /// Also hide entries Telegram flags as recommendations rather than paid ads.
    public let hideRecommended: Bool
    /// Extra keywords; a match on any of them hides the message.
    public let keywords: [String]

    public init(
        isEnabled: Bool,
        hideAllSponsored: Bool = true,
        hideRecommended: Bool = false,
        keywords: [String] = []
    ) {
        self.isEnabled = isEnabled
        self.hideAllSponsored = hideAllSponsored
        self.hideRecommended = hideRecommended
        self.keywords = keywords
    }
}

/// Decides whether a sponsored message is dropped.
///
/// Mirrors the sponsored-message half of AyuGram's ad blocking. The Android
/// original ships `libetgadblock.so` plus an `AdBlockClient` that consumes
/// ABP-style filter lists and cosmetic rules, and also rewrites in-app web pages.
/// That is a far larger surface than can be reproduced faithfully here, so this
/// covers the part that is both self-contained and testable — dropping the
/// sponsored entries Telegram injects into channels — while the rest is listed in
/// AyuGram/docs/PORT-MAP.md rather than half-implemented.
///
/// Matching is a case-insensitive **substring** test, not a regular expression:
/// keyword lists are what users actually paste into ad blockers, and a stray
/// bracket in a keyword should not silently disable blocking. AyuGram's separate
/// regex message filters (`AyuFilters`) exist for pattern matching.
public enum AyuAdPolicy {
    /// Whether this sponsored message should be hidden.
    ///
    /// - Parameters:
    ///   - title: the sponsorship title, e.g. "Sponsored".
    ///   - text: the message body.
    ///   - url: the target URL, when present.
    ///   - sponsorInfo: the "sponsored by" line, when present.
    ///   - isRecommended: whether Telegram flagged it as a recommendation rather
    ///     than a paid placement.
    ///   - configuration: the current ad-blocking settings.
    public static func shouldHide(
        title: String?,
        text: String?,
        url: String?,
        sponsorInfo: String?,
        isRecommended: Bool,
        configuration: AyuAdPolicyConfiguration
    ) -> Bool {
        guard configuration.isEnabled else {
            return false
        }

        // A recommendation is not a paid placement, so it survives unless the user
        // asked for it to go too. Checked before the blanket rule so the blanket
        // rule cannot silently swallow it.
        if isRecommended && !configuration.hideRecommended {
            return false
        }

        if configuration.hideAllSponsored {
            return true
        }

        let keywords = configuration.keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !keywords.isEmpty else {
            return false
        }

        // One haystack: a keyword may name the advertiser, the headline or the
        // destination, and a user cannot know which field a given ad uses.
        let haystack = [title, text, url, sponsorInfo]
            .compactMap { $0 }
            .joined(separator: "\n")

        for keyword in keywords {
            if haystack.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                return true
            }
        }
        return false
    }
}
