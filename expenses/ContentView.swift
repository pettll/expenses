import SwiftUI
import SwiftData
import WidgetKit

// MARK: - Root

struct ContentView: View {
    @StateObject private var categoryService     = CategoryService()
    @StateObject private var sheetsService       = SheetsService()
    @StateObject private var categoryStore       = CategoryCustomizationStore()
    @StateObject private var exchangeRateService = ExchangeRateService()
    @StateObject private var notificationParser    = NotificationParser()
    @Query private var allTransactions: [Transaction]

    var needsReviewCount: Int {
        allTransactions.filter {
            ($0.category == .unknown || $0.category == .other) && $0.customCategoryKey == nil
        }.count
    }

    var body: some View {
        TabView {
            TransactionListView(categoryService: categoryService, sheetsService: sheetsService, exchangeRateService: exchangeRateService, notificationParser: notificationParser)
                .tabItem { Label("Expenses", systemImage: "creditcard.fill") }

            NeedsReviewView(categoryService: categoryService, sheetsService: sheetsService, notificationParser: notificationParser)
                .tabItem { Label("Review", systemImage: "questionmark.circle.fill") }
                .badge(needsReviewCount > 0 ? needsReviewCount : 0)

            InsightsView(exchangeRateService: exchangeRateService)
                .tabItem { Label("Insights", systemImage: "chart.bar.fill") }

            SettingsView(sheetsService: sheetsService, categoryService: categoryService)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.white)
        .tabBarMinimizeBehavior(.onScrollDown)
        .environmentObject(categoryStore)
        .task { sheetsService.categoryStore = categoryStore }
    }
}

// MARK: - Sort option

enum SortOption: CaseIterable, Hashable {
    case dateNewest, dateOldest, amountHigh, amountLow, byCategory

    var shortLabel: String {
        switch self {
        case .dateNewest: return "Date ↓"
        case .dateOldest: return "Date ↑"
        case .amountHigh: return "Amount ↓"
        case .amountLow:  return "Amount ↑"
        case .byCategory: return "Category"
        }
    }
    var menuLabel: String {
        switch self {
        case .dateNewest: return "Newest First"
        case .dateOldest: return "Oldest First"
        case .amountHigh: return "Highest Amount"
        case .amountLow:  return "Lowest Amount"
        case .byCategory: return "Category A–Z"
        }
    }
}

// MARK: - Transaction List

struct TransactionListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var categoryStore: CategoryCustomizationStore
    @Query(sort: \Transaction.timestamp, order: .reverse) private var transactions: [Transaction]

    let categoryService: CategoryService
    let sheetsService: SheetsService
    let exchangeRateService: ExchangeRateService
    let notificationParser: NotificationParser

    @State private var showingAdd      = false
    @State private var isSyncing       = false
    @State private var isImporting     = false
    @State private var importError: String?
    @State private var selected: Transaction?
    @State private var sortOption: SortOption = .dateNewest
    @State private var filterMonth: Date? = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    )
    @State private var filterSelection: CategorySelection?
    @State private var filterSource: TransactionSource?
    @AppStorage("mainCurrency") private var mainCurrency = "GBP"
    @State private var mainTotal: Double = 0
    @State private var convertedAmounts: [UUID: Double] = [:]

    // MARK: Computed

    var availableMonths: [Date] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        var seen: Set<String> = []
        var months: [Date] = []
        for tx in transactions {
            let key = fmt.string(from: tx.timestamp)
            if seen.insert(key).inserted {
                let comps = cal.dateComponents([.year, .month], from: tx.timestamp)
                if let date = cal.date(from: comps) { months.append(date) }
            }
        }
        return months.sorted(by: >)
    }

    var displayedTransactions: [Transaction] {
        let cal = Calendar.current
        var result = transactions
        if let month = filterMonth {
            result = result.filter { cal.isDate($0.timestamp, equalTo: month, toGranularity: .month) }
        }
        if let sel = filterSelection {
            switch sel {
            case .standard(let cat):
                result = result.filter { $0.category == cat && $0.customCategoryKey == nil }
            case .custom(let id, _):
                result = result.filter { $0.customCategoryKey == id }
            }
        }
        if let src = filterSource {
            result = result.filter { $0.source == src }
        }
        switch sortOption {
        case .dateNewest: result.sort { $0.timestamp > $1.timestamp }
        case .dateOldest: result.sort { $0.timestamp < $1.timestamp }
        case .amountHigh: result.sort { (convertedAmounts[$0.id] ?? $0.amount) > (convertedAmounts[$1.id] ?? $1.amount) }
        case .amountLow:  result.sort { (convertedAmounts[$0.id] ?? $0.amount) < (convertedAmounts[$1.id] ?? $1.amount) }
        case .byCategory: result.sort { $0.category.rawValue < $1.category.rawValue }
        }
        return result
    }

    var headerLabel: String {
        var parts: [String] = []
        if let month = filterMonth {
            let isCurrentMonth = Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month)
            if isCurrentMonth {
                parts.append("This month")
            } else {
                let fmt = DateFormatter()
                fmt.dateFormat = "MMMM yyyy"
                parts.append(fmt.string(from: month))
            }
        } else {
            parts.append("All time")
        }
        if let sel = filterSelection {
            parts.append(categoryStore.displayName(for: sel))
        }
        if let src = filterSource {
            parts.append(src.displayName)
        }
        return parts.joined(separator: " · ")
    }

    private var totalTaskKey: String {
        let ids = displayedTransactions.map { $0.id.uuidString }.joined()
        return "\(ids.hashValue)_\(mainCurrency)"
    }

    private func computeMainTotals() async {
        // Stage 1: show same-currency amounts immediately; foreign show as original until converted
        let txs = displayedTransactions
        var sameMap: [UUID: Double] = [:]
        var sameTotal = 0.0
        for tx in txs where tx.currency.uppercased() == mainCurrency.uppercased() {
            sameMap[tx.id] = tx.amount
            sameTotal += tx.amount
        }
        convertedAmounts = sameMap
        mainTotal = sameTotal
        // Stage 2: refine with currency conversion
        var converted: [UUID: Double] = [:]
        var total = 0.0
        for tx in txs {
            guard !Task.isCancelled else { return }
            if let v = await exchangeRateService.convert(amount: tx.amount, from: tx.currency, date: tx.timestamp) {
                converted[tx.id] = v
                total += v
            } else {
                total += tx.amount  // best estimate for total when rate unavailable
            }
        }
        guard !Task.isCancelled else { return }
        convertedAmounts = converted
        mainTotal = total
    }

    // MARK: Body

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Expenses")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                        Text(headerLabel)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.55))
                        Text(formatAmount(mainTotal, currency: mainCurrency))
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.spring, value: mainTotal)
                    }
                    Spacer()
                    if sheetsService.isConfigured {
                        VStack(alignment: .trailing, spacing: 6) {
                            HStack(spacing: 18) {
                                Button { Task { await importFromSheets() } } label: {
                                    Image(systemName: isImporting ? "arrow.down.circle.fill" : "arrow.down.circle")
                                        .font(.title3.weight(.medium))
                                        .foregroundStyle(isImporting ? .appAccent.opacity(0.5) : .appAccent)
                                }
                                .disabled(isImporting || isSyncing)

                                Button { syncAll() } label: {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.title3.weight(.medium))
                                        .foregroundStyle(isSyncing ? .appAccent.opacity(0.5) : .appAccent)
                                }
                                .disabled(isSyncing || isImporting)
                            }
                            if let err = importError {
                                Text(err)
                                    .font(.caption2)
                                    .foregroundStyle(.red.opacity(0.8))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 140)
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

                // Filter / sort bar
                if !transactions.isEmpty {
                    filterSortBar
                        .padding(.bottom, 12)
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
                } else if displayedTransactions.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 52))
                            .foregroundStyle(.white.opacity(0.25))
                        Text("No matching transactions")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.45))
                        Button("Clear filters") {
                            filterMonth = Calendar.current.date(
                                from: Calendar.current.dateComponents([.year, .month], from: Date())
                            )
                            filterSelection = nil
                            filterSource = nil
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.appAccent)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(displayedTransactions) { tx in
                            TransactionRow(
                                transaction: tx,
                                sheetsService: sheetsService,
                                convertedAmount: convertedAmounts[tx.id],
                                mainCurrency: mainCurrency,
                                onTap: { selected = tx }
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        }
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
                    GlassEffectContainer {
                        Button { showingAdd = true } label: {
                            Image(systemName: "plus")
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                                .frame(width: 62, height: 62)
                        }
                        .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
                    .padding(.trailing, 24)
                    .padding(.bottom, 32)
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddTransactionSheet(categoryService: categoryService, sheetsService: sheetsService)
        }
        .sheet(item: $selected) { tx in
            TransactionDetailSheet(
                transaction: tx,
                sheetsService: sheetsService,
                categoryService: categoryService
            )
        }
        .onChange(of: transactions) { _, _ in writeWidgetSummary() }
        .onAppear { writeWidgetSummary() }
        .task(id: totalTaskKey) { await computeMainTotals() }
        .onOpenURL { url in
            if url.scheme == "expenses" {
                if url.host == "add" { showingAdd = true }
                if url.host == "sync" { syncAll() }
                if url.host == "parse" {
                    let comps    = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    let title    = comps?.queryItems?.first { $0.name == "title" }?.value ?? ""
                    let body     = comps?.queryItems?.first { $0.name == "body" }?.value ?? ""
                    let bundleId = comps?.queryItems?.first { $0.name == "bundleId" }?.value
                    if let parsed = notificationParser.parse(title: title, body: body, bundleIdentifier: bundleId) {
                        let cat = categoryService.localCategorise(merchant: parsed.merchant)
                        let tx = Transaction(
                            amount: parsed.amount,
                            currency: parsed.currency,
                            merchant: parsed.merchant,
                            category: cat,
                            source: .shortcut,
                            rawNotificationText: parsed.rawText
                        )
                        modelContext.insert(tx)
                        if sheetsService.isConfigured {
                            Task { try? await sheetsService.send(transaction: tx) }
                        }
                    }
                }
                if url.host == "record" {
                    // Direct params — no notification parsing needed.
                    // expenses://record?merchant=Costa&amount=4.50&currency=GBP&category=dining
                    let comps     = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    let merchant  = comps?.queryItems?.first { $0.name == "merchant" }?.value ?? ""
                    let amountStr = comps?.queryItems?.first { $0.name == "amount" }?.value ?? ""
                    let currency  = comps?.queryItems?.first { $0.name == "currency" }?.value ?? "GBP"
                    let catStr    = comps?.queryItems?.first { $0.name == "category" }?.value
                    guard !merchant.isEmpty, let amount = Double(amountStr) else { return }
                    let cat = catStr.flatMap { s in TransactionCategory.allCases.first { $0.rawValue == s } }
                              ?? categoryService.localCategorise(merchant: merchant)
                    let tx = Transaction(
                        amount: amount,
                        currency: currency,
                        merchant: merchant,
                        category: cat,
                        source: .shortcut
                    )
                    modelContext.insert(tx)
                    if sheetsService.isConfigured {
                        Task { try? await sheetsService.send(transaction: tx) }
                    }
                }
            }
        }
    }

    // MARK: Filter / sort bar

    @ViewBuilder
    private var filterSortBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Sort
                Menu {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Button {
                            sortOption = option
                        } label: {
                            if sortOption == option {
                                Label(option.menuLabel, systemImage: "checkmark")
                            } else {
                                Text(option.menuLabel)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption.weight(.bold))
                        Text(sortOption.shortLabel)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                }
                .glassEffect(.regular.interactive(), in: .capsule)

                // Month filter
                Menu {
                    Button {
                        filterMonth = nil
                    } label: {
                        if filterMonth == nil {
                            Label("All time", systemImage: "checkmark")
                        } else {
                            Text("All time")
                        }
                    }
                    if !availableMonths.isEmpty { Divider() }
                    ForEach(availableMonths, id: \.self) { month in
                        Button {
                            filterMonth = month
                        } label: {
                            let isSelected = filterMonth.map {
                                Calendar.current.isDate($0, equalTo: month, toGranularity: .month)
                            } ?? false
                            if isSelected {
                                Label(shortMonthLabel(month), systemImage: "checkmark")
                            } else {
                                Text(shortMonthLabel(month))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption.weight(.bold))
                        Text(filterMonth.map { shortMonthLabel($0) } ?? "All Time")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                }
                .glassEffect(
                    filterMonth != nil
                        ? .regular.tint(.appAccent).interactive()
                        : .regular.interactive(),
                    in: .capsule
                )

                // Category filter
                Menu {
                    Button {
                        filterSelection = nil
                    } label: {
                        if filterSelection == nil {
                            Label("All Categories", systemImage: "checkmark")
                        } else {
                            Text("All Categories")
                        }
                    }
                    Divider()
                    ForEach(categoryStore.allAssignableSelections()) { sel in
                        Button {
                            filterSelection = sel
                        } label: {
                            if filterSelection == sel {
                                Label(categoryStore.displayName(for: sel), systemImage: "checkmark")
                            } else {
                                Text(categoryStore.displayName(for: sel))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "tag")
                            .font(.caption.weight(.bold))
                        Text(filterSelection.map { categoryStore.displayName(for: $0) } ?? "Category")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                }
                .glassEffect(
                    filterSelection != nil
                        ? .regular.tint(.appAccent).interactive()
                        : .regular.interactive(),
                    in: .capsule
                )

                // Source filter
                Menu {
                    Button {
                        filterSource = nil
                    } label: {
                        if filterSource == nil {
                            Label("All Sources", systemImage: "checkmark")
                        } else {
                            Text("All Sources")
                        }
                    }
                    Divider()
                    ForEach(TransactionSource.allCases, id: \.self) { src in
                        Button {
                            filterSource = src
                        } label: {
                            if filterSource == src {
                                Label(src.displayName, systemImage: "checkmark")
                            } else {
                                Text(src.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack")
                            .font(.caption.weight(.bold))
                        Text(filterSource?.displayName ?? "Source")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                }
                .glassEffect(
                    filterSource != nil
                        ? .regular.tint(.appAccent).interactive()
                        : .regular.interactive(),
                    in: .capsule
                )
            }
            .padding(.horizontal, 24)
        }
    }

    private func shortMonthLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM yyyy"
        return fmt.string(from: date)
    }

    // MARK: Actions

    private func importFromSheets() async {
        isImporting = true
        importError = nil
        do {
            let rows = try await sheetsService.fetchRows()
            let existingIds = Set(transactions.map { $0.id.uuidString })

            // Date parsers in priority order — the script now always emits ISO UTC,
            // but we keep fallbacks for any legacy text-stored cells.
            let isoParserFrac = ISO8601DateFormatter()
            isoParserFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoParser = ISO8601DateFormatter()
            isoParser.formatOptions = [.withInternetDateTime]

            func makeDF(_ fmt: String) -> DateFormatter {
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(identifier: "Europe/London")
                df.dateFormat = fmt
                return df
            }
            // Accept both zero-padded and single-digit day/month
            let parsers = [
                makeDF("dd/MM/yyyy HH:mm:ss"),
                makeDF("d/M/yyyy HH:mm:ss"),
                makeDF("dd/MM/yyyy"),
                makeDF("d/M/yyyy")
            ]

            for row in rows {
                if !row.txId.isEmpty && existingIds.contains(row.txId) { continue }
                guard let amount = Double(row.amount.replacingOccurrences(of: ",", with: ".")) else { continue }
                let category = TransactionCategory.allCases.first { $0.rawValue == row.category } ?? .other
                let timestamp = isoParserFrac.date(from: row.date)
                    ?? isoParser.date(from: row.date)
                    ?? parsers.lazy.compactMap({ $0.date(from: row.date) }).first
                    ?? Date()
                let newId = UUID(uuidString: row.txId) ?? UUID()
                let tx = Transaction(
                    id: newId,
                    timestamp: timestamp,
                    amount: amount,
                    currency: row.currency.isEmpty ? "GBP" : row.currency,
                    merchant: row.name,
                    category: category,
                    source: .sheetsSync
                )
                tx.syncedToSheets = true
                modelContext.insert(tx)

                // Row had no ID — write the new UUID back to the sheet so it
                // won't be duplicated on the next import.
                if row.txId.isEmpty, let rowIndex = row.rowIndex {
                    let idString = newId.uuidString
                    Task { try? await sheetsService.patchTxId(rowIndex: rowIndex, txId: idString) }
                }
            }
            try? modelContext.save()
        } catch {
            importError = error.localizedDescription
        }
        isImporting = false
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
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        defaults.set(daily,   forKey: "widgetDailyTotal")
        defaults.set(monthly, forKey: "widgetMonthlyTotal")
        defaults.set(Date(),  forKey: "widgetLastUpdated")
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Transaction Row

struct TransactionRow: View {
    @Environment(\.modelContext) private var modelContext
    let transaction: Transaction
    let sheetsService: SheetsService
    let convertedAmount: Double?
    let mainCurrency: String
    let onTap: () -> Void

    @State private var confirmDelete = false

    var body: some View {
        TransactionCard(transaction: transaction, convertedAmount: convertedAmount, mainCurrency: mainCurrency)
            .onTapGesture { onTap() }
            .swipeActions(edge: .trailing, allowsFullSwipe: !transaction.syncedToSheets) {
                if transaction.syncedToSheets {
                    Button { confirmDelete = true } label: {
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
                Button("Delete from app and Sheets", role: .destructive) {
                    let tx = transaction
                    Task { try? await sheetsService.deleteFromSheet(transaction: tx) }
                    modelContext.delete(transaction)
                }
                Button("Delete from app only", role: .destructive) {
                    modelContext.delete(transaction)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This transaction has been synced to Google Sheets.")
            }
    }
}

// MARK: - Transaction Card

struct TransactionCard: View {
    @EnvironmentObject private var categoryStore: CategoryCustomizationStore
    let transaction: Transaction
    let convertedAmount: Double?
    let mainCurrency: String

    var categoryColor: Color {
        guard transaction.customCategoryKey == nil else { return Color(red: 0.4, green: 0.6, blue: 0.7) }
        return expenses.categoryColor(transaction.category)
    }

    var categoryIcon: String {
        guard transaction.customCategoryKey == nil else { return "tag.fill" }
        switch transaction.category {
        case .alcohol:       return "wineglass.fill"
        case .bills:         return "bolt.fill"
        case .clothes:       return "tshirt.fill"
        case .coffee:        return "cup.and.saucer.fill"
        case .diningOut:     return "fork.knife"
        case .entertainment: return "popcorn.fill"
        case .gifts:         return "gift.fill"
        case .groceries:     return "cart.fill"
        case .health:        return "heart.fill"
        case .study:         return "book.fill"
        case .toiletries:    return "house.fill"
        case .transport:     return "car.fill"
        case .trips:         return "airplane"
        default:             return "creditcard.fill"
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
                Text(categoryStore.effectiveCategoryName(for: transaction))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let converted = convertedAmount {
                    Text(formatAmount(converted, currency: mainCurrency))
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                    if transaction.currency.uppercased() != mainCurrency.uppercased() {
                        Text(transaction.formattedAmount)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                } else {
                    Text(transaction.formattedAmount)
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                }
                HStack(spacing: 4) {
                    Text(transaction.formattedDate)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.38))
                    if transaction.source == .sheetsSync {
                        Image(systemName: "tablecells.fill")
                            .font(.caption2)
                            .foregroundStyle(.appAccent.opacity(0.7))
                    } else if !transaction.syncedToSheets {
                        Image(systemName: "icloud.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange.opacity(0.85))
                    }
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Transaction Detail Sheet

struct TransactionDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var categoryStore: CategoryCustomizationStore
    let transaction: Transaction
    let sheetsService: SheetsService
    let categoryService: CategoryService

    @State private var isSyncing          = false
    @State private var syncError: String?
    @State private var showDeleteConfirm  = false
    @State private var isEditing          = false

    // Edit fields
    @State private var editMerchant       = ""
    @State private var editAmountText     = ""
    @State private var editCurrency       = "GBP"
    @State private var editCategorySelection: CategorySelection = .standard(.unknown)
    @State private var editDate           = Date()
    @State private var isCategorising     = false
    @FocusState private var editFocused: Bool

    let currencies = ["GBP", "USD", "EUR", "BRL", "JPY", "INR"]

    var body: some View {
        ZStack {
            AppBackground()
                .onTapGesture { editFocused = false }

            VStack(spacing: 0) {
                // Edit / Cancel button row — iOS provides the drag handle automatically
                HStack {
                    Spacer()
                    Button(isEditing ? "Cancel" : "Edit") {
                        isEditing ? (isEditing = false) : startEditing()
                    }
                    .font(.body.weight(.medium))
                    .foregroundStyle(.appAccent)
                    .padding(.trailing, 20)
                }
                .padding(.top, 12)
                .padding(.bottom, 20)

                if isEditing {
                    editForm
                } else {
                    detailView
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .confirmationDialog(
            "Delete \"\(transaction.merchant)\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            if transaction.syncedToSheets {
                Button("Delete from app and Sheets", role: .destructive) {
                    let tx = transaction
                    dismiss()
                    Task { try? await sheetsService.deleteFromSheet(transaction: tx) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { modelContext.delete(tx) }
                }
                Button("Delete from app only", role: .destructive) {
                    let tx = transaction
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { modelContext.delete(tx) }
                }
            } else {
                Button("Delete", role: .destructive) {
                    let tx = transaction
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { modelContext.delete(tx) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(transaction.syncedToSheets
                 ? "This transaction has been synced to Google Sheets."
                 : "This cannot be undone.")
        }
    }

    // MARK: Read-only detail view

    private var detailView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 6) {
                        Text(transaction.formattedAmount)
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(transaction.merchant)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }

                    VStack(spacing: 0) {
                        DetailRow(label: "Category", value: categoryStore.displayName(for: transaction.category))
                        GlassDivider()
                        DetailRow(label: "Source",   value: transaction.source.rawValue.capitalized)
                        GlassDivider()
                        DetailRow(label: "Date",     value: transaction.formattedDate)
                        GlassDivider()
                        DetailRow(label: "Currency", value: transaction.currency)
                    }
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                                .foregroundStyle(.appAccent)
                                .disabled(isSyncing)
                        }
                    }
                    .padding(16)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 20)

                    if let err = syncError {
                        Text(err).font(.caption).foregroundStyle(.red.opacity(0.9)).padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 16)
            }

            // Delete pinned at bottom, outside scroll view
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                    Text("Delete transaction")
                }
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .glassEffect(.regular.tint(.red).interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    // MARK: Edit form

    private var editForm: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassSection(title: "TRANSACTION") {
                    TextField("Merchant", text: $editMerchant)
                        .foregroundStyle(.white).tint(.appAccent)
                        .focused($editFocused)
                        .padding(.horizontal, 16).padding(.vertical, 14)
                    GlassDivider()
                    HStack(spacing: 0) {
                        TextField("Amount", text: $editAmountText)
                            .foregroundStyle(.white).tint(.appAccent)
                            .keyboardType(.decimalPad)
                            .focused($editFocused)
                            .padding(.horizontal, 16).padding(.vertical, 14)
                        Picker("", selection: $editCurrency) {
                            ForEach(currencies, id: \.self) { Text($0).foregroundStyle(.white) }
                        }
                        .tint(.appAccent).frame(width: 90).padding(.trailing, 8)
                    }
                    GlassDivider()
                    DatePicker("Date", selection: $editDate, displayedComponents: [.date, .hourAndMinute])
                        .foregroundStyle(.white)
                        .tint(.appAccent)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .colorScheme(.dark)
                }

                GlassSection(title: "CATEGORY") {
                    HStack {
                        Text("Category").font(.body).foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        Picker("", selection: $editCategorySelection) {
                            ForEach(categoryStore.allAssignableSelections()) { sel in
                                Text(categoryStore.displayName(for: sel)).tag(sel)
                            }
                        }
                        .tint(.appAccent)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    GlassDivider()
                    Button { autocategorise() } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text(isCategorising ? "Categorising…" : "Auto-categorise with AI")
                            Spacer()
                            if isCategorising { ProgressView().tint(.appAccent) }
                        }
                        .font(.body.weight(.medium))
                        .foregroundStyle(editMerchant.isEmpty || isCategorising ? .white.opacity(0.3) : .appAccent)
                        .padding(.horizontal, 16).padding(.vertical, 13)
                    }
                    .disabled(editMerchant.isEmpty || isCategorising)
                }

                Button { saveEdits() } label: {
                    Text("Save Changes")
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editFocused = false }.foregroundStyle(.appAccent)
            }
        }
    }

    private var canSave: Bool { !editMerchant.isEmpty && !editAmountText.isEmpty }

    // MARK: Actions

    private func startEditing() {
        editMerchant   = transaction.merchant
        editAmountText = String(format: "%.2f", transaction.amount)
        editCurrency   = transaction.currency
        editCategorySelection = categoryStore.selection(for: transaction)
        editDate       = transaction.timestamp
        isEditing      = true
    }

    private func saveEdits() {
        guard let amount = Double(editAmountText.replacingOccurrences(of: ",", with: ".")) else { return }
        transaction.merchant  = editMerchant.trimmingCharacters(in: .whitespaces)
        transaction.amount    = amount
        transaction.currency  = editCurrency
        categoryStore.apply(editCategorySelection, to: transaction)
        transaction.timestamp = editDate
        if sheetsService.isConfigured {
            transaction.syncedToSheets = false
            Task { try? await sheetsService.send(transaction: transaction) }
        }
        isEditing = false
    }

    private func autocategorise() {
        isCategorising = true
        Task {
            editCategorySelection = .standard(await categoryService.categorise(merchant: editMerchant))
            isCategorising = false
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

    @EnvironmentObject private var categoryStore: CategoryCustomizationStore

    @State private var merchant         = ""
    @State private var amountText       = ""
    @State private var currency         = "GBP"
    @State private var categorySelection: CategorySelection = .standard(.unknown)
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
                                .foregroundStyle(.white).tint(.appAccent)
                                .focused($focused, equals: .merchant)
                                .padding(.horizontal, 16).padding(.vertical, 14)
                                .onChange(of: merchant) { _, newValue in
                                    let local = categoryService.localCategorise(merchant: newValue)
                                    if local != .unknown {
                                        withAnimation { categorySelection = .standard(local) }
                                    } else if newValue.isEmpty {
                                        withAnimation { categorySelection = .standard(.unknown) }
                                    }
                                }
                            GlassDivider()
                            HStack(spacing: 0) {
                                TextField("Amount", text: $amountText)
                                    .foregroundStyle(.white).tint(.appAccent)
                                    .keyboardType(.decimalPad)
                                    .focused($focused, equals: .amount)
                                    .padding(.horizontal, 16).padding(.vertical, 14)
                                Picker("", selection: $currency) {
                                    ForEach(currencies, id: \.self) { Text($0).foregroundStyle(.white) }
                                }
                                .tint(.appAccent).frame(width: 90).padding(.trailing, 8)
                            }
                        }

                        GlassSection(title: "CATEGORY") {
                            HStack {
                                Text("Category").font(.body).foregroundStyle(.white.opacity(0.75))
                                Spacer()
                                Picker("", selection: $categorySelection) {
                                    ForEach(categoryStore.allAssignableSelections()) { sel in
                                        Text(categoryStore.displayName(for: sel)).tag(sel)
                                    }
                                }
                                .tint(.appAccent)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            GlassDivider()
                            Button { autocategorise() } label: {
                                HStack {
                                    Image(systemName: "sparkles")
                                    Text(isCategorising ? "Categorising…" : "Auto-categorise with AI")
                                    Spacer()
                                    if isCategorising { ProgressView().tint(.appAccent) }
                                }
                                .font(.body.weight(.medium))
                                .foregroundStyle(merchant.isEmpty || isCategorising ? .white.opacity(0.3) : .appAccent)
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
                Button("Done") { focused = nil }.foregroundStyle(.appAccent)
            }
        }
    }

    private func autocategorise() {
        isCategorising = true
        Task {
            categorySelection = .standard(await categoryService.categorise(merchant: merchant))
            isCategorising = false
        }
    }

    private func save() {
        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) else { return }
        let tx = Transaction(
            amount: amount, currency: currency,
            merchant: merchant.trimmingCharacters(in: .whitespaces),
            category: .unknown, source: .manual
        )
        categoryStore.apply(categorySelection, to: tx)
        modelContext.insert(tx)
        if sheetsService.isConfigured { Task { try? await sheetsService.send(transaction: tx) } }
        dismiss()
    }
}

// MARK: - Shared design components

struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.0, blue: 0.12)
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.08, green: 0.04, blue: 0.48), location: 0),
                    .init(color: Color(red: 0.28, green: 0.02, blue: 0.44), location: 0.55),
                    .init(color: Color(red: 0.44, green: 0.00, blue: 0.38), location: 1)
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
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

struct GlassField: View {
    let placeholder: String
    @Binding var text: String
    var body: some View {
        TextField(placeholder, text: $text)
            .foregroundStyle(.white).tint(.appAccent)
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

extension Color {
    /// Brand accent — neon pink matching the logo gradient endpoint.
    static let appAccent = Color(red: 0.98, green: 0.12, blue: 0.87)
}

extension ShapeStyle where Self == Color {
    static var appAccent: Color { .appAccent }
}

#Preview {
    ContentView().modelContainer(for: Transaction.self, inMemory: true)
}
