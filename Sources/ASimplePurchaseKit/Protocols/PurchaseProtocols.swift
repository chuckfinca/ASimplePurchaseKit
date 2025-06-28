//
//  PurchaseProtocols.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/10/25.
//

import Foundation
import StoreKit

// MARK: - Product-related Protocols

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

// MARK: - Delegate Protocol

public enum LogLevel: Sendable {
    case debug, info, warning, error
}

public protocol PurchaseServiceDelegate: AnyObject, Sendable {
    func purchaseService(didLog event: String, level: LogLevel, context: [String: String]?)
}

// MARK: - System Service Protocols

/// A protocol that abstracts the behavior of listening for transaction updates.
/// This allows for a mock implementation during unit tests.
@MainActor
public protocol TransactionListenerProvider {
    /// Starts a listener that provides transaction updates.
    /// - Parameter updateHandler: A closure to be called with each new transaction result.
    /// - Returns: A `Task` handle for the listening process, which can be cancelled.
    func listenForTransactions(updateHandler: @escaping @Sendable (VerificationResult<Transaction>) async -> Void) -> Task<Void, Error>
}

/// A protocol that abstracts the App Store sync action.
/// This allows for a mock implementation during unit tests.
@MainActor
public protocol AppStoreSyncer {
    /// Initiates a sync with the App Store to check for new transactions.
    func sync() async throws
}
