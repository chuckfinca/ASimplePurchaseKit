//
//  PurchaseProtocols.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/10/25.
//

import Foundation
import StoreKit

// MARK: - Product-related Protocols (NEW)

public protocol PromotionalOfferProtocol: Sendable {
    var id: String? { get } // StoreKit.Product.SubscriptionOffer.id (iOS 17.4+)
    var displayName: String { get }
    var price: Decimal { get }
    var paymentMode: Product.SubscriptionOffer.PaymentMode { get }
    var period: Product.SubscriptionPeriod { get }
    var type: Product.SubscriptionOffer.OfferType { get }
}

public protocol SubscriptionInfoProtocol: Sendable {
    var subscriptionGroupID: String { get }
    var promotionalOffers: [PromotionalOfferProtocol] { get }
    var subscriptionPeriod: Product.SubscriptionPeriod { get }
}

public protocol ProductProtocol: Identifiable, Sendable where ID == String {
    var id: String { get }
    var type: Product.ProductType { get }
    var displayName: String { get }
    var description: String { get }
    var displayPrice: String { get }
    var price: Decimal { get }
    var isFamilyShareable: Bool { get }
    var subscription: SubscriptionInfoProtocol? { get }

    // Store the original StoreKit.Product if this is an adapter
    // This is for internal use by PurchaseService to pass to the Purchaser protocol.
    // Not strictly part of the public protocol surface area for consumers,
    // but a practical way to manage the underlying StoreKit type.
    var underlyingStoreKitProduct: Product? { get }
}

// MARK: - Core Purchase Flow Protocols

// Protocol for fetching product information
@MainActor
public protocol ProductProvider {
    func fetchProducts(for ids: [String]) async throws -> [any ProductProtocol]
}

// Protocol for handling the purchase flow
@MainActor
public protocol Purchaser {
    /// Initiates the purchase flow for a given product, optionally with a specific promotional offer.
    /// - Parameters:
    ///   - product: The `StoreKit.Product` to purchase.
    ///   - offerIdentifier: An optional identifier for a specific promotional offer.
    ///     This typically corresponds to `StoreKit.Product.SubscriptionOffer.id` (available iOS 17.4+).
    /// - Returns: A verified `Transaction`.
    /// - Throws: A `PurchaseError` or underlying StoreKit error if the purchase fails.
    func purchase(_ product: Product, offerIdentifier: String?) async throws -> Transaction
    func getAllTransactions() async throws -> [Transaction]
}

// Protocol for validating receipts/transactions
@MainActor
public protocol ReceiptValidator {
    /// Verifies a transaction and returns the current entitlement status.
    func validate(transaction: Transaction) async throws -> EntitlementStatus
    
    /// Checks all current entitlements to determine the user's status.
    func checkCurrentEntitlements() async throws -> EntitlementStatus
}

// MARK: - Delegate Protocol (NEW)

public enum LogLevel: Sendable {
    case debug, info, warning, error
}

public protocol PurchaseServiceDelegate: AnyObject, Sendable {
    func purchaseService(didLog event: String, level: LogLevel, context: [String: String]?)
}
