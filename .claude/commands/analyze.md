Run Xcode's static analyzer (SAST) on the project and summarise any issues found.

```bash
xcodebuild analyze \
  -project expenses.xcodeproj \
  -scheme expenses \
  -sdk iphonesimulator \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  2>&1 | grep -E "warning:|error:|analyze|ANALYZE"
```

After running, also perform these manual security checks:

1. **Secrets in UserDefaults** — scan for keys stored insecurely:
```bash
grep -rn "UserDefaults.*api_key\|UserDefaults.*secret\|UserDefaults.*password\|UserDefaults.*token" expenses/
```

2. **Plain HTTP URLs** — ensure no unencrypted endpoints:
```bash
grep -rn "http://" expenses/ --include="*.swift"
```

3. **Unvalidated input passed to APIs** — check merchant strings sent to external services without sanitization:
```bash
grep -n "merchant" expenses/CategoryService.swift expenses/SheetsService.swift
```

4. **Force unwraps in network paths**:
```bash
grep -n "!\." expenses/SheetsService.swift expenses/CategoryService.swift
```

Report each finding with file path, line number, and recommended fix.
