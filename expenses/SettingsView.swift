import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allTransactions: [Transaction]

    @ObservedObject var sheetsService: SheetsService
    @ObservedObject var categoryService: CategoryService

    @AppStorage("mainCurrency") private var mainCurrency = "GBP"

    @State private var scriptURL         = ""
    @State private var secret            = ""
    @State private var apiKey            = ""
    @State private var isTesting         = false
    @State private var testResult: TestResult?
    @State private var saved             = false
    @State private var confirmDeleteAll  = false
    @FocusState private var focused: Field?

    enum TestResult { case success, failure(String) }
    enum Field { case url, secret, apiKey }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                    .onTapGesture { focused = nil }

                ScrollView {
                    VStack(spacing: 24) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Settings")
                                    .font(.largeTitle.bold())
                                    .foregroundStyle(.white)
                                Text("Configure your integrations")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer()
                        }
                        .padding(.top, 20)

                        // MARK: Google Sheets
                        GlassSection(title: "GOOGLE SHEETS") {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Script URL")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .padding(.horizontal, 16)
                                    .padding(.top, 12)
                                TextField("https://script.google.com/…", text: $scriptURL)
                                    .foregroundStyle(.white).tint(.appAccent)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.URL)
                                    .focused($focused, equals: .url)
                                    .padding(.horizontal, 16).padding(.bottom, 14)
                            }
                            GlassDivider()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Secret (optional)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .padding(.horizontal, 16)
                                    .padding(.top, 12)
                                SecureField("X-App-Secret header value", text: $secret)
                                    .foregroundStyle(.white).tint(.appAccent)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .focused($focused, equals: .secret)
                                    .padding(.horizontal, 16).padding(.bottom, 14)
                            }
                            GlassDivider()
                            Button { testConnection() } label: {
                                HStack {
                                    Image(systemName: "network")
                                    Text(isTesting ? "Testing…" : "Test Connection")
                                    Spacer()
                                    if isTesting {
                                        ProgressView().tint(.white)
                                    } else if let r = testResult {
                                        switch r {
                                        case .success:
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                        case .failure:
                                            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                                        }
                                    }
                                }
                                .font(.body.weight(.medium))
                                .foregroundStyle(scriptURL.isEmpty || isTesting ? .white.opacity(0.3) : .appAccent)
                                .padding(.horizontal, 16).padding(.vertical, 13)
                            }
                            .disabled(scriptURL.isEmpty || isTesting)

                            if case .failure(let msg) = testResult {
                                Text(msg).font(.caption).foregroundStyle(.red.opacity(0.85))
                                    .padding(.horizontal, 16).padding(.bottom, 12)
                            }
                        }

                        // MARK: AI
                        GlassSection(title: "AI CATEGORISATION") {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Anthropic API Key")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .padding(.horizontal, 16)
                                    .padding(.top, 12)
                                SecureField("sk-ant-…", text: $apiKey)
                                    .foregroundStyle(.white).tint(.appAccent)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .focused($focused, equals: .apiKey)
                                    .padding(.horizontal, 16).padding(.bottom, 14)
                            }
                        }

                        // MARK: Display
                        GlassSection(title: "DISPLAY") {
                            HStack {
                                Image(systemName: "coloncurrencysign.circle").foregroundStyle(.appAccent)
                                Text("Main Currency")
                                    .font(.body).foregroundStyle(.white)
                                Spacer()
                                Picker("", selection: $mainCurrency) {
                                    ForEach(["GBP", "USD", "EUR", "BRL", "JPY", "INR", "AUD", "CAD", "CHF", "SGD"], id: \.self) {
                                        Text($0).tag($0)
                                    }
                                }
                                .tint(.appAccent)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                        }

                        // MARK: Category rules
                        GlassSection(title: "AUTO-CATEGORISATION RULES") {
                            NavigationLink {
                                CategoryEditorView(sheetsService: sheetsService)
                            } label: {
                                HStack {
                                    Image(systemName: "pencil").foregroundStyle(.appAccent)
                                    Text("Category Names")
                                        .font(.body).foregroundStyle(.white)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption).foregroundStyle(.white.opacity(0.4))
                                }
                                .padding(.horizontal, 16).padding(.vertical, 14)
                            }
                            GlassDivider()
                            NavigationLink {
                                CategoryRulesView(categoryService: categoryService)
                            } label: {
                                HStack {
                                    Image(systemName: "tag.fill").foregroundStyle(.appAccent)
                                    Text("Keyword Rules")
                                        .font(.body).foregroundStyle(.white)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption).foregroundStyle(.white.opacity(0.4))
                                }
                                .padding(.horizontal, 16).padding(.vertical, 14)
                            }
                        }

                        // MARK: Danger Zone
                        GlassSection(title: "DANGER ZONE") {
                            Button { confirmDeleteAll = true } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "trash.fill")
                                        .font(.body)
                                        .foregroundStyle(.red)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Delete All Transactions")
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.red)
                                        Text(allTransactions.isEmpty
                                             ? "No transactions"
                                             : "\(allTransactions.count) transaction\(allTransactions.count == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.4))
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 16).padding(.vertical, 14)
                            }
                            .disabled(allTransactions.isEmpty)
                        }

                        // MARK: Save
                        Button { saveSettings() } label: {
                            HStack(spacing: 8) {
                                if saved {
                                    Image(systemName: "checkmark").transition(.scale.combined(with: .opacity))
                                }
                                Text(saved ? "Saved" : "Save Settings")
                            }
                            .font(.body.bold())
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .animation(.spring(duration: 0.3), value: saved)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .onAppear { load() }
        .alert(
            "Delete \(allTransactions.count) transaction\(allTransactions.count == 1 ? "" : "s")?",
            isPresented: $confirmDeleteAll
        ) {
            Button("Delete from app and Sheets", role: .destructive) { deleteAll(fromSheets: true) }
            Button("Delete from app only", role: .destructive) { deleteAll(fromSheets: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }.foregroundStyle(.appAccent)
            }
        }
    }

    private func load() {
        scriptURL = sheetsService.scriptURL
        secret    = sheetsService.secret
        apiKey    = categoryService.anthropicApiKey
    }

    private func saveSettings() {
        sheetsService.scriptURL         = scriptURL
        sheetsService.secret            = secret
        categoryService.anthropicApiKey = apiKey
        testResult = nil
        withAnimation { saved = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { saved = false }
        }
    }

    private func deleteAll(fromSheets: Bool) {
        let toDelete = allTransactions
        if fromSheets {
            Task {
                for tx in toDelete where tx.syncedToSheets {
                    try? await sheetsService.deleteFromSheet(transaction: tx)
                }
            }
        }
        for tx in toDelete { modelContext.delete(tx) }
    }

    private func testConnection() {
        saveSettings()
        isTesting  = true
        testResult = nil
        Task {
            do {
                try await sheetsService.testConnection()
                testResult = .success
            } catch {
                testResult = .failure(error.localizedDescription)
            }
            isTesting = false
        }
    }
}

