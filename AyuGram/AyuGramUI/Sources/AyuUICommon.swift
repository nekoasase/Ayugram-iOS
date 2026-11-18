// MARK: AyuGram
import Foundation
import SwiftSignalKit

/// Runs a synchronous (throwing) DAO call off the main queue and delivers the
/// result on main. The archive store is intentionally synchronous — sqlite on
/// the render thread would stutter the chat list.
func ayuLoadRecords<T>(_ body: @escaping () throws -> [T]) -> Signal<[T], NoError> {
    return Signal { subscriber in
        DispatchQueue.global(qos: .utility).async {
            let result = (try? body()) ?? []
            DispatchQueue.main.async {
                subscriber.putNext(result)
                subscriber.putCompletion()
            }
        }
        return EmptyDisposable
    }
}

private let ayuDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()

/// `entityCreateDate` in the archive is unix milliseconds.
func ayuFormatMillis(_ value: Int64) -> String {
    let date = Date(timeIntervalSince1970: Double(value) / 1000.0)
    return ayuDateFormatter.string(from: date)
}

func ayuFormatSeconds(_ value: Int32) -> String {
    let date = Date(timeIntervalSince1970: Double(value))
    return ayuDateFormatter.string(from: date)
}

func ayuSnippet(_ text: String?, fallback: String = "(no text)") -> String {
    guard let text = text, !text.isEmpty else {
        return fallback
    }
    let flattened = text.replacingOccurrences(of: "\n", with: " ")
    if flattened.count > 90 {
        return String(flattened.prefix(90)) + "…"
    }
    return flattened
}

/// Parses an optional dialog-id input. Empty / "0" means "all dialogs".
func ayuParseDialogId(_ text: String) -> Int64? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed == "0" {
        return nil
    }
    return Int64(trimmed)
}
