# expenses

Native iOS expense tracker that captures banking notifications, auto-categorises transactions with Claude AI, and syncs everything to Google Sheets.

## Features

- **Automatic capture** — listens for banking notifications (Apple Pay, Monzo, Starling, Amex) and creates transactions instantly
- **AI categorisation** — keyword rules handle known merchants; Claude Haiku handles everything else
- **Google Sheets sync** — upserts every transaction to a Sheet via Apps Script (batch, retry, delete supported)
- **Multi-currency** — converts foreign amounts to your main currency using daily exchange rates
- **Home screen widget** — shows recent spend at a glance
- **Fully configurable** — edit notification patterns, category keywords, and custom categories in-app

## Requirements

- iOS 17+
- Xcode 15+
- An [Anthropic API key](https://console.anthropic.com) (optional — used only for AI categorisation fallback)
- A Google account with Apps Script enabled (optional — for Sheets sync)

## Getting Started

1. Clone the repo and open `expenses.xcodeproj` in Xcode
2. Select your target device or simulator
3. Build and run (`Cmd+R`)
4. Grant notification access when prompted — required for automatic capture

No package dependencies. Everything is first-party Swift.

## Configuration

All configuration lives in **Settings** inside the app.

### Anthropic API Key

Used as a fallback when the merchant doesn't match any keyword rule. The model (`claude-haiku-4-5-20251001`) is called with a minimal prompt asking it to return a single category name.

If no key is set, unknown merchants are categorised as **Other**.

### Google Sheets Sync

Requires a Google Apps Script web app that accepts POST requests. The script should handle four actions:

| Action | Description |
|---|---|
| `upsert` | Insert or update a row by `txId` |
| `batch` | Upsert multiple rows in one call |
| `delete` | Remove a row by `txId` |
| `patchRow` | Write a `txId` to an existing row by index |

A `doGet` endpoint returning `{"rows": [...]}` is also expected for the history view and connection test.

Optionally set a shared secret — the app sends it as `X-App-Secret` on every POST.

### Notification Patterns

The app parses notification titles and bodies using named-capture-group regex patterns. Default patterns ship for Apple Pay (GBP and multi-currency), Monzo, Starling, and American Express. You can add, edit, reorder, or disable patterns in **Settings → Notification Patterns**.

Pattern fields:
- **Regex** — POSIX extended regex with named groups: `merchant`, `amount`, `currency` (optional)
- **Bundle identifiers** — restrict the pattern to specific app bundle IDs (empty = match all)

Example — Monzo pattern:
```
You (?:paid|spent) (?<currency>[£$€])(?<amount>[\d,]+\.?\d*) at (?<merchant>.+)
Bundle: co.monzo.Monzo
```

### Category Rules

Each category has a list of keyword strings. If a merchant name contains any keyword (case-insensitive), it's assigned that category without calling the API.

Edit keywords per category in **Settings → Category Rules**. Changes persist in UserDefaults.

## Categories

Alcohol · Bills · Clothes · Coffee · Dining Out · Entertainment · Gifts · Groceries · Health · Study · Toiletries/Household · Transport · Trips · Other

Custom categories can be created and mapped to the built-in set for Sheets export.

## Transaction Sources

| Source | How it arrives |
|---|---|
| Bank Sync | Parsed from a banking notification |
| Manual | Entered by the user in-app |
| Shortcut | Created via iOS Shortcuts automation |
| Sheets | Imported from the connected Google Sheet |

## Architecture

```
expenses/
├── Transaction.swift           SwiftData model + category/source enums
├── NotificationParser.swift    Regex-based notification → ParsedTransaction
├── CategoryService.swift       Keyword rules + Claude AI fallback
├── SheetsService.swift         Google Apps Script HTTP client
├── ExchangeRateService.swift   Daily rate fetch + disk cache (fawazahmed0/currency-api)
├── ContentView.swift           Main tab view
├── InsightsView.swift          Spend charts and summaries
├── NeedsReviewView.swift       Unreviewed transaction queue
├── SheetsHistoryView.swift     Sheet row viewer + import
├── CategoryEditorView.swift    Keyword rule editor
├── CategoryRulesView.swift     Per-category keyword list
├── SettingsView.swift          All configuration
└── ExpensesWidget/             Home screen widget target
```

Data is persisted with SwiftData. Exchange rates are cached to disk under `Caches/ExchangeRates/`. Notification patterns and category rules are stored in UserDefaults.

## Privacy

- No analytics or crash reporting
- The Anthropic API is called only when a merchant doesn't match any local keyword rule, and only if an API key is configured
- Notification content is processed on-device; only the parsed merchant name is sent to the API
- Google Sheets sync is opt-in and uses your own Apps Script deployment

## License

MIT
