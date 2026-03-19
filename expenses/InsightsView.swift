import SwiftUI
import SwiftData
import Charts

// MARK: - Period

enum InsightPeriod: String, CaseIterable, Identifiable {
    case week    = "Week"
    case month   = "Month"
    case quarter = "Quarter"
    case year    = "Year"

    var id: String { rawValue }

    func dateRange() -> ClosedRange<Date> {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .week:
            let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now))!
            return start...now
        case .month:
            let comps = cal.dateComponents([.year, .month], from: now)
            let start = cal.date(from: comps)!
            return start...now
        case .quarter:
            let start = cal.date(byAdding: .month, value: -3, to: now)!
            return start...now
        case .year:
            var comps = cal.dateComponents([.year], from: now)
            comps.month = 1; comps.day = 1
            let start = cal.date(from: comps)!
            return start...now
        }
    }

    // Granularity label for time-series grouping
    var bucketComponent: Calendar.Component {
        switch self {
        case .week:    return .day
        case .month:   return .day
        case .quarter: return .weekOfYear
        case .year:    return .month
        }
    }
}

// MARK: - Data helpers

private struct CategoryTotal: Identifiable {
    let category: TransactionCategory
    let total: Double
    var id: String { category.rawValue }
}

private struct TimeBucket: Identifiable {
    let date: Date
    let total: Double
    var id: Date { date }
}

// MARK: - Insights View

struct InsightsView: View {
    @Query(sort: \Transaction.timestamp, order: .reverse) private var all: [Transaction]

    @State private var period: InsightPeriod = .month
    @State private var selectedCategory: TransactionCategory? = nil

    private var range: ClosedRange<Date> { period.dateRange() }

    private var filtered: [Transaction] {
        all.filter { range.contains($0.timestamp) }
           .filter { selectedCategory == nil || $0.category == selectedCategory }
    }

    private var categoryTotals: [CategoryTotal] {
        let inRange = all.filter { range.contains($0.timestamp) }
        let grouped = Dictionary(grouping: inRange, by: \.category)
        return grouped.map { CategoryTotal(category: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
                      .sorted { $0.total > $1.total }
    }

    private var timeBuckets: [TimeBucket] {
        guard !filtered.isEmpty else { return [] }
        let cal = Calendar.current
        let comp = period.bucketComponent
        let grouped = Dictionary(grouping: filtered) { tx -> Date in
            cal.dateInterval(of: comp, for: tx.timestamp)!.start
        }
        return grouped.map { TimeBucket(date: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
                      .sorted { $0.date < $1.date }
    }

    private var grandTotal: Double { filtered.reduce(0) { $0 + $1.amount } }

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
                            Text("£\(grandTotal, specifier: "%.2f") \(selectedCategory.map { "· \($0.rawValue)" } ?? "")")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.55))
                                .animation(.spring, value: grandTotal)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    // Period picker
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(InsightPeriod.allCases) { p in
                                PeriodChip(label: p.rawValue, selected: period == p) {
                                    withAnimation(.spring(duration: 0.3)) { period = p }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // Category filter chips
                    if !categoryTotals.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                PeriodChip(label: "All", selected: selectedCategory == nil) {
                                    withAnimation(.spring(duration: 0.3)) { selectedCategory = nil }
                                }
                                ForEach(categoryTotals) { ct in
                                    PeriodChip(
                                        label: ct.category.rawValue,
                                        selected: selectedCategory == ct.category,
                                        color: categoryColor(ct.category)
                                    ) {
                                        withAnimation(.spring(duration: 0.3)) {
                                            selectedCategory = selectedCategory == ct.category ? nil : ct.category
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // Bar chart: spending by category
                    if !categoryTotals.isEmpty && selectedCategory == nil {
                        GlassSection(title: "BY CATEGORY") {
                            Chart(categoryTotals) { ct in
                                BarMark(
                                    x: .value("Amount", ct.total),
                                    y: .value("Category", ct.category.rawValue)
                                )
                                .foregroundStyle(categoryColor(ct.category).gradient)
                                .cornerRadius(6)
                                .annotation(position: .trailing) {
                                    Text("£\(ct.total, specifier: "%.0f")")
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

                    // Area chart: spending over time
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
                                        colors: [.cyan.opacity(0.5), .cyan.opacity(0.05)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                                LineMark(
                                    x: .value("Date", bucket.date),
                                    y: .value("Amount", bucket.total)
                                )
                                .foregroundStyle(.cyan)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                PointMark(
                                    x: .value("Date", bucket.date),
                                    y: .value("Amount", bucket.total)
                                )
                                .foregroundStyle(.cyan)
                                .symbolSize(30)
                            }
                            .chartXAxis {
                                AxisMarks(preset: .aligned) { _ in
                                    AxisValueLabel(format: xAxisFormat)
                                        .foregroundStyle(Color.white.opacity(0.6))
                                        .font(.caption2)
                                }
                            }
                            .chartYAxis {
                                AxisMarks(preset: .aligned) { value in
                                    AxisValueLabel {
                                        if let d = value.as(Double.self) {
                                            Text("£\(d, specifier: "%.0f")")
                                                .font(.caption2)
                                                .foregroundStyle(.white.opacity(0.6))
                                        }
                                    }
                                }
                            }
                            .frame(height: 180)
                            .padding(16)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Summary rows per category
                    if !categoryTotals.isEmpty {
                        GlassSection(title: "BREAKDOWN") {
                            ForEach(Array(categoryTotals.enumerated()), id: \.element.id) { idx, ct in
                                Button {
                                    withAnimation(.spring(duration: 0.3)) {
                                        selectedCategory = selectedCategory == ct.category ? nil : ct.category
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(categoryColor(ct.category))
                                            .frame(width: 10, height: 10)
                                        Text(ct.category.rawValue)
                                            .font(.subheadline)
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Text("£\(ct.total, specifier: "%.2f")")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.white)
                                        if let sel = selectedCategory, sel == ct.category {
                                            Image(systemName: "checkmark")
                                                .font(.caption)
                                                .foregroundStyle(.cyan)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }
                                if idx < categoryTotals.count - 1 {
                                    GlassDivider()
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var xAxisFormat: Date.FormatStyle {
        switch period {
        case .week, .month: return .dateTime.day().month(.abbreviated)
        case .quarter:      return .dateTime.month(.abbreviated).day()
        case .year:         return .dateTime.month(.abbreviated)
        }
    }
}

// MARK: - Period chip

private struct PeriodChip: View {
    let label: String
    let selected: Bool
    var color: Color = .cyan
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? .black : .white.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    selected ? AnyShapeStyle(color) : AnyShapeStyle(.white.opacity(0.12)),
                    in: Capsule()
                )
        }
    }
}

// MARK: - Color helper

func categoryColor(_ category: TransactionCategory) -> Color {
    switch category {
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
