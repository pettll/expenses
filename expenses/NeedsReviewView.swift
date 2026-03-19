import SwiftUI
import SwiftData

// MARK: - Needs Review Tab

struct NeedsReviewView: View {
    @Query(sort: \Transaction.timestamp, order: .reverse) private var all: [Transaction]
    let categoryService: CategoryService

    var pending: [Transaction] {
        all.filter { $0.category == .unknown || $0.category == .other }
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Needs Review")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                        Text(pending.isEmpty ? "All caught up" : "\(pending.count) uncategorised")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 20)

                if pending.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.green.opacity(0.55))
                        Text("All transactions categorised")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.55))
                        Text("Unknown or 'Other' transactions will appear here for you to review.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.3))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(pending) { tx in
                                ReviewCard(transaction: tx, categoryService: categoryService)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 40)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
    }
}

// MARK: - Review Card

struct ReviewCard: View {
    @Bindable var transaction: Transaction
    let categoryService: CategoryService

    @State private var selectedCategory: TransactionCategory = .foodAndDrink
    @State private var saveAsRule = true
    @State private var applied    = false

    private let assignable = TransactionCategory.allCases.filter { $0 != .unknown && $0 != .other }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.1)).frame(width: 44, height: 44)
                    Image(systemName: "questionmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.merchant)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(transaction.formattedAmount + "  ·  " + transaction.formattedDate)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                if applied {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            GlassDivider().padding(.vertical, 10)

            // Category picker + apply
            HStack(spacing: 10) {
                Picker("", selection: $selectedCategory) {
                    ForEach(assignable, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .tint(.cyan)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button { applyCategory() } label: {
                    Text(applied ? "Done" : "Apply")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(applied ? .green : .black)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(applied ? Color.green.opacity(0.2) : .white, in: Capsule())
                }
                .disabled(applied)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            GlassDivider()

            // Save as rule toggle
            Toggle(isOn: $saveAsRule) {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.sparkles").foregroundStyle(.cyan).font(.caption)
                    Text("Remember \"\(transaction.merchant)\" for next time")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .cyan))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 1))
        .animation(.spring(duration: 0.3), value: applied)
        .onAppear {
            selectedCategory = assignable.first ?? .other
        }
    }

    private func applyCategory() {
        transaction.category = selectedCategory
        if saveAsRule {
            let keyword = transaction.merchant.lowercased().trimmingCharacters(in: .whitespaces)
            var kws = categoryService.keywords(for: selectedCategory)
            if !kws.contains(keyword) {
                kws.append(keyword)
                categoryService.setKeywords(kws, for: selectedCategory)
            }
        }
        withAnimation { applied = true }
    }
}
