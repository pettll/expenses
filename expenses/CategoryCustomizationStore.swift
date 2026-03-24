import Foundation
import Combine

// MARK: - Custom category

struct CustomCategory: Codable, Identifiable {
    let id: String
    var name: String
}

// MARK: - Category selection (standard enum case or user-created custom category)

enum CategorySelection: Hashable, Identifiable {
    case standard(TransactionCategory)
    case custom(id: String, name: String)

    var id: String {
        switch self {
        case .standard(let cat): return "std_\(cat.rawValue)"
        case .custom(let id, _): return "cus_\(id)"
        }
    }
}

// MARK: - Store

@MainActor
final class CategoryCustomizationStore: ObservableObject {
    private let overridesKey  = "category_display_names"
    private let customCatsKey = "custom_categories"

    @Published private(set) var overrides: [String: String] = [:]
    @Published private(set) var customCategories: [CustomCategory] = []

    init() {
        if let saved = UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: String] {
            overrides = saved
        }
        if let data = UserDefaults.standard.data(forKey: customCatsKey),
           let decoded = try? JSONDecoder().decode([CustomCategory].self, from: data) {
            customCategories = decoded
        }
    }

    // MARK: Standard category display names

    func displayName(for category: TransactionCategory) -> String {
        overrides[category.rawValue] ?? category.rawValue
    }

    func setDisplayName(_ name: String, for category: TransactionCategory) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == category.rawValue {
            overrides.removeValue(forKey: category.rawValue)
        } else {
            overrides[category.rawValue] = trimmed
        }
        UserDefaults.standard.set(overrides, forKey: overridesKey)
    }

    func clearDisplayName(for category: TransactionCategory) {
        overrides.removeValue(forKey: category.rawValue)
        UserDefaults.standard.set(overrides, forKey: overridesKey)
    }

    // MARK: Custom categories

    @discardableResult
    func addCustomCategory(name: String) -> CustomCategory? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let custom = CustomCategory(id: UUID().uuidString, name: trimmed)
        customCategories.append(custom)
        saveCustomCategories()
        return custom
    }

    func removeCustomCategory(id: String) {
        customCategories.removeAll { $0.id == id }
        saveCustomCategories()
    }

    func renameCustomCategory(id: String, to name: String) {
        guard let idx = customCategories.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        customCategories[idx].name = trimmed
        saveCustomCategories()
    }

    private func saveCustomCategories() {
        if let data = try? JSONEncoder().encode(customCategories) {
            UserDefaults.standard.set(data, forKey: customCatsKey)
        }
    }

    // MARK: CategorySelection helpers

    /// All categories a user can assign to a transaction (standard + custom), excluding .unknown.
    func allAssignableSelections() -> [CategorySelection] {
        let standard = TransactionCategory.allCases
            .filter { $0 != .unknown }
            .map { CategorySelection.standard($0) }
        let custom = customCategories.map { CategorySelection.custom(id: $0.id, name: $0.name) }
        return standard + custom
    }

    func displayName(for selection: CategorySelection) -> String {
        switch selection {
        case .standard(let cat): return displayName(for: cat)
        case .custom(_, let name): return name
        }
    }

    /// Returns the `CategorySelection` that represents a transaction's current category.
    func selection(for transaction: Transaction) -> CategorySelection {
        if let key = transaction.customCategoryKey,
           let custom = customCategories.first(where: { $0.id == key }) {
            return .custom(id: custom.id, name: custom.name)
        }
        return .standard(transaction.category)
    }

    /// Applies a `CategorySelection` to a transaction (sets both `category` and `customCategoryKey`).
    func apply(_ selection: CategorySelection, to transaction: Transaction) {
        switch selection {
        case .standard(let cat):
            transaction.category = cat
            transaction.customCategoryKey = nil
        case .custom(let id, _):
            transaction.category = .other
            transaction.customCategoryKey = id
        }
    }

    /// Effective display name for a transaction, accounting for custom categories and display name overrides.
    func effectiveCategoryName(for transaction: Transaction) -> String {
        if let key = transaction.customCategoryKey,
           let custom = customCategories.first(where: { $0.id == key }) {
            return custom.name
        }
        return displayName(for: transaction.category)
    }
}
