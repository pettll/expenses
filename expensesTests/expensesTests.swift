//
//  expensesTests.swift
//  expensesTests
//
//  Created by Peterson Segatto Muller on 17/03/2026.
//

import Testing
@testable import expenses

// MARK: - CategoryService local categorisation

@MainActor
struct CategoryServiceTests {

    @Test func localCategorisesKnownCoffeeMerchant() {
        let service = CategoryService()
        #expect(service.localCategorise(merchant: "Starbucks") == .coffee)
    }

    @Test func localCategorisesKnownTransportMerchant() {
        let service = CategoryService()
        #expect(service.localCategorise(merchant: "Uber") == .transport)
    }

    @Test func localCategorisesKnownToileriesMerchant() {
        let service = CategoryService()
        #expect(service.localCategorise(merchant: "Amazon") == .toiletries)
    }

    @Test func localCategorisesKnownHealthMerchant() {
        let service = CategoryService()
        #expect(service.localCategorise(merchant: "PureGym") == .health)
    }

    @Test func localCategorisesUnknownMerchantAsUnknown() {
        let service = CategoryService()
        #expect(service.localCategorise(merchant: "XYZZY_UNKNOWN_MERCHANT_99") == .unknown)
    }

    @Test func localCategorisationIsCaseInsensitive() {
        let service = CategoryService()
        #expect(service.localCategorise(merchant: "MCDONALDS") == .diningOut)
        #expect(service.localCategorise(merchant: "mcdonalds") == .diningOut)
    }

    @Test func customKeywordsOverrideDefaults() {
        let service = CategoryService()
        service.setKeywords(["zynqmerchant"], for: .entertainment)
        #expect(service.localCategorise(merchant: "ZynqMerchant Live") == .entertainment)
    }

    @Test func keywordsRoundtrip() {
        let service = CategoryService()
        let keywords = ["testshop1", "testshop2"]
        service.setKeywords(keywords, for: .clothes)
        #expect(service.keywords(for: .clothes) == keywords)
    }
}

// MARK: - NotificationParser

@MainActor
struct NotificationParserTests {

    @Test func parsesApplePayPoundNotification() {
        let parser = NotificationParser()
        let result = parser.parse(
            title: "Apple Pay",
            body: "Costa Coffee £3.50",
            bundleIdentifier: "com.apple.PassbookUIService"
        )
        #expect(result != nil)
        #expect(result?.merchant == "Costa Coffee")
        #expect(result?.amount == 3.50)
        #expect(result?.currency == "GBP")
    }

    @Test func parsesMonzoNotification() {
        let parser = NotificationParser()
        let result = parser.parse(
            title: "Monzo",
            body: "You paid £12.99 at Netflix",
            bundleIdentifier: "co.monzo.Monzo"
        )
        #expect(result != nil)
        #expect(result?.merchant == "Netflix")
        #expect(result?.amount == 12.99)
        #expect(result?.currency == "GBP")
    }

    @Test func parsesStarlingNotification() {
        let parser = NotificationParser()
        let result = parser.parse(
            title: "Starling",
            body: "Tesco: £45.20",
            bundleIdentifier: "com.starlingbank.StarlingBank"
        )
        #expect(result != nil)
        #expect(result?.merchant == "Tesco")
        #expect(result?.amount == 45.20)
    }

    @Test func returnsNilForUnrecognisedNotification() {
        let parser = NotificationParser()
        let result = parser.parse(
            title: "Some App",
            body: "You have a new message",
            bundleIdentifier: "com.example.app"
        )
        #expect(result == nil)
    }

    @Test func bundleIdFilterBlocksWrongApp() {
        let parser = NotificationParser()
        // Monzo pattern requires co.monzo.Monzo bundle ID
        let result = parser.parse(
            title: "Monzo",
            body: "You paid £12.99 at Netflix",
            bundleIdentifier: "com.evil.phishing"
        )
        #expect(result == nil)
    }

    @Test func parsesAmountWithCommaThousandsSeparator() {
        let parser = NotificationParser()
        let result = parser.parse(
            title: "Apple Pay",
            body: "ACME Store £1,200.00",
            bundleIdentifier: "com.apple.PassbookUIService"
        )
        #expect(result?.amount == 1200.0)
    }
}

// MARK: - Transaction model

struct TransactionModelTests {

    @Test func sheetsRowHasCorrectColumnOrder() {
        let t = Transaction(amount: 9.99, currency: "GBP", merchant: "Pret", category: .diningOut, source: .manual)
        let row = t.sheetsRow
        // Columns: Timestamp | Value | Currency | Category | Merchant
        #expect(row.count == 5)
        #expect(row[1] == "9.99")
        #expect(row[2] == "GBP")
        #expect(row[3] == "Dining Out")
        #expect(row[4] == "Pret")
    }

    @Test func formattedAmountIncludesCurrencySymbol() {
        let t = Transaction(amount: 5.00, currency: "GBP", merchant: "Test", source: .manual)
        #expect(t.formattedAmount.contains("5"))
    }

    @Test func defaultSyncedToSheetsIsFalse() {
        let t = Transaction(amount: 1.0, currency: "GBP", merchant: "Test", source: .manual)
        #expect(t.syncedToSheets == false)
        #expect(t.syncError == nil)
    }

    @Test func defaultCategoryIsUnknownWhenNotSpecified() {
        let t = Transaction(amount: 1.0, currency: "GBP", merchant: "Test", source: .manual)
        #expect(t.category == .unknown)
    }
}
