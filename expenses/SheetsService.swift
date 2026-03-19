import Foundation
import Combine

@MainActor
class SheetsService: ObservableObject {

    private let scriptUrlKey = "google_script_url"
    private let secretKey = "google_script_secret"

    var scriptURL: String {
        get { UserDefaults.standard.string(forKey: scriptUrlKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: scriptUrlKey) }
    }

    // Optional shared secret — passed as a header so your Apps Script
    // can verify requests come from this app
    var secret: String {
        get { UserDefaults.standard.string(forKey: secretKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: secretKey) }
    }

    var isConfigured: Bool { !scriptURL.isEmpty }

    // MARK: - Send a single transaction

    func send(transaction: Transaction) async throws {
        guard isConfigured else {
            throw SheetsError.notConfigured
        }
        guard let url = URL(string: scriptURL) else {
            throw SheetsError.invalidURL
        }

        // Matches Apps Script fields: name (required), amount (required), merchant, cardOrPass
        let cardOrPass = transaction.source == .walletNotification ? "Pass" : "Card"
        let payload: [String: Any] = [
            "name":       transaction.merchant,
            "amount":     String(format: "%.2f", transaction.amount),
            "merchant":   transaction.merchant,
            "cardOrPass": cardOrPass
        ]

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

        transaction.syncedToSheets = true
        transaction.syncError = nil
    }

    // MARK: - Retry all failed transactions

    func retryFailed(transactions: [Transaction]) async {
        let failed = transactions.filter { !$0.syncedToSheets }
        for transaction in failed {
            do {
                try await send(transaction: transaction)
            } catch {
                transaction.syncError = error.localizedDescription
            }
        }
    }

    // MARK: - Test connection

    func testConnection() async throws {
        guard isConfigured else { throw SheetsError.notConfigured }
        guard let url = URL(string: scriptURL) else { throw SheetsError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if !secret.isEmpty {
            request.setValue(secret, forHTTPHeaderField: "X-App-Secret")
        }
        request.timeoutInterval = 10

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw SheetsError.invalidResponse
        }
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
        case .notConfigured:   return "Google Script URL not configured. Go to Settings → API Config."
        case .invalidURL:      return "The configured URL is not valid."
        case .invalidResponse: return "Unexpected response from Google Apps Script."
        case .httpError(let code, let body):
            return "HTTP \(code): \(body)"
        }
    }
}
