Perform a full security review of the codebase covering SAST and DAST concerns for this iOS app.

## SAST Checks (Static)

Run each check and report findings:

```bash
# 1. Secrets stored outside Keychain
grep -rn "UserDefaults.standard.set\|UserDefaults.standard.string" expenses/ --include="*.swift" | grep -i "key\|secret\|token\|password"

# 2. Hardcoded credentials or URLs
grep -rn '"http\|api_key\|secret\|password"' expenses/ --include="*.swift" | grep -v "//\|test\|Test"

# 3. Force-unwrapped optionals in network/parse code
grep -rn "URL(string:.*)\!" expenses/ --include="*.swift"

# 4. User input passed unsanitized to external calls
grep -B2 -A2 "merchant" expenses/CategoryService.swift

# 5. Missing HTTPS enforcement in URL validation
grep -n "URL(string:" expenses/SheetsService.swift

# 6. Regex patterns from user input compiled without error handling
grep -n "NSRegularExpression" expenses/NotificationParser.swift

# 7. PII in logs
grep -rn "print(" expenses/ --include="*.swift"
```

## DAST Concerns (Runtime / Design)

Review and answer each question:

1. **Certificate pinning**: Is SSL pinning configured? (Currently: No — note this as a finding)
2. **ATS compliance**: Check Info.plist for `NSAppTransportSecurity` exceptions
3. **Jailbreak detection**: Is there any check before accessing sensitive config?
4. **Keychain vs UserDefaults**: Are `anthropic_api_key` and `google_script_secret` in Keychain? (Currently: No — critical finding)
5. **Data at rest**: Is `rawNotificationText` excluded from iCloud backup?
6. **Timeout + retry amplification**: Can the SheetsService retry loop be abused to DDoS the endpoint?

## Expected Output Format

For each finding:
- **Severity**: Critical / High / Medium / Low
- **File**: path:line
- **Issue**: description
- **Fix**: concrete code change or architectural recommendation
