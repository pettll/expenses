import Foundation
import Combine

@MainActor
class SheetsService: ObservableObject {

    private let scriptUrlKey = "google_script_url"
    private let secretKey    = "google_script_secret"

    var categoryStore: CategoryCustomizationStore?

    var scriptURL: String {
        get { UserDefaults.standard.string(forKey: scriptUrlKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: scriptUrlKey) }
    }

    var secret: String {
        get { UserDefaults.standard.string(forKey: secretKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: secretKey) }
    }

    var isConfigured: Bool { !scriptURL.isEmpty }

    // MARK: - Upsert (insert or update) a single transaction

    func send(transaction: Transaction) async throws {
        let payload: [String: Any] = [
            "action":     "upsert",
            "txId":       transaction.id.uuidString,
            "name":       transaction.merchant,
            "amount":     String(format: "%.2f", transaction.amount),
            "currency":   transaction.currency,
            "category":   categoryStore?.effectiveCategoryName(for: transaction) ?? transaction.category.rawValue,
            "cardOrPass": transaction.source == .walletNotification ? "Pass" : "Card"
        ]
        try await post(payload: payload)
        transaction.syncedToSheets = true
        transaction.syncError = nil
    }

    // MARK: - Delete a row from the sheet

    func deleteFromSheet(transaction: Transaction) async throws {
        let payload: [String: Any] = [
            "action": "delete",
            "txId":   transaction.id.uuidString
        ]
        try await post(payload: payload)
    }

    // MARK: - Send multiple transactions in a single batch POST

    func sendBatch(transactions: [Transaction]) async throws {
        guard !transactions.isEmpty else { return }
        let items: [[String: Any]] = transactions.map { tx in
            [
                "action":     "upsert",
                "txId":       tx.id.uuidString,
                "name":       tx.merchant,
                "amount":     String(format: "%.2f", tx.amount),
                "currency":   tx.currency,
                "category":   categoryStore?.effectiveCategoryName(for: tx) ?? tx.category.rawValue,
                "cardOrPass": tx.source == .walletNotification ? "Pass" : "Card"
            ]
        }
        let payload: [String: Any] = ["action": "batch", "items": items]
        try await post(payload: payload)
        for tx in transactions {
            tx.syncedToSheets = true
            tx.syncError = nil
        }
    }

    // MARK: - Retry all unsynced transactions

    func retryFailed(transactions: [Transaction]) async {
        let unsynced = transactions.filter { !$0.syncedToSheets }
        guard !unsynced.isEmpty else { return }
        do {
            try await sendBatch(transactions: unsynced)
        } catch {
            for tx in unsynced {
                tx.syncError = error.localizedDescription
            }
        }
    }

    // MARK: - Fetch all rows from the sheet (doGet)

    func fetchRows() async throws -> [SheetsRow] {
        guard isConfigured else { throw SheetsError.notConfigured }
        guard let url = URL(string: scriptURL) else { throw SheetsError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw SheetsError.invalidResponse
        }

        struct Envelope: Decodable { let rows: [SheetsRow] }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        return envelope.rows.filter { !$0.name.isEmpty }
    }

    // MARK: - Patch a sheet row to write its txId (for rows imported without one)

    func patchTxId(rowIndex: Int, txId: String) async throws {
        let payload: [String: Any] = [
            "action":   "patchRow",
            "rowIndex": rowIndex,
            "txId":     txId
        ]
        try await post(payload: payload)
    }

    // MARK: - Test connection

    func testConnection() async throws {
        guard isConfigured else { throw SheetsError.notConfigured }
        guard let url = URL(string: scriptURL) else { throw SheetsError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw SheetsError.invalidResponse
        }

        // Verify response is valid JSON from our doGet
        struct Envelope: Decodable { let rows: [SheetsRow]? ; let error: String? }
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
           let errMsg = envelope.error {
            throw SheetsError.httpError(200, errMsg)
        }
    }

    // MARK: - Internal POST helper

    private func post(payload: [String: Any]) async throws {
        guard isConfigured else { throw SheetsError.notConfigured }
        guard let url = URL(string: scriptURL) else { throw SheetsError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !secret.isEmpty {
            request.setValue(secret, forHTTPHeaderField: "X-App-Secret")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SheetsError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SheetsError.httpError(http.statusCode, body)
        }
    }
}

// MARK: - Sheets row (from doGet)

struct SheetsRow: Identifiable, Decodable {
    let id       = UUID()
    let rowIndex: Int?   // present only after script is redeployed
    let date:     String
    let amount:   String
    let currency: String
    let category: String
    let name:     String
    let txId:     String

    enum CodingKeys: String, CodingKey {
        case rowIndex, date, amount, currency, category, name, txId
    }
}

// MARK: - Errors

enum SheetsError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Google Script URL not configured. Go to Settings."
        case .invalidURL:
            return "The configured URL is not valid."
        case .invalidResponse:
            return "Unexpected response from Google Apps Script."
        case .httpError(let code, let body):
            return "HTTP \(code): \(body)"
        }
    }
}
