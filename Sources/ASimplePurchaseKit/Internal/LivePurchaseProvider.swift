//
//  LivePurchaseProvider.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/10/25.
//

import Foundation
import StoreKit

/// The concrete implementation of the purchase protocols that interacts directly with Apple's StoreKit framework.
/// This class is internal to the library. The app will only interact with `PurchaseService`.
@MainActor
internal class LivePurchaseProvider: ProductProvider, Purchaser, ReceiptValidator {

    // MARK: - ProductProvider
    
    /// Fetches product information from the App Store.
    func fetchProducts(for ids: [String]) async throws -> [Product] {
        do {
            let products = try await Product.products(for: ids)
            if products.isEmpty {
                print("LivePurchaseProvider: No products found for the given IDs.")
                throw PurchaseError.productsNotFound
            }
            return products
        } catch {
            print("LivePurchaseProvider: Failed to fetch products: \(error.localizedDescription)")
            // Re-throw the original error, PurchaseService will handle wrapping if needed.
            throw error
        }
    }
    
    // MARK: - Purchaser
    
    /// Initiates the purchase flow for a given product.
    func purchase(_ product: Product) async throws -> Transaction {
        let result = try await product.purchase()

        // The purchase flow can result in success, cancellation, or a pending state.
        switch result {
        case .success(let verificationResult):
            // The purchase was successful. Now we must verify the transaction's signature.
            switch verificationResult {
            case .verified(let transaction):
                // The transaction is cryptographically verified by Apple. This is the success case.
                print("LivePurchaseProvider: Purchase successful and verified for product: \(transaction.productID)")
                return transaction
            case .unverified(_, let verificationError):
                // The transaction signature is invalid. This could be a security issue.
                print("LivePurchaseProvider: Purchase failed verification: \(verificationError.localizedDescription)")
                throw PurchaseError.verificationFailed(verificationError)
            }
            
        case .pending:
            // The purchase requires approval (e.g., Ask to Buy). The app should wait for a transaction update.
            print("LivePurchaseProvider: Purchase is pending user action.")
            throw PurchaseError.purchasePending
            
        case .userCancelled:
            // The user explicitly cancelled the purchase.
            print("LivePurchaseProvider: User cancelled purchase.")
            throw PurchaseError.purchaseCancelled
            
        @unknown default:
            throw PurchaseError.unknown
        }
    }
    
    // MARK: - ReceiptValidator
    
    /// Checks all of the user's current entitlements to determine their access level.
    /// This is the source of truth for "is the user subscribed?".
    func checkCurrentEntitlements() async throws -> EntitlementStatus {
        var highestPriorityTransaction: Transaction? = nil

        // Iterate through all of the user's currently entitled transactions.
        // This includes active subscriptions and non-consumable IAPs.
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                // Ignore unverified transactions for security.
                continue
            }
            
            // For this implementation, we assume any valid transaction is the one we care about.
            // A more complex app could check `productID` for different subscription tiers.
            // We'll just find the most recent one.
            if let current = highestPriorityTransaction {
                if transaction.purchaseDate > current.purchaseDate {
                    highestPriorityTransaction = transaction
                }
            } else {
                highestPriorityTransaction = transaction
            }
        }
        
        guard let finalTransaction = highestPriorityTransaction else {
            // No active entitlements were found for the user.
            print("LivePurchaseProvider: No active entitlements found.")
            return .notSubscribed
        }
        
        // We found a valid entitlement. Now, convert its state into our EntitlementStatus enum.
        return try await self.validate(transaction: finalTransaction)
    }
    
    /// Converts a single verified transaction into a specific entitlement status.
    func validate(transaction: Transaction) async throws -> EntitlementStatus {
        // A transaction is not an entitlement if it has been revoked or is for an upgraded product.
        if transaction.revocationDate != nil || transaction.isUpgraded {
            return .notSubscribed
        }
        
        switch transaction.productType {
        case .autoRenewable:
            // This is a subscription. We need to check its current state.
            guard let subInfo = transaction.subscriptionInfo,
                  let state = subInfo.state else {
                // Should not happen for an auto-renewable product with a verified transaction.
                return .unknown
            }
            
            switch state {
            case .subscribed:
                return .subscribed(expires: transaction.expirationDate, isInGracePeriod: false)
            case .inGracePeriod:
                return .subscribed(expires: transaction.expirationDate, isInGracePeriod: true)
            case .expired, .inBillingRetryPeriod, .revoked:
                return .notSubscribed
            @unknown default:
                return .unknown
            }
            
        case .nonConsumable, .nonRenewing:
            // These products grant a lifetime entitlement once purchased.
            return .subscribed(expires: nil, isInGracePeriod: false)
            
        default:
            // Consumable products do not grant an ongoing entitlement.
            return .notSubscribed
        }
    }
}
