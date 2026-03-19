# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Build (from repo root)
xcodebuild -project expenses.xcodeproj -scheme expenses -sdk iphonesimulator build

# Run unit tests
xcodebuild test -project expenses.xcodeproj -scheme expenses -destination 'platform=iOS Simulator,name=iPhone 16'

# Run a single test (Swift Testing framework)
xcodebuild test -project expenses.xcodeproj -scheme expenses -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:expensesTests/expensesTests/<TestName>

# Run UI tests
xcodebuild test -project expenses.xcodeproj -scheme expenses -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:expensesUITests

# Static analysis (Xcode built-in)
xcodebuild analyze -project expenses.xcodeproj -scheme expenses -sdk iphonesimulator

# Check for Swift compilation errors without full build
swiftc --version && xcodebuild -project expenses.xcodeproj -scheme expenses -sdk iphonesimulator build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

## Architecture

SwiftUI + SwiftData iOS app (minimum iOS 17) that captures banking notifications, categorizes transactions via Claude AI, and syncs to Google Sheets.

**Data flow:**
```
Banking App Notification → NotificationParser → Transaction (SwiftData) → SheetsService → Google Sheets
                                                        ↑
                                               CategoryService (local rules → Claude AI fallback)
```

### Services

- **`CategoryService`** — Dual-mode categorization: keyword rules (UserDefaults) first, falls back to `claude-haiku-4-5-20251001` via Anthropic API (`/v1/messages`). Manages `TransactionCategory` enum assignment.

- **`SheetsService`** — POSTs transactions as JSON to a user-deployed Google Apps Script URL. Tracks `syncedToSheets`/`syncError` per transaction. Optional `X-App-Secret` header for endpoint auth.

- **`NotificationParser`** — Regex patterns with named capture groups (`merchant`, `amount`, `currency`) for parsing banking notifications. Built-in patterns for Apple Pay, Monzo, Starling. Patterns stored/edited in UserDefaults.

### Data Model

`Transaction` is the sole SwiftData `@Model`. Key fields: `amount: Double`, `currency: String`, `merchant: String`, `category: TransactionCategory`, `source: TransactionSource`, `syncedToSheets: Bool`, `rawNotificationText: String?`.

`sheetsRow` computed property serializes a transaction for the Sheets payload.

### Configuration Storage

All user configuration lives in UserDefaults (not Keychain — a known security gap):
- `anthropic_api_key` — Anthropic key for AI categorization
- `google_script_url` — Deployed Apps Script endpoint
- `google_script_secret` — Optional shared secret

## Known Issues

- **`ContentView.swift`** references the old `Item` type (renamed to `Transaction`) — the app will not compile until this is fixed. Replace `[Item]` with `[Transaction]` and `Item(timestamp:)` with `Transaction(...)`.

## Security Constraints

- **API keys must use Keychain**, not UserDefaults. Use `Security.framework` `SecItemAdd`/`SecItemCopyMatching` for storing `anthropic_api_key` and `google_script_secret`. Do not regress to UserDefaults for secrets.
- **Google Apps Script URL** should be validated as HTTPS before accepting; reject plain HTTP.
- **Merchant names** from notifications must be sanitized before being sent to external APIs — treat them as untrusted input.
- **`rawNotificationText`** may contain PII (account numbers, balances). Do not log it or include it in error reports.

## Testing Framework

Unit tests use Apple's modern **Swift Testing** framework (`import Testing`, `@Test`, `#expect`). UI tests use **XCTest**. Both suites are currently empty stubs — new features should add `@Test` functions to `expensesTests.swift`.

## Quality Gates

When modifying services that call external APIs (`CategoryService`, `SheetsService`):
1. Ensure all network calls go through `URLSession` with a configured timeout (30s established pattern).
2. Errors must degrade gracefully — never crash; fall back to `.other` category or set `syncError` on the transaction.
3. Run `xcodebuild analyze` and resolve any reported issues before committing.
4. New regex patterns in `NotificationParser` must be validated with `test(pattern:against:)` before saving.
