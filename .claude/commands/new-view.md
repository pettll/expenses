Create a new SwiftUI view for the expenses app.

## Instructions

Ask the user: what screen/feature does this view implement?

Then follow these conventions from the existing codebase:

### File naming
- Place in `expenses/` directory
- Name matches the primary struct: `SettingsView.swift`, `PatternEditorView.swift`, etc.

### Architecture pattern
Services are injected as `@StateObject` at the top level and passed down as plain properties or via environment:
```swift
struct MyView: View {
    @Environment(\.modelContext) private var modelContext
    let categoryService: CategoryService   // passed from parent
    let sheetsService: SheetsService       // passed from parent
    // ...
}
```

Do NOT create new `@StateObject` service instances inside child views — receive them from the parent.

### SwiftData queries
```swift
@Query(sort: \Transaction.timestamp, order: .reverse) private var transactions: [Transaction]
```

### Async operations
Use `Task { }` inside button actions. Show loading state with a `@State private var isLoading = false` bool.

### Error display
Use `.alert` with a `@State private var errorMessage: String?` binding pattern (see `ContentView` for the exact pattern used).

### After creating the view
1. Wire it into `ContentView` or the appropriate navigation destination
2. Add a `#Preview` block using `Transaction.self` in-memory model container
3. Run `/build` to verify compilation
