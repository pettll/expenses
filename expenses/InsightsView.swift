import SwiftUI
import SwiftData
import Charts

// MARK: - Data helpers

private struct CategoryTotal: Identifiable {
    let key: String   // customCategoryKey for custom, category.rawValue for standard
    let name: String
    let color: Color
    let total: Double
    var id: String { key }
}

private struct TimeBucket: Identifiable {
    let date: Date
    let total: Double
    var id: Date { date }
}

// MARK: - Insights View

struct InsightsView: View {
    @EnvironmentObject private var categoryStore: CategoryCustomizationStore
    @Query(sort: \Transaction.timestamp, order: .reverse) private var all: [Transaction]

    let exchangeRateService: ExchangeRateService

    @AppStorage("mainCurrency") private var mainCurrency = "GBP"
    @State private var rangeStart: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()
    @State private var rangeEnd: Date = Date()
    @State private var selectedCategoryKey: String? = nil
    @State private var selectedBucket: TimeBucket? = nil
    @State private var convertedAmounts: [UUID: Double] = [:]

    // MARK: Derived data

    private var filterRange: ClosedRange<Date> {
        let lo = min(rangeStart, rangeEnd)
        let hi = max(rangeStart, rangeEnd)
        return lo...hi
    }

    private var rangeTaskKey: String {
        "\(filterRange.lowerBound)_\(filterRange.upperBound)_\(mainCurrency)"
    }

    private func computeConvertedAmounts() async {
        let base = all.filter { filterRange.contains($0.timestamp) }
        var result: [UUID: Double] = [:]
        for tx in base {
            guard !Task.isCancelled else { return }
            result[tx.id] = await exchangeRateService.convert(amount: tx.amount, from: tx.currency, date: tx.timestamp) ?? tx.amount
        }
        guard !Task.isCancelled else { return }
        convertedAmounts = result
    }

    private func convertedAmount(for tx: Transaction) -> Double {
        convertedAmounts[tx.id] ?? tx.amount
    }

    private var filtered: [Transaction] {
        let base = all.filter { filterRange.contains($0.timestamp) }
        guard let key = selectedCategoryKey else { return base }
        return base.filter { tx in
            if let ck = tx.customCategoryKey { return ck == key }
            return tx.category.rawValue == key
        }
    }

    private var categoryTotals: [CategoryTotal] {
        let base = all.filter { filterRange.contains($0.timestamp) }
        var groups: [String: (name: String, color: Color, total: Double)] = [:]
        for tx in base {
            let key: String
            let name: String
            let color: Color
            if let ck = tx.customCategoryKey,
               let custom = categoryStore.customCategories.first(where: { $0.id == ck }) {
                key = ck
                name = custom.name
                color = Color(red: 0.4, green: 0.6, blue: 0.7)
            } else {
                key = tx.category.rawValue
                name = categoryStore.displayName(for: tx.category)
                color = categoryColor(tx.category)
            }
            let existing = groups[key] ?? (name: name, color: color, total: 0)
            groups[key] = (name: name, color: color, total: existing.total + convertedAmount(for: tx))
        }
        return groups
            .map { CategoryTotal(key: $0.key, name: $0.value.name, color: $0.value.color, total: $0.value.total) }
            .filter { $0.total > 0 }
            .sorted { $0.total > $1.total }
    }

    private var bucketComponent: Calendar.Component {
        let days = Calendar.current.dateComponents([.day], from: rangeStart, to: rangeEnd).day ?? 0
        if days <= 60  { return .day }
        if days <= 180 { return .weekOfYear }
        return .month
    }

    private var timeBuckets: [TimeBucket] {
        guard !filtered.isEmpty else { return [] }
        let cal = Calendar.current
        let comp = bucketComponent
        let grouped = Dictionary(grouping: filtered) { tx -> Date in
            cal.dateInterval(of: comp, for: tx.timestamp)?.start ?? tx.timestamp
        }
        return grouped
            .map { TimeBucket(date: $0.key, total: $0.value.reduce(0.0) { $0 + convertedAmount(for: $1) }) }
            .sorted { $0.date < $1.date }
    }

    private var grandTotal: Double { filtered.reduce(0.0) { $0 + convertedAmount(for: $1) } }

    // MARK: Body

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Insights")
                                .font(.largeTitle.bold())
                                .foregroundStyle(.white)
                            Text("\(formatAmount(grandTotal, currency: mainCurrency))\(selectedCategoryKey.map { key in " · \(categoryTotals.first(where: { $0.key == key })?.name ?? key)" } ?? "")")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.55))
                                .animation(.spring, value: grandTotal)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    // Date range
                    HStack(spacing: 10) {
                        Text("From")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.55))
                        DatePicker("", selection: $rangeStart, in: ...rangeEnd, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .colorScheme(.dark)
                            .tint(.appAccent)
                            .labelsHidden()
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.35))
                        DatePicker("", selection: $rangeEnd, in: rangeStart..., displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .colorScheme(.dark)
                            .tint(.appAccent)
                            .labelsHidden()
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 20)

                    // Category filter chips
                    if !categoryTotals.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                PeriodChip(label: "All", selected: selectedCategoryKey == nil) {
                                    withAnimation(.spring(duration: 0.3)) { selectedCategoryKey = nil }
                                }
                                ForEach(categoryTotals) { ct in
                                    PeriodChip(
                                        label: ct.name,
                                        selected: selectedCategoryKey == ct.key,
                                        color: ct.color
                                    ) {
                                        withAnimation(.spring(duration: 0.3)) {
                                            selectedCategoryKey = selectedCategoryKey == ct.key ? nil : ct.key
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // Bar chart: by category
                    if !categoryTotals.isEmpty && selectedCategoryKey == nil {
                        GlassSection(title: "BY CATEGORY") {
                            Chart(categoryTotals) { ct in
                                BarMark(
                                    x: .value("Amount", ct.total),
                                    y: .value("Category", ct.name)
                                )
                                .foregroundStyle(ct.color.gradient)
                                .cornerRadius(6)
                                .annotation(position: .trailing) {
                                    Text(formatAmount(ct.total, currency: mainCurrency))
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                            }
                            .chartXAxis(.hidden)
                            .chartYAxis {
                                AxisMarks(preset: .aligned) { _ in
                                    AxisValueLabel()
                                        .foregroundStyle(Color.white.opacity(0.7))
                                        .font(.caption2)
                                }
                            }
                            .frame(height: max(CGFloat(categoryTotals.count) * 36, 100))
                            .padding(16)
                        }
                        .padding(.horizontal, 20)
                    }

                    // Area chart: over time
                    GlassSection(title: "OVER TIME") {
                        if timeBuckets.isEmpty {
                            Text("No data for this period")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.35))
                                .frame(maxWidth: .infinity, minHeight: 120)
                        } else {
                            Chart(timeBuckets) { bucket in
                                AreaMark(
                                    x: .value("Date", bucket.date),
                                    y: .value("Amount", bucket.total)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.appAccent.opacity(0.5), .appAccent.opacity(0.05)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                                LineMark(
                                    x: .value("Date", bucket.date),
                                    y: .value("Amount", bucket.total)
                                )
                                .foregroundStyle(.appAccent)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                PointMark(
                                    x: .value("Date", bucket.date),
                                    y: .value("Amount", bucket.total)
                                )
                                .foregroundStyle(.appAccent)
                                .symbolSize(selectedBucket?.date == bucket.date ? 60 : 30)
                                if let sel = selectedBucket, sel.date == bucket.date {
                                    RuleMark(x: .value("Date", sel.date))
                                        .foregroundStyle(.white.opacity(0.3))
                                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                                        .annotation(position: .top, alignment: .center, spacing: 4) {
                                            VStack(spacing: 2) {
                                                Text(formatAmount(sel.total, currency: mainCurrency))
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(.white)
                                                Text(sel.date.formatted(date: .abbreviated, time: .omitted))
                                                    .font(.caption2)
                                                    .foregroundStyle(.white.opacity(0.65))
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                                        }
                                }
                            }
                            .chartXAxis(.hidden)
                            .chartYAxis {
                                AxisMarks(preset: .aligned) { value in
                                    AxisValueLabel {
                                        if let d = value.as(Double.self) {
                                            Text(formatAmount(d, currency: mainCurrency))
                                                .font(.caption2)
                                                .foregroundStyle(.white.opacity(0.6))
                                        }
                                    }
                                }
                            }
                            .chartOverlay { proxy in
                                GeometryReader { geo in
                                    Rectangle().fill(.clear).contentShape(Rectangle())
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { value in
                                                    let origin = proxy.plotFrame.map { geo[$0].origin } ?? .zero
                                                    let x = value.location.x - origin.x
                                                    if let date: Date = proxy.value(atX: x), !timeBuckets.isEmpty {
                                                        selectedBucket = timeBuckets.min {
                                                            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                                        }
                                                    }
                                                }
                                                .onEnded { _ in
                                                    withAnimation(.easeOut(duration: 0.3)) { selectedBucket = nil }
                                                }
                                        )
                                }
                            }
                            .frame(height: 180)
                            .padding(16)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Breakdown list
                    if !categoryTotals.isEmpty {
                        GlassSection(title: "BREAKDOWN") {
                            ForEach(Array(categoryTotals.enumerated()), id: \.element.id) { idx, ct in
                                Button {
                                    withAnimation(.spring(duration: 0.3)) {
                                        selectedCategoryKey = selectedCategoryKey == ct.key ? nil : ct.key
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(ct.color)
                                            .frame(width: 10, height: 10)
                                        Text(ct.name)
                                            .font(.subheadline)
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Text(formatAmount(ct.total, currency: mainCurrency))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.white)
                                        if selectedCategoryKey == ct.key {
                                            Image(systemName: "checkmark")
                                                .font(.caption)
                                                .foregroundStyle(.appAccent)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }
                                if idx < categoryTotals.count - 1 { GlassDivider() }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .task(id: rangeTaskKey) { await computeConvertedAmounts() }
    }
}

// MARK: - Period chip

private struct PeriodChip: View {
    let label: String
    let selected: Bool
    var color: Color = .appAccent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
        }
        .glassEffect(
            selected ? Glass.regular.tint(color).interactive() : Glass.regular.interactive(),
            in: .capsule
        )
    }
}

// MARK: - Color helper

func categoryColor(_ category: TransactionCategory) -> Color {
    switch category {
    case .alcohol:       return Color(red: 0.6, green: 0.2, blue: 0.8)
    case .bills:         return .yellow
    case .clothes:       return .pink
    case .coffee:        return Color(red: 0.72, green: 0.45, blue: 0.2)
    case .diningOut:     return .orange
    case .entertainment: return .purple
    case .gifts:         return Color(red: 0.95, green: 0.4, blue: 0.55)
    case .groceries:     return .green
    case .health:        return Color(red: 0.2, green: 0.8, blue: 0.5)
    case .study:         return .appAccent
    case .toiletries:    return Color(red: 0.3, green: 0.7, blue: 0.9)
    case .transport:     return .blue
    case .trips:         return Color(red: 0.1, green: 0.7, blue: 0.6)
    default:             return Color(white: 0.55)
    }
}
