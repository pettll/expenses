import Foundation
import Combine
import SwiftUI

// A single named pattern the user can edit in Settings
struct NotificationPattern: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String           // e.g. "Apple Pay", "Monzo", "Starling"
    var isEnabled: Bool = true

    // Regex with named capture groups: merchant, amount, currency (optional)
    // Example: "(?P<merchant>.+?)\\s+(?P<currency>[£$€R$]?)(?P<amount>[\\d,]+\\.?\\d*)"
    var regex: String

    // Maps regex group names to field names
    // e.g. ["merchant": "merchant", "amount": "amount", "currency": "currency"]
    var groupMapping: [String: String]

    // Which bundle IDs this pattern applies to (empty = all)
    var bundleIdentifiers: [String]

    static var defaults: [NotificationPattern] {
        [
            NotificationPattern(
                name: "Apple Pay (£)",
                regex: #"(?<merchant>.+?)\s+£(?<amount>[\d,]+\.?\d*)"#,
                groupMapping: ["merchant": "merchant", "amount": "amount"],
                bundleIdentifiers: ["com.apple.PassbookUIService", "com.apple.Passbook"]
            ),
            NotificationPattern(
                name: "Apple Pay (multi-currency)",
                regex: #"(?<merchant>.+?)\s+(?<currency>[A-Z]{2,3}\s*)?(?<amount>[\d,]+\.?\d*)"#,
                groupMapping: ["merchant": "merchant", "amount": "amount", "currency": "currency"],
                bundleIdentifiers: ["com.apple.PassbookUIService", "com.apple.Passbook"]
            ),
            NotificationPattern(
                name: "Monzo",
                regex: #"You (?:paid|spent) (?<currency>[£$€])(?<amount>[\d,]+\.?\d*) at (?<merchant>.+)"#,
                groupMapping: ["merchant": "merchant", "amount": "amount", "currency": "currency"],
                bundleIdentifiers: ["co.monzo.Monzo"]
            ),
            NotificationPattern(
                name: "Starling",
                regex: #"(?<merchant>.+?): (?<currency>[£$€])(?<amount>[\d,]+\.?\d*)"#,
                groupMapping: ["merchant": "merchant", "amount": "amount", "currency": "currency"],
                bundleIdentifiers: ["com.starlingbank.StarlingBank"]
            )
        ]
    }
}

// The result of a successful parse
struct ParsedTransaction {
    var merchant: String
    var amount: Double
    var currency: String
    var rawText: String
    var patternUsed: String
}

// Currency symbol → ISO code map
private let currencySymbolMap: [String: String] = [
    "£": "GBP",
    "$": "USD",
    "€": "EUR",
    "R$": "BRL",
    "¥": "JPY",
    "₹": "INR",
    "₩": "KRW",
    "CHF": "CHF",
    "kr": "SEK"
]

@MainActor
class NotificationParser: ObservableObject {
    @Published var patterns: [NotificationPattern] = []

    private let storageKey = "notification_patterns"

    init() {
        load()
    }

    // MARK: - Parse

    func parse(title: String, body: String, bundleIdentifier: String?) -> ParsedTransaction? {
        let fullText = [title, body].filter { !$0.isEmpty }.joined(separator: "\n")

        for pattern in patterns where pattern.isEnabled {
            // Check bundle ID filter
            if !pattern.bundleIdentifiers.isEmpty,
               let bid = bundleIdentifier,
               !pattern.bundleIdentifiers.contains(bid) {
                continue
            }

            if let result = try? apply(pattern: pattern, to: fullText) {
                return result
            }
        }
        return nil
    }

    private func apply(pattern: NotificationPattern, to text: String) throws -> ParsedTransaction? {
        let regex = try NSRegularExpression(pattern: pattern.regex, options: [.caseInsensitive])
        let range = NSRange(text.startIndex..., in: text)

        guard let match = regex.firstMatch(in: text, range: range) else { return nil }

        var fields: [String: String] = [:]
        for (groupName, _) in pattern.groupMapping {
            let r = match.range(withName: groupName)
            if r.location != NSNotFound, let swiftRange = Range(r, in: text) {
                fields[groupName] = String(text[swiftRange]).trimmingCharacters(in: .whitespaces)
            }
        }

        guard let merchant = fields["merchant"],
              let amountStr = fields["amount"],
              let amount = Double(amountStr.replacingOccurrences(of: ",", with: ""))
        else { return nil }

        let rawCurrency = fields["currency"] ?? ""
        let currency = currencySymbolMap[rawCurrency] ?? (rawCurrency.isEmpty ? "GBP" : rawCurrency)

        return ParsedTransaction(
            merchant: merchant,
            amount: amount,
            currency: currency,
            rawText: text,
            patternUsed: pattern.name
        )
    }

    // MARK: - Test a pattern live (used in PatternEditorView)

    func test(pattern: NotificationPattern, against text: String) -> ParsedTransaction? {
        try? apply(pattern: pattern, to: text)
    }

    // MARK: - Persistence

    func save() {
        if let data = try? JSONEncoder().encode(patterns) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([NotificationPattern].self, from: data) {
            patterns = decoded
        } else {
            patterns = NotificationPattern.defaults
        }
    }

    func resetToDefaults() {
        patterns = NotificationPattern.defaults
        save()
    }

    func addPattern(_ pattern: NotificationPattern) {
        patterns.append(pattern)
        save()
    }

    func removePattern(at offsets: IndexSet) {
        patterns.remove(atOffsets: offsets)
        save()
    }

    func movePattern(from source: IndexSet, to destination: Int) {
        patterns.move(fromOffsets: source, toOffset: destination)
        save()
    }
}
