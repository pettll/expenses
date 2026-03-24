import WidgetKit
import SwiftUI

// MARK: - Shared summary (read from App Group UserDefaults)

struct ExpenseSummary {
    let dailyTotal:   Double
    let monthlyTotal: Double
    let lastUpdated:  Date

    static func read() -> ExpenseSummary {
        let d = UserDefaults(suiteName: "group.com.psmuller.expenses") ?? .standard
        return ExpenseSummary(
            dailyTotal:   d.double(forKey: "widgetDailyTotal"),
            monthlyTotal: d.double(forKey: "widgetMonthlyTotal"),
            lastUpdated:  d.object(forKey: "widgetLastUpdated") as? Date ?? .distantPast
        )
    }

    static var placeholder: ExpenseSummary {
        ExpenseSummary(dailyTotal: 24.50, monthlyTotal: 312.80, lastUpdated: Date())
    }
}

// MARK: - Timeline

struct ExpensesEntry: TimelineEntry {
    let date:    Date
    let summary: ExpenseSummary
}

struct ExpensesProvider: TimelineProvider {
    func placeholder(in context: Context) -> ExpensesEntry {
        ExpensesEntry(date: .now, summary: .placeholder)
    }
    func getSnapshot(in context: Context, completion: @escaping (ExpensesEntry) -> Void) {
        completion(ExpensesEntry(date: .now, summary: .read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ExpensesEntry>) -> Void) {
        let entry = ExpensesEntry(date: .now, summary: .read())
        let next  = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Small widget (daily total)

struct SmallWidgetView: View {
    let entry: ExpensesEntry

    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(LinearGradient(
                    colors: [Color(red: 0.08, green: 0.04, blue: 0.48),
                             Color(red: 0.44, green: 0.00, blue: 0.38)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))

            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))

                Text("£\(entry.summary.dailyTotal, specifier: "%.2f")")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)

                Spacer()

                VStack(alignment: .leading, spacing: 1) {
                    Text("Month")
                        .font(.caption2).foregroundStyle(.white.opacity(0.5))
                    Text("£\(entry.summary.monthlyTotal, specifier: "%.2f")")
                        .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.85))
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Medium widget (totals + action buttons)

struct MediumWidgetView: View {
    let entry: ExpensesEntry

    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(LinearGradient(
                    colors: [Color(red: 0.08, green: 0.04, blue: 0.48),
                             Color(red: 0.44, green: 0.00, blue: 0.38)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))

            HStack(spacing: 0) {
                // Totals
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today")
                            .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                        Text("£\(entry.summary.dailyTotal, specifier: "%.2f")")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white).minimumScaleFactor(0.6)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This month")
                            .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                        Text("£\(entry.summary.monthlyTotal, specifier: "%.2f")")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85)).minimumScaleFactor(0.6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Action buttons — open app via URL scheme
                VStack(spacing: 10) {
                    Link(destination: URL(string: "expenses://add")!) {
                        Label("Add", systemImage: "plus")
                            .font(.caption.weight(.semibold)).foregroundStyle(.black)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.white, in: Capsule())
                    }
                    Link(destination: URL(string: "expenses://sync")!) {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.white.opacity(0.2), in: Capsule())
                    }
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Widget definitions

struct ExpensesSmallWidget: Widget {
    let kind = "ExpensesSmallWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ExpensesProvider()) { entry in
            SmallWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(red: 0.02, green: 0.00, blue: 0.12) }
        }
        .configurationDisplayName("Expenses")
        .description("Daily and monthly spending at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

struct ExpensesMediumWidget: Widget {
    let kind = "ExpensesMediumWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ExpensesProvider()) { entry in
            MediumWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(red: 0.02, green: 0.00, blue: 0.12) }
        }
        .configurationDisplayName("Expenses")
        .description("Totals plus quick Add and Sync actions.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Bundle entry point

@main
struct ExpensesWidgetBundle: WidgetBundle {
    var body: some Widget {
        ExpensesSmallWidget()
        ExpensesMediumWidget()
    }
}
