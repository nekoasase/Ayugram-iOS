// Executable test harness for AyuAdPolicy, run on the Mac mini.
//
// The policy depends on Foundation only, so its behaviour — including the two
// decisions that are easy to get wrong, "recommended" versus "sponsored" and what
// happens with an empty keyword list — is verified rather than assumed.

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

func config(enabled: Bool = true, hideAll: Bool = true, hideRecommended: Bool = false, keywords: [String] = []) -> AyuAdPolicyConfiguration {
    return AyuAdPolicyConfiguration(
        isEnabled: enabled,
        hideAllSponsored: hideAll,
        hideRecommended: hideRecommended,
        keywords: keywords
    )
}

func shouldHide(
    title: String? = "Sponsored",
    text: String? = "Buy something",
    url: String? = "https://example.com",
    sponsorInfo: String? = nil,
    isRecommended: Bool = false,
    configuration: AyuAdPolicyConfiguration
) -> Bool {
    return AyuAdPolicy.shouldHide(
        title: title,
        text: text,
        url: url,
        sponsorInfo: sponsorInfo,
        isRecommended: isRecommended,
        configuration: configuration
    )
}

print("AyuAdPolicy behaviour")

// --- master switch --------------------------------------------------------
do {
    expect("nothing is hidden while ad blocking is off",
           !shouldHide(configuration: config(enabled: false)))
    expect("sponsored messages are hidden when it is on",
           shouldHide(configuration: config()))
}

// --- recommended versus sponsored ----------------------------------------
// Telegram marks its own suggestions with the same update but a different flag;
// treating them as paid ads would hide content the user did not ask to remove.
do {
    expect("recommendations survive by default",
           !shouldHide(isRecommended: true, configuration: config()))
    expect("recommendations can be hidden explicitly",
           shouldHide(isRecommended: true, configuration: config(hideRecommended: true)))
    expect("paid ads are hidden either way",
           shouldHide(isRecommended: false, configuration: config(hideRecommended: true)))
    expect("the recommendation exception needs the feature to be on",
           !shouldHide(isRecommended: true, configuration: config(enabled: false, hideRecommended: true)))
}

// --- keyword mode ---------------------------------------------------------
do {
    let keywords = ["crypto", "casino"]

    // Blanket off: only matching ads go.
    expect("a matching keyword hides the ad",
           shouldHide(text: "Win at crypto now", configuration: config(hideAll: false, keywords: keywords)))
    expect("a non-matching ad survives",
           !shouldHide(text: "Ordinary message", url: "https://example.com",
                       configuration: config(hideAll: false, keywords: keywords)))
    expect("keywords are matched case-insensitively",
           shouldHide(text: "WIN AT CRYPTO", configuration: config(hideAll: false, keywords: keywords)))
    expect("keywords are matched in the URL",
           shouldHide(text: "nothing here", url: "https://casino.example",
                      configuration: config(hideAll: false, keywords: keywords)))
    expect("keywords are matched in the title",
           shouldHide(title: "Casino bonus", text: "nothing", url: nil,
                      configuration: config(hideAll: false, keywords: keywords)))
    expect("keywords are matched in the sponsor line",
           shouldHide(title: nil, text: "nothing", url: nil, sponsorInfo: "Sponsored by CryptoCorp",
                      configuration: config(hideAll: false, keywords: keywords)))

    // A keyword list that is empty must not behave like "hide everything".
    expect("an empty keyword list hides nothing",
           !shouldHide(configuration: config(hideAll: false, keywords: [])))
    expect("whitespace-only keywords are ignored",
           !shouldHide(configuration: config(hideAll: false, keywords: ["   ", ""])))
    expect("keywords are trimmed before matching",
           shouldHide(text: "try crypto today", configuration: config(hideAll: false, keywords: ["  crypto  "])))
}

// --- missing fields -------------------------------------------------------
// Telegram omits fields it does not need; the policy must not crash or invent a
// match out of nothing.
do {
    expect("all fields absent is handled",
           !shouldHide(title: nil, text: nil, url: nil, sponsorInfo: nil,
                       configuration: config(hideAll: false, keywords: ["crypto"])))
    expect("all fields absent still hidden in blanket mode",
           shouldHide(title: nil, text: nil, url: nil, sponsorInfo: nil, configuration: config()))
}

// --- unicode --------------------------------------------------------------
do {
    expect("cyrillic keywords match",
           shouldHide(text: "Лучшее казино", configuration: config(hideAll: false, keywords: ["казино"])))
    expect("diacritics are ignored when matching",
           shouldHide(text: "Le CAFÉ du coin", configuration: config(hideAll: false, keywords: ["cafe"])))
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
