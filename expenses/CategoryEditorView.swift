import SwiftUI
import SwiftData

struct CategoryEditorView: View {
    @EnvironmentObject private var categoryStore: CategoryCustomizationStore
    @Environment(\.modelContext) private var modelContext
    @Query private var allTransactions: [Transaction]

    let sheetsService: SheetsService

    @State private var standardEdits: [String: String] = [:]  // rawValue → new display name
    @State private var customEdits: [String: String] = [:]    // custom id → new display name
    @State private var isSyncing = false
    @State private var syncedCount = 0
    @State private var isAddingNew = false
    @State private var newCategoryName = ""
    @FocusState private var focusedField: String?

    private let editableStandard = TransactionCategory.allCases.filter { $0 != .unknown }

    var body: some View {
        ZStack {
            AppBackground()
                .onTapGesture { focusedField = nil }

            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Category Names")
                                .font(.largeTitle.bold())
                                .foregroundStyle(.white)
                            Text("Rename, delete, or create categories")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                    }
                    .padding(.top, 20)

                    // Built-in categories
                    GlassSection(title: "BUILT-IN") {
                        ForEach(Array(editableStandard.enumerated()), id: \.element) { idx, cat in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(categoryColor(cat))
                                    .frame(width: 9, height: 9)
                                Text(cat.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.38))
                                    .frame(width: 90, alignment: .leading)
                                Spacer()
                                TextField(
                                    cat.rawValue,
                                    text: Binding(
                                        get: { standardEdits[cat.rawValue] ?? categoryStore.displayName(for: cat) },
                                        set: { standardEdits[cat.rawValue] = $0 }
                                    )
                                )
                                .foregroundStyle(.white)
                                .tint(.appAccent)
                                .multilineTextAlignment(.trailing)
                                .font(.subheadline.weight(.medium))
                                .focused($focusedField, equals: cat.rawValue)

                                if categoryStore.overrides[cat.rawValue] != nil {
                                    Button {
                                        standardEdits.removeValue(forKey: cat.rawValue)
                                        categoryStore.clearDisplayName(for: cat)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white.opacity(0.35))
                                            .font(.body)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            if idx < editableStandard.count - 1 { GlassDivider() }
                        }
                    }

                    // Custom categories
                    if !categoryStore.customCategories.isEmpty || isAddingNew {
                        GlassSection(title: "CUSTOM") {
                            ForEach(Array(categoryStore.customCategories.enumerated()), id: \.element.id) { idx, custom in
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(Color(red: 0.4, green: 0.6, blue: 0.7))
                                        .frame(width: 9, height: 9)
                                    TextField(
                                        custom.name,
                                        text: Binding(
                                            get: { customEdits[custom.id] ?? custom.name },
                                            set: { customEdits[custom.id] = $0 }
                                        )
                                    )
                                    .foregroundStyle(.white)
                                    .tint(.appAccent)
                                    .font(.subheadline.weight(.medium))
                                    .focused($focusedField, equals: custom.id)

                                    Spacer()

                                    Button { deleteCustomCategory(id: custom.id) } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red.opacity(0.7))
                                            .font(.callout)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                                if idx < categoryStore.customCategories.count - 1 || isAddingNew {
                                    GlassDivider()
                                }
                            }

                            if isAddingNew {
                                HStack(spacing: 10) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.appAccent)
                                        .font(.body)
                                    TextField("Category name", text: $newCategoryName)
                                        .foregroundStyle(.white)
                                        .tint(.appAccent)
                                        .font(.subheadline.weight(.medium))
                                        .focused($focusedField, equals: "new")
                                        .onSubmit { confirmNewCategory() }
                                    Spacer()
                                    Button { confirmNewCategory() } label: {
                                        Text("Add")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(
                                                newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty
                                                ? .white.opacity(0.3) : .appAccent
                                            )
                                    }
                                    .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                            }
                        }
                    }

                    // Add category button
                    if !isAddingNew {
                        Button {
                            isAddingNew = true
                            newCategoryName = ""
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                focusedField = "new"
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle").font(.body)
                                Text("Add Category").font(.body.weight(.medium))
                            }
                            .foregroundStyle(.appAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                        }
                        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if isSyncing {
                        HStack(spacing: 8) {
                            ProgressView().tint(.appAccent)
                            Text("Syncing \(syncedCount) transactions…")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if hasChanges {
                        Button { applyChanges() } label: {
                            Text("Save Changes")
                                .font(.body.bold())
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .disabled(isSyncing)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }.foregroundStyle(.appAccent)
            }
        }
    }

    private var hasChanges: Bool { !standardEdits.isEmpty || !customEdits.isEmpty }

    private func confirmNewCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        categoryStore.addCustomCategory(name: trimmed)
        newCategoryName = ""
        isAddingNew = false
        focusedField = nil
    }

    private func deleteCustomCategory(id: String) {
        categoryStore.removeCustomCategory(id: id)
        let affected = allTransactions.filter { $0.customCategoryKey == id }
        for tx in affected {
            tx.customCategoryKey = nil
            tx.category = .other
            tx.syncedToSheets = false
        }
        try? modelContext.save()
        customEdits.removeValue(forKey: id)
    }

    private func applyChanges() {
        var changedStandard: Set<TransactionCategory> = []
        var changedCustomIds: Set<String> = []

        for (rawVal, newName) in standardEdits {
            let trimmed = newName.trimmingCharacters(in: .whitespaces)
            guard let cat = TransactionCategory(rawValue: rawVal), !trimmed.isEmpty else { continue }
            if trimmed != categoryStore.displayName(for: cat) {
                categoryStore.setDisplayName(trimmed, for: cat)
                changedStandard.insert(cat)
            }
        }
        standardEdits.removeAll()

        for (id, newName) in customEdits {
            let trimmed = newName.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let custom = categoryStore.customCategories.first(where: { $0.id == id }),
                  trimmed != custom.name else { continue }
            categoryStore.renameCustomCategory(id: id, to: trimmed)
            changedCustomIds.insert(id)
        }
        customEdits.removeAll()

        guard sheetsService.isConfigured else { return }

        var toSync: [Transaction] = []
        if !changedStandard.isEmpty {
            toSync += allTransactions.filter { changedStandard.contains($0.category) && $0.customCategoryKey == nil }
        }
        if !changedCustomIds.isEmpty {
            toSync += allTransactions.filter { changedCustomIds.contains($0.customCategoryKey ?? "") }
        }
        guard !toSync.isEmpty else { return }

        isSyncing = true
        syncedCount = toSync.count
        Task {
            try? await sheetsService.sendBatch(transactions: toSync)
            isSyncing = false
        }
    }
}
