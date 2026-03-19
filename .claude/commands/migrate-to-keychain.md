Migrate API key and secret storage from UserDefaults to Keychain.

## Context

Currently `CategoryService` stores `anthropic_api_key` and `SheetsService` stores `google_script_secret` in plain `UserDefaults`. These must move to Keychain using `Security.framework`.

## Implementation Plan

### 1. Create `KeychainService.swift` in `expenses/`

```swift
import Foundation
import Security

enum KeychainService {
    static func set(_ value: String, forKey key: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: Bundle.main.bundleIdentifier ?? "com.expenses.app"
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData] = data
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func get(forKey key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: Bundle.main.bundleIdentifier ?? "com.expenses.app",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(forKey key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: Bundle.main.bundleIdentifier ?? "com.expenses.app"
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

### 2. Update `CategoryService.swift`

Replace:
```swift
var anthropicApiKey: String {
    get { UserDefaults.standard.string(forKey: apiKeyStorageKey) ?? "" }
    set { UserDefaults.standard.set(newValue, forKey: apiKeyStorageKey) }
}
```
With:
```swift
var anthropicApiKey: String {
    get { KeychainService.get(forKey: apiKeyStorageKey) ?? "" }
    set { KeychainService.set(newValue, forKey: apiKeyStorageKey) }
}
```

### 3. Update `SheetsService.swift`

Apply the same substitution for `secret` (key: `google_script_secret`).

### 4. Migration on first launch

In the property getters, add a one-time migration:
```swift
get {
    // Migrate from UserDefaults if Keychain is empty
    if let legacy = UserDefaults.standard.string(forKey: key), !legacy.isEmpty,
       KeychainService.get(forKey: key) == nil {
        KeychainService.set(legacy, forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
    }
    return KeychainService.get(forKey: key) ?? ""
}
```

### 5. Build and verify

```bash
xcodebuild -project expenses.xcodeproj -scheme expenses -sdk iphonesimulator CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO build 2>&1 | grep -E "error:|Build succeeded"
```

Then re-run `/security-scan` and confirm the UserDefaults findings are resolved.
