Run the test suite and report results.

```bash
# Full test suite
xcodebuild test \
  -project expenses.xcodeproj \
  -scheme expenses \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  2>&1 | grep -E "Test Case|passed|failed|error:|Executed"
```

```bash
# Single test by name (Swift Testing framework)
xcodebuild test \
  -project expenses.xcodeproj \
  -scheme expenses \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:expensesTests/expensesTests/<TestFunctionName> \
  2>&1 | grep -E "Test Case|passed|failed|error:"
```

## Test file locations
- Unit tests: `expensesTests/expensesTests.swift` (Swift Testing — use `@Test` and `#expect`)
- UI tests: `expensesUITests/expensesUITests.swift` (XCTest)

## Writing new tests

Unit tests use Apple's Swift Testing framework:
```swift
import Testing
@testable import expenses

@Test func categoryServiceLocalCategorise() {
    let service = CategoryService()
    let result = service.localCategorise(merchant: "Starbucks")
    #expect(result == .foodAndDrink)
}
```

Key units worth testing:
- `CategoryService.localCategorise(merchant:)` — keyword matching logic
- `NotificationParser.parse(title:body:bundleIdentifier:)` — regex pattern matching
- `Transaction.sheetsRow` — correct column ordering
- `Transaction.formattedAmount` — currency formatting
