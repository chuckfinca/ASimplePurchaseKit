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
    // Add other relevant properties from StoreKit.Product.SubscriptionOffer as needed
}

public protocol SubscriptionInfoProtocol: Sendable {
    var subscriptionGroupID: String { get }
    var promotionalOffers: [PromotionalOfferProtocol] { get }
    var subscriptionPeriod: Product.SubscriptionPeriod { get }
    // Add other relevant properties from StoreKit.Product.SubscriptionInfo as needed
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
    func fetchProducts(for ids: [String]) async throws -> [ProductProtocol] // Changed to ProductProtocol
}

// Protocol for handling the purchase flow
@MainActor
public protocol Purchaser {
    func purchase(_ product: Product) async throws -> Transaction // Stays StoreKit.Product
    func getAllTransactions() async throws -> [Transaction] // NEW
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
    // func purchaseService(didUpdateMetrics: PurchaseMetrics) // Future: For more detailed metrics
}