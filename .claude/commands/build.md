Build the Xcode project for the iOS simulator and report any errors.

```bash
xcodebuild \
  -project expenses.xcodeproj \
  -scheme expenses \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  build 2>&1 | xcpretty || xcodebuild \
  -project expenses.xcodeproj \
  -scheme expenses \
  -sdk iphonesimulator \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  build 2>&1 | grep -E "error:|warning:|Build succeeded|Build FAILED"
```

If there are compilation errors, read the affected Swift file(s) and fix them. Common issues in this project:
- Type references to the old `Item` model (now `Transaction`)
- Missing required `Transaction` init parameters: `amount`, `currency`, `merchant`, `source`
- `@MainActor` isolation violations in service classes
