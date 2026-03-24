import Foundation
import SwiftData

enum TransactionSource: String, Codable, CaseIterable {
    case walletNotification = "wallet"
    case shortcut           = "shortcut"
    case manual             = "manual"
    case sheetsSync         = "sheets"

    var displayName: String {
        switch self {
        case .walletNotification: return "Bank Sync"
        case .shortcut:           return "Shortcut"
        case .manual:             return "Manual"
        case .sheetsSync:         return "Sheets"
        }
    }
}

enum TransactionCategory: String, Codable, CaseIterable {
    case alcohol = "Alcohol"
    case bills = "Bills"
    case clothes = "Clothes"
    case coffee = "Coffee"
    case diningOut = "Dining Out"
    case entertainment = "Entertainment"
    case gifts = "Gifts"
    case groceries = "Groceries"
    case health = "Health"
    case other = "Other"
    case study = "Study"
    case toiletries = "Toiletries/Household"
    case transport = "Transport"
    case trips = "Trips"
    case unknown = "Unknown"

    // Maps raw values from the old category set so SwiftData can load
    // records that were saved before the rename without crashing.
    private static let legacyMapping: [String: TransactionCategory] = [
        "Food & Drink":     .diningOut,
        "Shopping":         .other,
        "Travel":           .trips,
        "Bills & Utilities":.bills
        // "Transport", "Entertainment", "Health", "Other", "Unknown"
        // share the same raw value and are handled by init(rawValue:) directly.
    ]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let value = TransactionCategory(rawValue: raw) {
            self = value
        } else if let mapped = TransactionCategory.legacyMapping[raw] {
            self = mapped
        } else {
            self = .other
        }
    }
}

@Model
final class Transaction {
    var id: UUID
    var timestamp: Date
    var amount: Double
    var currency: String
    var merchant: String
    var category: TransactionCategory
    var source: TransactionSource
    var rawNotificationText: String?
    var syncedToSheets: Bool
    var syncError: String?
    /// When set, overrides `category` for display — the transaction belongs to a custom (user-created) category.
    var customCategoryKey: String?
    /// External transaction ID (e.g. GoCardless) — prevents duplicate imports.
    var externalTransactionId: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        amount: Double,
        currency: String,
        merchant: String,
        category: TransactionCategory = .unknown,
        source: TransactionSource,
        rawNotificationText: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.amount = amount
        self.currency = currency
        self.merchant = merchant
        self.category = category
        self.source = source
        self.rawNotificationText = rawNotificationText
        self.syncedToSheets = false
        self.syncError = nil
    }

    var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(amount)"
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    // Format for Google Sheets — matches your existing column order:
    // Timestamp | Value | Currency | Category | Description
    var sheetsRow: [String] {
        let tsFormatter = DateFormatter()
        tsFormatter.dateFormat = "dd/MM/yyyy HH:mm:ss"
        return [
            tsFormatter.string(from: timestamp),
            String(format: "%.2f", amount),
            currency,
            category.rawValue,
            merchant
        ]
    }
}
