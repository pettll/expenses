Add a new bank notification parsing pattern to NotificationParser.

## Instructions

Ask the user for:
1. **Bank name** (e.g. "Barclays", "HSBC")
2. **Example notification text** — paste a real notification title and body
3. **App bundle ID** — found in iOS Settings → Privacy → Notifications, or ask user to check their banking app's bundle ID

Then:

### Step 1 — Design the regex

Use named capture groups matching the `NotificationParser` convention:
- `(?P<merchant>.+?)` — merchant/vendor name
- `(?P<amount>[\d,]+\.?\d*)` — numeric amount (may have commas)
- `(?P<currency>[£$€]|[A-Z]{3})` — currency symbol or ISO code (optional)

Test the regex against the example text mentally before writing code.

### Step 2 — Add to `NotificationPattern.defaults`

In `expenses/NotificationParser.swift`, add a new `NotificationPattern` to the `defaults` static array:

```swift
NotificationPattern(
    name: "<BankName>",
    regex: #"<your_regex_here>"#,
    groupMapping: ["merchant": "merchant", "amount": "amount", "currency": "currency"],
    bundleIdentifiers: ["<com.bank.AppBundleId>"]
),
```

### Step 3 — Validate

After editing the file, verify:
```bash
# Check it compiles
xcodebuild -project expenses.xcodeproj -scheme expenses -sdk iphonesimulator CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO build 2>&1 | grep -E "error:|Build succeeded"
```

Also mentally trace `NotificationParser.parse(title:body:bundleIdentifier:)` with the example text to confirm the pattern would match.

### Step 4 — Update CLAUDE.md

Add the new bank to the "Supported Banks" list in the Architecture section of CLAUDE.md.
