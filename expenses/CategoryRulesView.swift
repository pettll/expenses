import SwiftUI

// MARK: - Category Rules List

struct CategoryRulesView: View {
    @ObservedObject var categoryService: CategoryService
    @EnvironmentObject private var categoryStore: CategoryCustomizationStore

    private let categories = TransactionCategory.allCases.filter { $0 != .unknown && $0 != .other }

    var body: some View {
        ZStack {
            AppBackground()

            List {
                ForEach(categories, id: \.self) { cat in
                    NavigationLink {
                        CategoryKeywordsView(category: cat, categoryService: categoryService)
                    } label: {
                        HStack {
                            Text(categoryStore.displayName(for: cat))
                                .foregroundStyle(.white)
                            Spacer()
                            let count = categoryService.keywords(for: cat).count
                            Text("\(count) keyword\(count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .padding(.vertical, 2)
                    )
                    .listRowSeparator(.hidden)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Category Rules")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Keywords for a single category

struct CategoryKeywordsView: View {
    let category: TransactionCategory
    @ObservedObject var categoryService: CategoryService
    @EnvironmentObject private var categoryStore: CategoryCustomizationStore

    @State private var newKeyword = ""
    @FocusState private var isEditing: Bool

    var keywords: [String] { categoryService.keywords(for: category) }

    var body: some View {
        ZStack {
            AppBackground()
                .onTapGesture { isEditing = false }

            VStack(spacing: 0) {
                // Add field
                GlassSection(title: "ADD KEYWORD") {
                    HStack(spacing: 8) {
                        TextField("e.g. starbucks, deliveroo…", text: $newKeyword)
                            .foregroundStyle(.white).tint(.appAccent)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($isEditing)
                            .padding(.horizontal, 16).padding(.vertical, 14)
                        Button { addKeyword() } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty ? .white.opacity(0.25) : .appAccent)
                        }
                        .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                        .padding(.trailing, 14)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                if keywords.isEmpty {
                    Spacer()
                    Text("No keywords yet — add one above")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.35))
                    Spacer()
                } else {
                    List {
                        ForEach(keywords, id: \.self) { kw in
                            HStack(spacing: 10) {
                                Image(systemName: "tag").font(.caption).foregroundStyle(.appAccent.opacity(0.7))
                                Text(kw).foregroundStyle(.white)
                            }
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .padding(.vertical, 2)
                            )
                            .listRowSeparator(.hidden)
                        }
                        .onDelete(perform: deleteKeywords)
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                }
            }
        }
        .navigationTitle(categoryStore.displayName(for: category))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isEditing = false }.foregroundStyle(.appAccent)
            }
        }
    }

    private func addKeyword() {
        let kw = newKeyword.lowercased().trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return }
        var kws = categoryService.keywords(for: category)
        guard !kws.contains(kw) else { newKeyword = ""; return }
        kws.append(kw)
        categoryService.setKeywords(kws, for: category)
        newKeyword = ""
    }

    private func deleteKeywords(at offsets: IndexSet) {
        var kws = categoryService.keywords(for: category)
        kws.remove(atOffsets: offsets)
        categoryService.setKeywords(kws, for: category)
    }
}
