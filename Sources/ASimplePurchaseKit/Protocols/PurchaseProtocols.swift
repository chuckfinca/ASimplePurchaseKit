//
//  PurchaseProtocols.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/10/25.
//

import Foundation
import StoreKit

// MARK: - Product-related Protocols

/// A protocol representing promotional offers for subscription products.
///
/// Promotional offers include introductory prices, free trials, and other
/// special pricing available for subscription products.
///
/// ## Usage
/// ```swift
/// let offers = purchaseService.eligiblePromotionalOffers(for: product)
/// for offer in offers {
///     print("Offer: \(offer.displayName) - \(offer.displayPrice)")
/// }
/// ```
public protocol PromotionalOfferProtocol: Sendable {
    /// The unique identifier for this promotional offer.
    ///
    /// Available in iOS 17.4+ through StoreKit.Product.SubscriptionOffer.id.
    /// May be `nil` for older iOS versions or certain offer types.
    var id: String? { get }

    /// The display name for this promotional offer.
    ///
    /// This is a human-readable name that can be shown to users,
    /// such as "Free Trial" or "50% Off First Month".
    var displayName: String { get }

    /// The price of this promotional offer.
    ///
    /// For free trials, this will typically be 0.
    var price: Decimal { get }

    /// The payment mode for this promotional offer.
    ///
    /// Indicates how the offer is applied (e.g., free trial, pay as you go, pay up front).
    var paymentMode: Product.SubscriptionOffer.PaymentMode { get }

    /// The billing period for this promotional offer.
    ///
    /// Defines how long the promotional pricing lasts.
    var period: Product.SubscriptionPeriod { get }

    /// The type of this promotional offer.
    ///
    /// Distinguishes between introductory offers and promotional offers.
    var type: Product.SubscriptionOffer.OfferType { get }
}

/// A protocol representing subscription information for a product.
///
/// This protocol provides details about subscription products, including
/// their billing periods, subscription groups, and available promotional offers.
public protocol SubscriptionInfoProtocol: Sendable {
    /// The subscription group identifier.
    ///
    /// Products in the same subscription group are mutually exclusive.
    /// Users can only have one active subscription per group.
    var subscriptionGroupID: String { get }

    /// The promotional offers available for this subscription.
    ///
    /// These may include introductory pricing, free trials, or other special offers.
    var promotionalOffers: [PromotionalOfferProtocol] { get }

    /// The billing period for this subscription.
    ///
    /// Defines how often the user is charged (e.g., monthly, yearly).
    var subscriptionPeriod: Product.SubscriptionPeriod { get }
}

/// A protocol representing a product available for purchase.
///
/// This protocol abstracts StoreKit's Product type to enable testing
/// and provide a consistent interface for all product types.
///
/// ## Usage
/// ```swift
/// for product in purchaseService.availableProducts {
///     print("\(product.displayName): \(product.displayPrice)")
///     if product.type == .autoRenewable {
///         // Handle subscription product
///     }
/// }
/// ```
public protocol ProductProtocol: Identifiable, Sendable where ID == String {
    /// The unique product identifier.
    ///
    /// This matches the Product ID configured in App Store Connect.
    var id: String { get }

    /// The type of this product.
    ///
    /// Indicates whether this is a consumable, non-consumable, or subscription product.
    var type: Product.ProductType { get }

    /// The localized display name for this product.
    ///
    /// This is the name shown to users in your app's interface.
    var displayName: String { get }

    /// The localized description of this product.
    ///
    /// Provides detailed information about what the product offers.
    var description: String { get }

    /// The localized price string for this product.
    ///
    /// Formatted according to the user's locale and App Store region.
    /// Example: "$9.99" or "€8.99"
    var displayPrice: String { get }

    /// The price of this product as a decimal value.
    ///
    /// This is the raw price value without currency formatting.
    var price: Decimal { get }

    /// Whether this product supports Family Sharing.
    ///
    /// When `true`, family members can access this purchase without
    /// additional cost.
    var isFamilyShareable: Bool { get }

    /// Subscription information for this product.
    ///
    /// Only available for subscription products. `nil` for other product types.
    var subscription: SubscriptionInfoProtocol? { get }
}

// MARK: - Core Purchase Flow Protocols

/// A protocol for fetching product information from the App Store.
///
/// This protocol abstracts the product fetching process to enable testing
/// and provide flexibility in how products are retrieved.
@MainActor
public protocol ProductProvider {
    /// Fetches products for the specified product identifiers.
    ///
    /// - Parameter ids: An array of product identifiers to fetch from the App Store.
    /// - Returns: An array of products that match the requested identifiers.
    /// - Throws: `PurchaseError` if the products cannot be fetched.
    func fetchProducts(for ids: [String]) async throws -> [any ProductProtocol]
}

/// A protocol for handling the purchase flow.
///
/// This protocol abstracts the purchase process to enable testing
/// and provide flexibility in how purchases are processed.
@MainActor
public protocol Purchaser {
    /// Initiates the purchase flow for a given product.
    ///
    /// - Parameters:
    ///   - product: The `StoreKit.Product` to purchase.
    ///   - offerIdentifier: An optional identifier for a specific promotional offer.
    ///     This typically corresponds to `StoreKit.Product.SubscriptionOffer.id` (available iOS 17.4+).
    /// - Returns: A verified `Transaction` representing the completed purchase.
    /// - Throws: `PurchaseError` or underlying StoreKit error if the purchase fails.
    func purchase(_ product: Product, offerIdentifier: String?) async throws -> Transaction

    /// Retrieves all transactions for the current user.
    ///
    /// - Returns: An array of all transactions associated with the user's Apple ID.
    /// - Throws: `PurchaseError` if transactions cannot be retrieved.
    func getAllTransactions() async throws -> [Transaction]
}

/// A protocol for validating receipts and transactions.
///
/// This protocol abstracts the validation process to enable testing
/// and provide flexibility in how entitlements are verified.
@MainActor
public protocol ReceiptValidator {
    /// Verifies a transaction and returns the current entitlement status.
    ///
    /// - Parameter transaction: The transaction to validate.
    /// - Returns: The user's entitlement status after validating the transaction.
    /// - Throws: `PurchaseError` if validation fails.
    func validate(transaction: Transaction) async throws -> EntitlementStatus

    /// Checks all current entitlements to determine the user's status.
    ///
    /// This method examines all active transactions and subscriptions
    /// to determine the user's current entitlement status.
    ///
    /// - Returns: The user's current entitlement status.
    /// - Throws: `PurchaseError` if entitlements cannot be determined.
    func checkCurrentEntitlements() async throws -> EntitlementStatus
}

// MARK: - Delegate Protocol

/// An enumeration describing the severity level of a log event.
public enum LogLevel: Sendable {
    /// Detailed information for debugging purposes.
    case debug
    /// General information about the service's state and operations.
    case info
    /// Indicates a potential issue or unexpected state that does not constitute an error.
    case warning
    /// Indicates an error that prevented an operation from completing successfully.
    case error
}

/// A delegate protocol for receiving events and logs from the `PurchaseService`.
///
/// Conform to this protocol to integrate the library's logging with your own analytics
/// or debugging systems.
///
/// ## Usage
/// ```swift
/// class MyAppAnalytics: PurchaseServiceDelegate {
///     func purchaseService(didLog event: String, level: LogLevel, context: [String: String]?) {
///         // Example: Send to a custom logging service
///         MyLogger.log("[\(level)] ASimplePurchaseKit: \(event)", properties: context)
///     }
/// }
///
/// // In your app setup:
/// let myDelegate = MyAppAnalytics()
/// purchaseService.delegate = myDelegate
/// ```
public protocol PurchaseServiceDelegate: AnyObject, Sendable {
    /// Called when the `PurchaseService` logs an event.
    ///
    /// - Parameters:
    ///   - event: A string describing the event that occurred.
    ///   - level: The severity level of the event.
    ///   - context: An optional dictionary providing additional context, such as `productID`, `operation`, or `errorDescription`.
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
