import SwiftUI

struct SettingsView: View {
    @ObservedObject var sheetsService: SheetsService
    @ObservedObject var categoryService: CategoryService

    @State private var scriptURL = ""
    @State private var secret    = ""
    @State private var apiKey    = ""
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var saved     = false
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
                                    .foregroundStyle(.white).tint(.cyan)
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
                                TextField("X-App-Secret header value", text: $secret)
                                    .foregroundStyle(.white).tint(.cyan)
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
                                .foregroundStyle(scriptURL.isEmpty || isTesting ? .white.opacity(0.3) : .cyan)
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
                                    .foregroundStyle(.white).tint(.cyan)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .focused($focused, equals: .apiKey)
                                    .padding(.horizontal, 16).padding(.bottom, 14)
                            }
                        }

                        // MARK: Category rules
                        GlassSection(title: "AUTO-CATEGORISATION RULES") {
                            NavigationLink {
                                CategoryRulesView(categoryService: categoryService)
                            } label: {
                                HStack {
                                    Image(systemName: "tag.fill").foregroundStyle(.cyan)
                                    Text("Keyword Rules")
                                        .font(.body).foregroundStyle(.white)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption).foregroundStyle(.white.opacity(0.4))
                                }
                                .padding(.horizontal, 16).padding(.vertical, 14)
                            }
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }.foregroundStyle(.cyan)
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
