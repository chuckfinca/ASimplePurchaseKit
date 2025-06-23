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

// MARK: - Mock Product Implementations (NEW)

public struct MockPromotionalOffer: PromotionalOfferProtocol, Hashable, Sendable {
    public var id: String?
    public var displayName: String // Ensure this is a valid String, e.g., "7-day free trial"
    public var price: Decimal
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
    public init(id: String? = nil, displayName: String = "Test Offer", price: Decimal = 0.0, paymentMode: Product.SubscriptionOffer.PaymentMode = .freeTrial, period: Product.SubscriptionPeriod = .weekly, type: Product.SubscriptionOffer.OfferType = .introductory) {
        self.id = id
        self.displayName = displayName
        self.price = price
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
    public static func newAutoRenewable(id: String, displayName: String = "Mock Subscription", groupID: String = "group1", period: Product.SubscriptionPeriod = .monthly) -> MockProduct {
        MockProduct(id: id,
                    type: .autoRenewable,
                    displayName: displayName,
                    subscription: MockSubscriptionInfo(subscriptionGroupID: groupID, subscriptionPeriod: period)
        )
    }

    public static func newNonConsumable(id: String, displayName: String = "Mock Lifetime") -> MockProduct {
        MockProduct(id: id, type: .nonConsumable, displayName: displayName)
    }
}


@MainActor
class MockPurchaseProvider: ProductProvider, Purchaser, ReceiptValidator {

    // ... (rest of MockPurchaseProvider remains the same) ...
    // MARK: - Controllable Test Properties

    // Controls what fetchProducts() returns
    var productsResult: Result<[ProductProtocol], Error> = .success([]) // Changed to ProductProtocol

    // Controls what purchase() returns
    var purchaseResult: Result<Transaction, Error> = .failure(PurchaseError.unknown)

    // Controls what validate() and checkCurrentEntitlements() return
    var entitlementResult: Result<EntitlementStatus, Error> = .success(.notSubscribed)

    // Controls what getAllTransactions() returns
    var allTransactionsResult: Result<[Transaction], Error> = .success([])


    // MARK: - Call Counts for Assertions

    var fetchProductsCallCount = 0
    var purchaseCallCount = 0
    var validateCallCount = 0
    var checkCurrentEntitlementsCallCount = 0
    var getAllTransactionsCallCount = 0


    // MARK: - Protocol Implementations

    func fetchProducts(for ids: [String]) async throws -> [ProductProtocol] { // Changed
        fetchProductsCallCount += 1
        return try productsResult.get()
    }

    func purchase(_ product: Product) async throws -> Transaction {
        purchaseCallCount += 1
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

    func getAllTransactions() async throws -> [Transaction] { // NEW
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
        validateCallCount = 0
        checkCurrentEntitlementsCallCount = 0
        getAllTransactionsCallCount = 0
    }
}

extension Transaction {
    static func makeMock(productID: String = "mock.product.id",
                         purchaseDate: Date = Date(),
                         productType: Product.ProductType = .autoRenewable,
                         expiresDate: Date? = Calendar.current.date(byAdding: .month, value: 1, to: Date()),
                         originalID: UInt64 = UInt64.random(in: 1000...9999)) throws -> Transaction {
        print("⚠️ Transaction.makeMock is a conceptual placeholder. Real Transaction instances are hard to mock fully.")
        throw NSError(domain: "MockTransactionError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create a fully mock Transaction object for unit tests easily."])
    }
}
