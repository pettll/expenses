import Foundation
import SwiftData

enum TransactionSource: String, Codable {
    case walletNotification = "wallet"
    case shortcut = "shortcut"
    case manual = "manual"
}

enum TransactionCategory: String, Codable, CaseIterable {
    case foodAndDrink = "Food & Drink"
    case transport = "Transport"
    case shopping = "Shopping"
    case entertainment = "Entertainment"
    case health = "Health"
    case travel = "Travel"
    case billsAndUtilities = "Bills & Utilities"
    case other = "Other"
    case unknown = "Unknown"
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
