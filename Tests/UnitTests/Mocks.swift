//
//  Mocks.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/10/25.
//

import Foundation
import XCTest
import StoreKit
@testable import ASimplePurchaseKit // Use @testable to access internal types

// MARK: - Mock Product Implementations

public struct MockPromotionalOffer: PromotionalOfferProtocol, Hashable, Sendable {
    public var id: String?
    public var displayName: String
    public var price: Decimal
    public var displayPrice: String
    public var paymentMode: Product.SubscriptionOffer.PaymentMode
    public var period: Product.SubscriptionPeriod
    public var type: Product.SubscriptionOffer.OfferType

    public static func == (lhs: MockPromotionalOffer, rhs: MockPromotionalOffer) -> Bool {
        lhs.id == rhs.id && lhs.displayName == rhs.displayName
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(displayName)
    }

    // Example initializer for tests
    public init(id: String? = nil, displayName: String = "Test Offer", price: Decimal = 0.0, displayPrice: String = "$0.00", paymentMode: Product.SubscriptionOffer.PaymentMode = .freeTrial, period: Product.SubscriptionPeriod = .weekly, type: Product.SubscriptionOffer.OfferType = .introductory) {
        self.id = id
        self.displayName = displayName
        self.price = price
        self.displayPrice = displayPrice
        self.paymentMode = paymentMode
        self.period = period
        self.type = type
    }
}

public struct MockSubscriptionInfo: SubscriptionInfoProtocol, Hashable, Sendable {
    public var subscriptionGroupID: String
    public var promotionalOffers: [PromotionalOfferProtocol]
    public var subscriptionPeriod: Product.SubscriptionPeriod

    public static func == (lhs: MockSubscriptionInfo, rhs: MockSubscriptionInfo) -> Bool {
        lhs.subscriptionGroupID == rhs.subscriptionGroupID
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(subscriptionGroupID)
    }

    // Initializer to create instances for tests
    public init(subscriptionGroupID: String, promotionalOffers: [PromotionalOfferProtocol] = [], subscriptionPeriod: Product.SubscriptionPeriod = .monthly) {
        self.subscriptionGroupID = subscriptionGroupID
        self.promotionalOffers = promotionalOffers
        self.subscriptionPeriod = subscriptionPeriod
    }
}


public struct MockProduct: ProductProtocol, Hashable, Sendable {
    public var id: String
    public var type: Product.ProductType
    public var displayName: String
    public var description: String
    public var displayPrice: String
    public var price: Decimal
    public var isFamilyShareable: Bool
    public var subscription: SubscriptionInfoProtocol?
    public var underlyingStoreKitProduct: Product? { nil }

    public static func == (lhs: MockProduct, rhs: MockProduct) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public init(id: String, type: Product.ProductType, displayName: String, description: String = "Mock Description", displayPrice: String = "$0.99", price: Decimal = 0.99, isFamilyShareable: Bool = false, subscription: SubscriptionInfoProtocol? = nil) {
        self.id = id
        self.type = type
        self.displayName = displayName
        self.description = description
        self.displayPrice = displayPrice
        self.price = price
        self.isFamilyShareable = isFamilyShareable
        self.subscription = subscription
    }

    // Helper to create a mock auto-renewable product
    public static func newAutoRenewable(id: String, displayName: String = "Mock Subscription", groupID: String = "group1", period: Product.SubscriptionPeriod = .monthly, promotionalOffers: [PromotionalOfferProtocol] = []) -> MockProduct {
        MockProduct(id: id,
                    type: .autoRenewable,
                    displayName: displayName,
                    subscription: MockSubscriptionInfo(subscriptionGroupID: groupID, promotionalOffers: promotionalOffers, subscriptionPeriod: period)
        )
    }

    public static func newNonConsumable(id: String, displayName: String = "Mock Lifetime") -> MockProduct {
        MockProduct(id: id, type: .nonConsumable, displayName: displayName)
    }
}


@MainActor
class MockPurchaseProvider: ProductProvider, Purchaser, ReceiptValidator {
    // MARK: - Controllable Test Properties

    // Controls what fetchProducts() returns
    var productsResult: Result<[any ProductProtocol], Error> = .success([])

    // Controls what purchase() returns
    var purchaseResult: Result<Transaction, Error> = .failure(PurchaseError.unknown)

    // Controls what validate() and checkCurrentEntitlements() return
    var entitlementResult: Result<EntitlementStatus, Error> = .success(.notSubscribed)

    // Controls what getAllTransactions() returns
    var allTransactionsResult: Result<[Transaction], Error> = .success([])

    // MARK: - Call Counts and Captured Values for Assertions

    var fetchProductsCallCount = 0
    var purchaseCallCount = 0
    var lastOfferIdentifierPurchased: String?
    var validateCallCount = 0
    var checkCurrentEntitlementsCallCount = 0
    var getAllTransactionsCallCount = 0


    // MARK: - Protocol Implementations

    func fetchProducts(for ids: [String]) async throws -> [any ProductProtocol] {
        fetchProductsCallCount += 1
        return try productsResult.get()
    }

    func purchase(_ product: Product, offerIdentifier: String?) async throws -> Transaction {
        purchaseCallCount += 1
        lastOfferIdentifierPurchased = offerIdentifier
        return try purchaseResult.get()
    }

    func validate(transaction: Transaction) async throws -> EntitlementStatus {
        validateCallCount += 1
        return try entitlementResult.get()
    }

    func checkCurrentEntitlements() async throws -> EntitlementStatus {
        checkCurrentEntitlementsCallCount += 1
        return try entitlementResult.get()
    }

    func getAllTransactions() async throws -> [Transaction] {
        getAllTransactionsCallCount += 1
        return try allTransactionsResult.get()
    }

    // MARK: - Test Helper

    func reset() {
        productsResult = .success([])
        purchaseResult = .failure(PurchaseError.unknown)
        entitlementResult = .success(.notSubscribed)
        allTransactionsResult = .success([])

        fetchProductsCallCount = 0
        purchaseCallCount = 0
        lastOfferIdentifierPurchased = nil
        validateCallCount = 0
        checkCurrentEntitlementsCallCount = 0
        getAllTransactionsCallCount = 0
    }
}

extension Transaction {
    // This is still problematic to truly mock but keeping for conceptual integrity.
    // Tests should rely on MockPurchaseProvider's results rather than mock Transactions.
    static func makeMock(productID: String = "mock.product.id",
                         purchaseDate: Date = Date(),
                         productType: Product.ProductType = .autoRenewable,
                         expiresDate: Date? = Calendar.current.date(byAdding: .month, value: 1, to: Date()),
                         originalID: UInt64 = UInt64.random(in: 1000...9999),
                         promotionalOfferID: String? = nil,
                         subscriptionStatusProvider: (() async -> Product.SubscriptionInfo.Status?)? = nil
    ) throws -> Transaction {
        print("⚠️ Transaction.makeMock is a conceptual placeholder. Real Transaction instances are hard to mock fully.")
        // To truly mock Transaction for testing getSubscriptionDetails, we'd need to mock its async `subscriptionStatus` property.
        // This is non-trivial. The current Transaction.makeMock will still throw.
        // For testing getSubscriptionDetails, MockPurchaseProvider.allTransactionsResult will need to be set
        // with *real* Transactions obtained from SKTestSession in an integration test context if deep inspection is needed,
        // or the test logic for getSubscriptionDetails will need to be adapted to handle this mock limitation.
        throw NSError(domain: "MockTransactionError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create a fully mock Transaction object for unit tests easily, especially for async properties like subscriptionStatus."])
    }
}

// MARK: - Mock System Service Providers

@MainActor
class MockTransactionListenerProvider: TransactionListenerProvider {
    
    // We can capture the handler to manually trigger it in tests
    var updateHandler: ((VerificationResult<Transaction>) async -> Void)?
    var listenForTransactionsCallCount = 0

    func listenForTransactions(updateHandler: @escaping (VerificationResult<Transaction>) async -> Void) -> Task<Void, Error> {
        listenForTransactionsCallCount += 1
        self.updateHandler = updateHandler
        // Return a dummy task that does nothing, but can be cancelled.
        return Task { /* Do nothing */ }
    }

    // Helper for tests to simulate a transaction update
    func triggerTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        await updateHandler?(result)
    }

    func reset() {
        updateHandler = nil
        listenForTransactionsCallCount = 0
    }
}

@MainActor
class MockAppStoreSyncer: AppStoreSyncer {
    var syncCallCount = 0
    var syncShouldThrowError: Error?

    func sync() async throws {
        syncCallCount += 1
        if let error = syncShouldThrowError {
            throw error
        }
    }

    func reset() {
        syncCallCount = 0
        syncShouldThrowError = nil
    }
}
