import SwiftUI
import SwiftData
import WidgetKit

// MARK: - Root

struct ContentView: View {
    @StateObject private var categoryService = CategoryService()
    @StateObject private var sheetsService  = SheetsService()
    @Query private var allTransactions: [Transaction]

    var needsReviewCount: Int {
        allTransactions.filter { $0.category == .unknown || $0.category == .other }.count
    }

    var body: some View {
        TabView {
            TransactionListView(categoryService: categoryService, sheetsService: sheetsService)
                .tabItem { Label("Expenses", systemImage: "creditcard.fill") }

            NeedsReviewView(categoryService: categoryService)
                .tabItem { Label("Review", systemImage: "questionmark.circle.fill") }
                .badge(needsReviewCount > 0 ? needsReviewCount : 0)

            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.bar.fill") }

            SettingsView(sheetsService: sheetsService, categoryService: categoryService)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.cyan)
    }
}

// MARK: - Transaction List

struct TransactionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.timestamp, order: .reverse) private var transactions: [Transaction]

    let categoryService: CategoryService
    let sheetsService: SheetsService

    @State private var showingAdd    = false
    @State private var isSyncing     = false
    @State private var selected: Transaction?

    var thisMonthTotal: Double {
        let cal = Calendar.current
        let now = Date()
        return transactions
            .filter { cal.isDate($0.timestamp, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Expenses")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text("This month")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                    Text("£\(thisMonthTotal, specifier: "%.2f")")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.spring, value: thisMonthTotal)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 20)

                if sheetsService.isConfigured {
                    Button { syncAll() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isSyncing ? "arrow.triangle.2.circlepath" : "checkmark.icloud")
                            Text(isSyncing ? "Syncing…" : "Sync all")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.15), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .disabled(isSyncing)
                }

                if transactions.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "creditcard")
                            .font(.system(size: 52))
                            .foregroundStyle(.white.opacity(0.25))
                        Text("No transactions yet")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.45))
                        Text("Tap + to add your first expense")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(transactions) { tx in
                            TransactionRow(transaction: tx, onTap: { selected = tx })
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        }
                        // Bottom padding row so content clears the FAB
                        Color.clear.frame(height: 80)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                }
            }

            // Floating add button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .frame(width: 62, height: 62)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
                            .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 32)
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddTransactionSheet(categoryService: categoryService, sheetsService: sheetsService)
        }
        .sheet(item: $selected) { tx in
            TransactionDetailSheet(transaction: tx, sheetsService: sheetsService)
        }
        .onChange(of: transactions) { _, _ in
            writeWidgetSummary()
        }
        .onAppear {
            writeWidgetSummary()
        }
        .onOpenURL { url in
            if url.scheme == "expenses" {
                if url.host == "add" { showingAdd = true }
                if url.host == "sync" { syncAll() }
            }
        }
    }

    private func syncAll() {
        isSyncing = true
        Task {
            await sheetsService.retryFailed(transactions: transactions)
            isSyncing = false
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func writeWidgetSummary() {
        let cal = Calendar.current
        let now = Date()
        let daily   = transactions.filter { cal.isDateInToday($0.timestamp) }.reduce(0) { $0 + $1.amount }
        let monthly = transactions.filter { cal.isDate($0.timestamp, equalTo: now, toGranularity: .month) }.reduce(0) { $0 + $1.amount }
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID)
        defaults?.set(daily,   forKey: "widgetDailyTotal")
        defaults?.set(monthly, forKey: "widgetMonthlyTotal")
        defaults?.set(Date(),  forKey: "widgetLastUpdated")
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Transaction Row (handles swipe + per-row confirm dialog)

struct TransactionRow: View {
    @Environment(\.modelContext) private var modelContext
    let transaction: Transaction
    let onTap: () -> Void

    @State private var confirmDelete = false

    var body: some View {
        TransactionCard(transaction: transaction)
            .onTapGesture { onTap() }
            .swipeActions(edge: .trailing, allowsFullSwipe: !transaction.syncedToSheets) {
                if transaction.syncedToSheets {
                    Button {
                        confirmDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                } else {
                    Button(role: .destructive) {
                        modelContext.delete(transaction)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .confirmationDialog(
                "Delete \"\(transaction.merchant)\"?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { modelContext.delete(transaction) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This has already been synced to Google Sheets. Deleting here won't remove it from the spreadsheet.")
            }
    }
}

// MARK: - Transaction Card

struct TransactionCard: View {
    let transaction: Transaction

    var categoryColor: Color {
        switch transaction.category {
        case .foodAndDrink:      return .orange
        case .transport:         return .blue
        case .shopping:          return .pink
        case .entertainment:     return .purple
        case .health:            return .green
        case .travel:            return .cyan
        case .billsAndUtilities: return .yellow
        default:                 return Color(white: 0.55)
        }
    }

    var categoryIcon: String {
        switch transaction.category {
        case .foodAndDrink:      return "fork.knife"
        case .transport:         return "car.fill"
        case .shopping:          return "bag.fill"
        case .entertainment:     return "popcorn.fill"
        case .health:            return "heart.fill"
        case .travel:            return "airplane"
        case .billsAndUtilities: return "bolt.fill"
        default:                 return "creditcard.fill"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.18))
                    .frame(width: 48, height: 48)
                Image(systemName: categoryIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(categoryColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.merchant)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(transaction.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(transaction.formattedAmount)
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                HStack(spacing: 4) {
                    Text(transaction.formattedDate)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.38))
                    if !transaction.syncedToSheets {
                        Image(systemName: "icloud.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange.opacity(0.85))
                    }
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 1))
    }
}

// MARK: - Transaction Detail Sheet

struct TransactionDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let transaction: Transaction
    let sheetsService: SheetsService

    @State private var isSyncing        = false
    @State private var syncError: String?
    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 24) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 12)

                VStack(spacing: 6) {
                    Text(transaction.formattedAmount)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(transaction.merchant)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.top, 8)

                VStack(spacing: 0) {
                    DetailRow(label: "Category", value: transaction.category.rawValue)
                    GlassDivider()
                    DetailRow(label: "Source",   value: transaction.source.rawValue.capitalized)
                    GlassDivider()
                    DetailRow(label: "Date",     value: transaction.formattedDate)
                    GlassDivider()
                    DetailRow(label: "Currency", value: transaction.currency)
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 1))
                .padding(.horizontal, 20)

                HStack(spacing: 10) {
                    Image(systemName: transaction.syncedToSheets ? "checkmark.icloud.fill" : "icloud.slash.fill")
                        .font(.title3)
                        .foregroundStyle(transaction.syncedToSheets ? .green : .orange)
                    Text(transaction.syncedToSheets ? "Synced to Sheets" : "Not synced")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    if !transaction.syncedToSheets && sheetsService.isConfigured {
                        Button(isSyncing ? "Syncing…" : "Retry") { retrySingle() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.cyan)
                            .disabled(isSyncing)
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 1))
                .padding(.horizontal, 20)

                if let err = syncError {
                    Text(err).font(.caption).foregroundStyle(.red.opacity(0.9)).padding(.horizontal, 20)
                }

                // Delete — only shown once synced, so data is safe
                if transaction.syncedToSheets {
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                            Text("Delete (synced to Sheets)")
                        }
                        .font(.body.weight(.medium))
                        .foregroundStyle(.red.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.red.opacity(0.2), lineWidth: 1))
                    }
                    .padding(.horizontal, 20)
                }

                Spacer()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .confirmationDialog(
            "Delete this transaction?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let tx = transaction
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    modelContext.delete(tx)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This has already been synced to Google Sheets. Deleting here won't remove it from the spreadsheet.")
        }
    }

    private func retrySingle() {
        isSyncing = true
        Task {
            do {
                try await sheetsService.send(transaction: transaction)
            } catch {
                syncError = error.localizedDescription
                transaction.syncError = error.localizedDescription
            }
            isSyncing = false
        }
    }
}

// MARK: - Add Transaction Sheet

struct AddTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let categoryService: CategoryService
    let sheetsService: SheetsService

    @State private var merchant     = ""
    @State private var amountText   = ""
    @State private var currency     = "GBP"
    @State private var category: TransactionCategory = .unknown
    @State private var isCategorising = false
    @FocusState private var focused: AddField?

    enum AddField { case merchant, amount }

    let currencies = ["GBP", "USD", "EUR", "BRL", "JPY", "INR"]
    var canSave: Bool { !merchant.isEmpty && !amountText.isEmpty }

    var body: some View {
        ZStack {
            AppBackground()
                .onTapGesture { focused = nil }

            VStack(spacing: 0) {
                VStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.3))
                        .frame(width: 36, height: 5)
                    Text("New Expense")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                .padding(.top, 16)
                .padding(.bottom, 28)

                ScrollView {
                    VStack(spacing: 16) {
                        GlassSection(title: "TRANSACTION") {
                            TextField("Merchant", text: $merchant)
                                .foregroundStyle(.white).tint(.cyan)
                                .focused($focused, equals: .merchant)
                                .padding(.horizontal, 16).padding(.vertical, 14)
                                .onChange(of: merchant) { _, newValue in
                                    let local = categoryService.localCategorise(merchant: newValue)
                                    if local != .unknown {
                                        withAnimation { category = local }
                                    } else if newValue.isEmpty {
                                        withAnimation { category = .unknown }
                                    }
                                }
                            GlassDivider()
                            HStack(spacing: 0) {
                                TextField("Amount", text: $amountText)
                                    .foregroundStyle(.white).tint(.cyan)
                                    .keyboardType(.decimalPad)
                                    .focused($focused, equals: .amount)
                                    .padding(.horizontal, 16).padding(.vertical, 14)
                                Picker("", selection: $currency) {
                                    ForEach(currencies, id: \.self) { Text($0).foregroundStyle(.white) }
                                }
                                .tint(.cyan).frame(width: 90).padding(.trailing, 8)
                            }
                        }

                        GlassSection(title: "CATEGORY") {
                            HStack {
                                Text("Category").font(.body).foregroundStyle(.white.opacity(0.75))
                                Spacer()
                                Picker("", selection: $category) {
                                    ForEach(TransactionCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                }
                                .tint(.cyan)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            GlassDivider()
                            Button { autocategorise() } label: {
                                HStack {
                                    Image(systemName: "sparkles")
                                    Text(isCategorising ? "Categorising…" : "Auto-categorise with AI")
                                    Spacer()
                                    if isCategorising { ProgressView().tint(.cyan) }
                                }
                                .font(.body.weight(.medium))
                                .foregroundStyle(merchant.isEmpty || isCategorising ? .white.opacity(0.3) : .cyan)
                                .padding(.horizontal, 16).padding(.vertical, 13)
                            }
                            .disabled(merchant.isEmpty || isCategorising)
                        }

                        Button { save() } label: {
                            Text("Save Expense")
                                .font(.body.bold())
                                .foregroundStyle(canSave ? .black : .white.opacity(0.3))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    canSave ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.1)),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                )
                        }
                        .disabled(!canSave)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .presentationDetents([.large])
        .presentationBackground(.ultraThinMaterial)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }.foregroundStyle(.cyan)
            }
        }
    }

    private func autocategorise() {
        isCategorising = true
        Task {
            category = await categoryService.categorise(merchant: merchant)
            isCategorising = false
        }
    }

    private func save() {
        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) else { return }
        let tx = Transaction(
            amount: amount, currency: currency,
            merchant: merchant.trimmingCharacters(in: .whitespaces),
            category: category, source: .manual
        )
        modelContext.insert(tx)
        if sheetsService.isConfigured { Task { try? await sheetsService.send(transaction: tx) } }
        dismiss()
    }
}

// MARK: - Shared design components

struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.02, blue: 0.18)
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.16, green: 0.05, blue: 0.46), location: 0),
                    .init(color: Color(red: 0.0,  green: 0.14, blue: 0.44), location: 0.55),
                    .init(color: Color(red: 0.0,  green: 0.28, blue: 0.38), location: 1)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct GlassSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.42))
                .padding(.leading, 4)
            VStack(spacing: 0) { content }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 1))
        }
    }
}

struct GlassField: View {
    let placeholder: String
    @Binding var text: String
    var body: some View {
        TextField(placeholder, text: $text)
            .foregroundStyle(.white).tint(.cyan)
            .padding(.horizontal, 16).padding(.vertical, 14)
    }
}

struct GlassDivider: View {
    var body: some View {
        Rectangle().fill(.white.opacity(0.07)).frame(height: 1).padding(.leading, 16)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(.white)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }
}

// MARK: - App-wide constants

enum AppConstants {
    static let appGroupID = "group.com.psmuller.expenses"
    static let urlScheme  = "expenses"
}

#Preview {
    ContentView().modelContainer(for: Transaction.self, inMemory: true)
}
