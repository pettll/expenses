import Foundation
import Combine

/// Converts amounts to the user's main currency using fawazahmed0/exchange-api.
/// Rates are fetched per calendar day per base currency and cached on disk.
@MainActor
final class ExchangeRateService: ObservableObject {

    private var memoryCache: [String: [String: Double]] = [:]
    private let cacheDirectory: URL

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = base.appendingPathComponent("ExchangeRates", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public

    /// Converts `amount` from `currency` into the user's main currency.
    /// Returns nil if the exchange rate is unavailable (caller should show original currency).
    func convert(amount: Double, from currency: String, date: Date) async -> Double? {
        let mainCurrency = (UserDefaults.standard.string(forKey: "mainCurrency") ?? "GBP").uppercased()
        let from = currency.uppercased()
        guard from != mainCurrency else { return amount }
        let rates = await ratesFor(date: date, base: mainCurrency)
        guard let rate = rates[from.lowercased()], rate > 0 else { return nil }
        return amount / rate
    }

    // MARK: - Private

    private func ratesFor(date: Date, base: String) async -> [String: Double] {
        let key = cacheKey(date: date, base: base)
        if let cached = memoryCache[key] { return cached }
        if let disk = loadFromDisk(key: key) { memoryCache[key] = disk; return disk }
        return await fetchAndCache(key: key, date: date, base: base)
    }

    private func fetchAndCache(key: String, date: Date, base: String) async -> [String: Double] {
        let b = base.lowercased()
        let d = dateKey(date)
        let urls = [
            URL(string: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@\(d)/v1/currencies/\(b).json")!,
            URL(string: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/\(b).json")!,
        ]
        for url in urls {
            if let rates = try? await parse(url: url, base: b) {
                memoryCache[key] = rates
                saveToDisk(rates: rates, key: key)
                return rates
            }
        }
        return [:]
    }

    private func parse(url: URL, base: String) async throws -> [String: Double] {
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        // Response is {"date":"2026-03-20","gbp":{...}} — the "date" key is a String,
        // not a [String:Double], so JSONDecoder with a homogeneous type would fail.
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rates = json[base] as? [String: Double] else {
            throw URLError(.cannotParseResponse)
        }
        return rates
    }

    private func loadFromDisk(key: String) -> [String: Double]? {
        let file = cacheDirectory.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode([String: Double].self, from: data)
    }

    private func saveToDisk(rates: [String: Double], key: String) {
        let file = cacheDirectory.appendingPathComponent("\(key).json")
        try? JSONEncoder().encode(rates).write(to: file)
    }

    private func cacheKey(date: Date, base: String) -> String {
        "\(base.lowercased())_\(dateKey(date))"
    }

    func dateKey(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "Europe/London")
        return fmt.string(from: date)
    }
}

// MARK: - Currency formatting helper

func formatAmount(_ amount: Double, currency: String) -> String {
    let fmt = NumberFormatter()
    fmt.numberStyle = .currency
    fmt.currencyCode = currency
    return fmt.string(from: NSNumber(value: amount)) ?? "\(currency) \(String(format: "%.2f", amount))"
}
