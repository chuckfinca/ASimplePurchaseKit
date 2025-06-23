//
//  LivePurchaseProvider.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/10/25.
//

import Foundation
import StoreKit // No StoreKitTest import here

/// The concrete implementation of the purchase protocols that interacts directly with Apple's StoreKit framework.
/// This class is internal to the library. The app will only interact with `PurchaseService`.
@MainActor
internal class LivePurchaseProvider: ProductProvider, Purchaser, ReceiptValidator {

    // MARK: - ProductProvider

    /// Fetches product information from the App Store.
    func fetchProducts(for ids: [String]) async throws -> [ProductProtocol] { // Changed return type
        do {
            let storeKitProducts = try await Product.products(for: ids)
            if storeKitProducts.isEmpty {
                print("LivePurchaseProvider: No products found for the given IDs.")
                throw PurchaseError.productsNotFound
            }
            // Adapt StoreKit.Product to ProductProtocol
            return storeKitProducts.map { StoreKitProductAdapter(product: $0) }
        } catch {
            print("LivePurchaseProvider: Failed to fetch products: \(error.localizedDescription)")
            // Re-throw the original error, PurchaseService will handle wrapping if needed.
            throw error
        }
    }

    // MARK: - Purchaser

    // Helper function for purchase refactor
    private func handlePurchaseVerificationResult(_ verificationResult: VerificationResult<Transaction>) throws -> Transaction {
        switch verificationResult {
        case .verified(let transaction):
            // The transaction is cryptographically verified by Apple. This is the success case.
            print("LivePurchaseProvider: Purchase successful and verified for product: \(transaction.productID)")
            return transaction
        case .unverified(_, let verificationError):
            // The transaction signature is invalid. This could be a security issue.
            print("🔴 LivePurchaseProvider: Purchase failed verification: \(verificationError.localizedDescription)")
            throw PurchaseError.verificationFailed(verificationError)
        }
    }
    
    /// Initiates the purchase flow for a given product.
    func purchase(_ product: Product) async throws -> Transaction { // Parameter remains StoreKit.Product
        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch { // Catch block for ANY error from product.purchase()
            print("🔴 LivePurchaseProvider: product.purchase() for productID '\(product.id)' threw an error directly: \(error). Error Type: \(type(of: error)). This error will be re-thrown.")
            throw error // Re-throw the original error. PurchaseService will handle it.
        }

        // The purchase flow can result in success, cancellation, or a pending state.
        switch result {
        case .success(let verificationResult):
            return try handlePurchaseVerificationResult(verificationResult)
        case .pending:
            print("ℹ️ LivePurchaseProvider: Purchase is pending user action for productID: \(product.id).")
            throw PurchaseError.purchasePending
        case .userCancelled:
            print("ℹ️ LivePurchaseProvider: User cancelled purchase (via Product.PurchaseResult.userCancelled) for productID: \(product.id).")
            throw PurchaseError.purchaseCancelled
        @unknown default:
            print("🔴 LivePurchaseProvider: product.purchase() returned an unknown default case for productID: \(product.id).")
            throw PurchaseError.unknown
        }
    }
    
    /// Fetches all transactions for the user.
    func getAllTransactions() async throws -> [Transaction] {
        var allTransactions: [Transaction] = []
        for await result in Transaction.all {
            switch result {
            case .verified(let transaction):
                allTransactions.append(transaction)
            case .unverified(let unverifiedTransaction, let verificationError):
                // Log or handle unverified transactions if necessary, but typically ignore for entitlement.
                print("LivePurchaseProvider: Encountered unverified transaction \(unverifiedTransaction.id) during getAllTransactions: \(verificationError.localizedDescription)")
                // Depending on policy, you might still want to include them or throw an error.
                // For now, we'll only collect verified ones.
            }
        }
        print("LivePurchaseProvider: Fetched \(allTransactions.count) verified transactions from Transaction.all.")
        return allTransactions
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
        // A transaction is not an entitlement if it has been revoked by Apple or is for an upgraded product.
        if transaction.revocationDate != nil || transaction.isUpgraded {
            return .notSubscribed
        }

        switch transaction.productType {
        case .autoRenewable:
            // For auto-renewable subscriptions, the source of truth is the expiration date.
            // StoreKit's `currentEntitlements` will provide a transaction if it's active.
            // This includes active subscriptions and those in a grace period.
            guard let expirationDate = transaction.expirationDate else {
                // A verified auto-renewable subscription from `currentEntitlements` must have an expiration date.
                // If it doesn't, we can't determine the status.
                return .unknown
            }

            let subscriptionStatus = await transaction.subscriptionStatus
            let currentSubscriptionState = subscriptionStatus?.state

            // Clarified comment and logic check:
            // A subscription is in a grace period if:
            // 1. StoreKit reports its state as `.inGracePeriod`.
            // 2. Its `expirationDate` has passed (otherwise, it's just regularly active).
            // `Transaction.currentEntitlements` should continue to return transactions in a grace period.
            // The `expirationDate < Date()` check confirms that we are past the original expiry,
            // and `currentSubscriptionState == .inGracePeriod` confirms StoreKit's view.
            var isInGracePeriod = false
            if let state = currentSubscriptionState { // Ensure state is not nil
                 if state == .inGracePeriod && expirationDate < Date() {
                    isInGracePeriod = true
                 } else if state == .inGracePeriod && expirationDate >= Date() {
                    // This case might mean the grace period started *before* the expiration date for some reason
                    // or StoreKit considers it in grace for other reasons (e.g. billing issue ahead of expiry).
                    // Trust StoreKit's state if it says .inGracePeriod.
                    isInGracePeriod = true
                 }
            }


            return .subscribed(expires: expirationDate, isInGracePeriod: isInGracePeriod)

        case .nonConsumable, .nonRenewable:
            // These products grant a lifetime entitlement once purchased. They do not expire.
            return .subscribed(expires: nil, isInGracePeriod: false)

        default:
            // Consumable products do not grant an ongoing entitlement.
            return .notSubscribed
        }
    }
}