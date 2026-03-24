import SwiftUI
import SwiftData

// MARK: - Needs Review Tab

struct NeedsReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.timestamp, order: .reverse) private var all: [Transaction]
    let categoryService: CategoryService
    let sheetsService: SheetsService
    var notificationParser: NotificationParser

    @State private var showScanSheet = false

    var pending: [Transaction] {
        all.filter { ($0.category == .unknown || $0.category == .other) && $0.customCategoryKey == nil }
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
                    Button {
                        showScanSheet = true
                    } label: {
                        Image(systemName: "bell.badge.waveform.fill")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.appAccent)
                    }
                    .padding(.top, 6)
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
                                ReviewCard(transaction: tx, allTransactions: all, categoryService: categoryService, sheetsService: sheetsService)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 40)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
        .sheet(isPresented: $showScanSheet) {
            NotificationScanSheet(
                notificationParser: notificationParser,
                categoryService: categoryService,
                sheetsService: sheetsService
            )
        }
    }
}

// MARK: - Notification Scan Sheet

struct NotificationScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let notificationParser: NotificationParser
    let categoryService: CategoryService
    let sheetsService: SheetsService

    @State private var titleText = ""
    @State private var bodyText  = ""
    @State private var parsed: ParsedTransaction? = nil
    @State private var added = false
    @FocusState private var focused: ScanField?

    enum ScanField { case title, body }

    var body: some View {
        ZStack {
            AppBackground()
                .onTapGesture { focused = nil }

            VStack(spacing: 0) {
                // Drag handle
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 16)
                    .padding(.bottom, 20)

                ScrollView {
                    VStack(spacing: 20) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Scan Notification")
                                    .font(.title2.bold())
                                    .foregroundStyle(.white)
                                Text("Paste a banking notification to capture the expense")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer()
                        }

                        GlassSection(title: "NOTIFICATION TEXT") {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Title")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .padding(.horizontal, 16)
                                    .padding(.top, 12)
                                TextField("e.g. Apple Pay", text: $titleText)
                                    .foregroundStyle(.white).tint(.appAccent)
                                    .autocorrectionDisabled()
                                    .focused($focused, equals: .title)
                                    .padding(.horizontal, 16).padding(.bottom, 8)
                                    .onChange(of: titleText) { _, _ in reparse() }
                            }
                            GlassDivider()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Body")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .padding(.horizontal, 16)
                                    .padding(.top, 10)
                                TextField("e.g. Costa Coffee £3.50", text: $bodyText)
                                    .foregroundStyle(.white).tint(.appAccent)
                                    .autocorrectionDisabled()
                                    .focused($focused, equals: .body)
                                    .padding(.horizontal, 16).padding(.bottom, 14)
                                    .onChange(of: bodyText) { _, _ in reparse() }
                            }
                        }

                        // Live parse preview
                        if let p = parsed {
                            GlassSection(title: "DETECTED EXPENSE") {
                                VStack(spacing: 0) {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                        Text(p.merchant)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Text(formatAmount(p.amount, currency: p.currency))
                                            .font(.body.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 14)
                                    GlassDivider()
                                    HStack {
                                        Text("Pattern")
                                            .font(.caption).foregroundStyle(.white.opacity(0.5))
                                        Spacer()
                                        Text(p.patternUsed)
                                            .font(.caption).foregroundStyle(.white.opacity(0.7))
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 10)
                                }
                            }

                            Button { addToReview() } label: {
                                HStack(spacing: 8) {
                                    if added {
                                        Image(systemName: "checkmark")
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                    Text(added ? "Added to Review" : "Add to Needs Review")
                                }
                                .font(.body.bold())
                                .foregroundStyle(added ? .green : .black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(added ? Color.green.opacity(0.25) : .white,
                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .animation(.spring(duration: 0.3), value: added)
                            }
                            .disabled(added)
                        } else if !titleText.isEmpty || !bodyText.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                Text("No expense pattern matched — try a different format")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .padding(16)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
                        }

                        // Shortcuts tip
                        GlassSection(title: "AUTOMATIC CAPTURE") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Set up iOS Shortcuts to capture notifications automatically:")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.7))
                                VStack(alignment: .leading, spacing: 6) {
                                    TipRow(n: "1", text: "Open Shortcuts → Automation → New Automation")
                                    TipRow(n: "2", text: "Choose \"App\" trigger → select your banking app")
                                    TipRow(n: "3", text: "Add \"Open URL\" action and paste the URL below")
                                    TipRow(n: "4", text: "Replace [Merchant] and [Amount] with the Shortcut Variables of the same name")
                                    TipRow(n: "5", text: "Turn off \"Ask Before Running\"")
                                }

                                // Copiable URL template
                                let urlTemplate = "expenses://record?merchant=[Merchant]&amount=[Amount]"
                                HStack(spacing: 10) {
                                    Text(urlTemplate)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.appAccent)
                                        .textSelection(.enabled)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                    Button {
                                        UIPasteboard.general.string = urlTemplate
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                }
                                .padding(12)
                                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .padding(16)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
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

    private func reparse() {
        parsed = notificationParser.parse(title: titleText, body: bodyText, bundleIdentifier: nil)
        added = false
    }

    private func addToReview() {
        guard let p = parsed else { return }
        let cat = categoryService.localCategorise(merchant: p.merchant)
        let tx = Transaction(
            amount: p.amount,
            currency: p.currency,
            merchant: p.merchant,
            category: cat == .unknown ? .unknown : cat,
            source: .shortcut,
            rawNotificationText: p.rawText
        )
        modelContext.insert(tx)
        if sheetsService.isConfigured {
            Task { try? await sheetsService.send(transaction: tx) }
        }
        withAnimation { added = true }
        Task {
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        }
    }
}

private struct TipRow: View {
    let n: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n)
                .font(.caption.weight(.bold))
                .foregroundStyle(.appAccent)
                .frame(width: 14)
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
        }
    }
}

// MARK: - Review Card

struct ReviewCard: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var categoryStore: CategoryCustomizationStore

    @Bindable var transaction: Transaction
    let allTransactions: [Transaction]
    let categoryService: CategoryService
    let sheetsService: SheetsService

    @State private var selectedSelection: CategorySelection = .standard(.diningOut)
    @State private var saveAsRule = true
    @State private var applied    = false
    @State private var syncError: String?

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
                Picker("", selection: $selectedSelection) {
                    ForEach(categoryStore.allAssignableSelections().filter {
                        if case .standard(let c) = $0 { return c != .unknown && c != .other }
                        return true
                    }) { sel in
                        Text(categoryStore.displayName(for: sel)).tag(sel)
                    }
                }
                .tint(.appAccent)
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
                    Image(systemName: "wand.and.sparkles").foregroundStyle(.appAccent).font(.caption)
                    Text("Remember \"\(transaction.merchant)\" for next time")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .appAccent))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.spring(duration: 0.3), value: applied)
        .onAppear {
            let suggested = categoryService.localCategorise(merchant: transaction.merchant)
            if suggested != .unknown {
                selectedSelection = .standard(suggested)
            } else {
                let assignable = TransactionCategory.allCases.filter { $0 != .unknown && $0 != .other }
                selectedSelection = .standard(assignable.first ?? .diningOut)
            }
        }
    }

    private func applyCategory() {
        categoryStore.apply(selectedSelection, to: transaction)

        if saveAsRule, case .standard(let cat) = selectedSelection {
            let keyword = transaction.merchant.lowercased().trimmingCharacters(in: .whitespaces)
            var kws = categoryService.keywords(for: cat)
            if !kws.contains(keyword) {
                kws.append(keyword)
                categoryService.setKeywords(kws, for: cat)
            }
        }

        // Find all other transactions with the same merchant and update them too
        let merchantLower = transaction.merchant.lowercased()
        let samemerchant = allTransactions.filter {
            $0.id != transaction.id &&
            $0.merchant.lowercased() == merchantLower
        }
        for tx in samemerchant {
            categoryStore.apply(selectedSelection, to: tx)
        }

        // Sync everything to Sheets: this transaction + all matching ones
        if sheetsService.isConfigured {
            let toSync = [transaction] + samemerchant
            Task {
                do {
                    try await sheetsService.sendBatch(transactions: toSync)
                } catch {
                    syncError = error.localizedDescription
                }
            }
        }

        withAnimation { applied = true }
    }
}
