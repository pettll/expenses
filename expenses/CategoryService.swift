import Foundation
import Combine

@MainActor
class CategoryService: ObservableObject {

    // MARK: - User-editable keyword rules
    // Stored as [category raw value: [keywords]]
    @Published var rules: [String: [String]] = [:]

    private let storageKey = "category_rules"
    private let apiKeyStorageKey = "anthropic_api_key"

    var anthropicApiKey: String {
        get { UserDefaults.standard.string(forKey: apiKeyStorageKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: apiKeyStorageKey) }
    }

    init() {
        load()
    }

    // MARK: - Categorise

    // First tries local keyword rules, then falls back to Claude AI
    func categorise(merchant: String) async -> TransactionCategory {
        let local = localCategorise(merchant: merchant)
        if local != .unknown {
            return local
        }
        return await aiCategorise(merchant: merchant)
    }

    // Rules-based: check if merchant contains any keyword for a category
    func localCategorise(merchant: String) -> TransactionCategory {
        let lower = merchant.lowercased()
        for category in TransactionCategory.allCases where category != .unknown {
            let keywords = rules[category.rawValue] ?? defaultKeywords[category.rawValue] ?? []
            if keywords.contains(where: { lower.contains($0.lowercased()) }) {
                return category
            }
        }
        return .unknown
    }

    // Claude AI categorisation
    func aiCategorise(merchant: String) async -> TransactionCategory {
        guard !anthropicApiKey.isEmpty else { return .unknown }

        let categoryList = TransactionCategory.allCases
            .filter { $0 != .unknown }
            .map { $0.rawValue }
            .joined(separator: ", ")

        let prompt = """
        You are a transaction categoriser. Given a merchant name, respond with ONLY the category name from this list — no explanation, no punctuation, nothing else:
        \(categoryList)

        Merchant: \(merchant)
        """

        do {
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(anthropicApiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

            let body: [String: Any] = [
                "model": "claude-haiku-4-5-20251001",
                "max_tokens": 20,
                "messages": [["role": "user", "content": prompt]]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(AnthropicResponse.self, from: data)
            let text = response.content.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            return TransactionCategory.allCases.first { $0.rawValue.lowercased() == text.lowercased() } ?? .other
        } catch {
            print("AI categorisation failed: \(error)")
            return .other
        }
    }

    // MARK: - Default keyword rules

    var defaultKeywords: [String: [String]] {
        [
            TransactionCategory.foodAndDrink.rawValue: [
                "restaurant", "cafe", "coffee", "bar", "pub", "pizza", "burger",
                "sushi", "tesco", "sainsbury", "waitrose", "lidl", "aldi", "morrisons",
                "co-op", "marks", "pret", "greggs", "mcdonalds", "kfc", "subway",
                "starbucks", "costa", "nero", "wine", "brewery", "kitchen", "dining",
                "eat", "food", "grill", "bistro", "brasserie", "tapas", "curry"
            ],
            TransactionCategory.transport.rawValue: [
                "uber", "lyft", "bolt", "taxi", "cab", "tfl", "tube", "rail",
                "train", "bus", "coach", "national rail", "gwr", "avanti", "eurostar",
                "parking", "petrol", "shell", "bp", "esso", "fuel", "garage",
                "mot", "halfords", "kwikfit", "heathrow", "gatwick", "stansted"
            ],
            TransactionCategory.shopping.rawValue: [
                "amazon", "ebay", "etsy", "asos", "zara", "h&m", "primark",
                "next", "john lewis", "selfridges", "harrods", "tk maxx", "boots",
                "superdrug", "argos", "currys", "apple store", "ikea", "b&q",
                "homebase", "screwfix", "wickes", "shop", "store", "market"
            ],
            TransactionCategory.entertainment.rawValue: [
                "netflix", "spotify", "apple music", "disney", "amazon prime",
                "cinema", "odeon", "vue", "cineworld", "theatre", "museum",
                "gallery", "concert", "ticketmaster", "eventbrite", "steam",
                "playstation", "xbox", "nintendo", "game", "sky", "now tv"
            ],
            TransactionCategory.health.rawValue: [
                "pharmacy", "chemist", "doctor", "dentist", "optician", "hospital",
                "clinic", "gym", "fitness", "puregym", "david lloyd", "anytime fitness",
                "nuffield", "virgin active", "pilates", "yoga", "physio",
                "nhs", "bupa", "vitality", "axa health"
            ],
            TransactionCategory.travel.rawValue: [
                "hotel", "airbnb", "booking.com", "expedia", "kayak", "hostel",
                "resort", "holiday", "inn", "marriott", "hilton", "hyatt",
                "ibis", "premier inn", "travelodge", "flight", "airways",
                "british airways", "easyjet", "ryanair", "wizz", "lufthansa"
            ],
            TransactionCategory.billsAndUtilities.rawValue: [
                "council tax", "water", "electric", "gas", "broadband", "bt ",
                "virgin media", "sky broadband", "o2", "vodafone", "ee ", "three",
                "insurance", "mortgage", "rent", "landlord", "hmrc", "tv licence",
                "bulb", "octopus energy", "british gas", "e.on", "npower"
            ]
        ]
    }

    // MARK: - Persistence

    func save() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            rules = decoded
        }
        // Note: if no saved rules, we fall through to defaultKeywords at runtime
    }

    func keywords(for category: TransactionCategory) -> [String] {
        rules[category.rawValue] ?? defaultKeywords[category.rawValue] ?? []
    }

    func setKeywords(_ keywords: [String], for category: TransactionCategory) {
        rules[category.rawValue] = keywords
        save()
    }
}

// MARK: - Anthropic API response model

private struct AnthropicResponse: Decodable {
    struct Content: Decodable {
        let text: String
    }
    let content: [Content]
}
