import SwiftUI

struct SheetsHistoryView: View {
    let sheetsService: SheetsService

    @State private var rows:    [SheetsRow] = []
    @State private var isLoading = false
    @State private var error:   String?

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Google Sheets")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                        Text(isLoading ? "Fetching…" : rows.isEmpty ? "No data yet" : "\(rows.count) rows")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Button { Task { await load() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .disabled(isLoading)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 20)

                if isLoading {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.4)
                    Spacer()
                } else if let error {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 44))
                            .foregroundStyle(.orange.opacity(0.7))
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    Spacer()
                } else if rows.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "tablecells")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.2))
                        Text("No rows found in the sheet")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(rows.reversed()) { row in
                            SheetsRowCard(row: row)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            rows = try await sheetsService.fetchRows()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Row card

private struct SheetsRowCard: View {
    let row: SheetsRow

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(row.category.isEmpty ? "Uncategorised" : row.category)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    if !row.date.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.25))
                        Text(row.date)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            Text("\(row.currency) \(row.amount)")
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
