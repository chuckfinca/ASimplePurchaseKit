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
    func fetchProducts(for ids: [String]) async throws -> [any ProductProtocol] {
        do {
            let storeKitProducts = try await Product.products(for: ids)
            if storeKitProducts.isEmpty {
                print("LivePurchaseProvider: No products found for the given IDs.")
                throw PurchaseError.productsNotFound
            }
            return storeKitProducts.map { StoreKitProductAdapter(product: $0) }
        } catch {
            print("LivePurchaseProvider: Failed to fetch products: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Purchaser

    // Helper function for purchase refactor
    private func handlePurchaseVerificationResult(_ verificationResult: VerificationResult<Transaction>) throws -> Transaction {
        switch verificationResult {
        case .verified(let transaction):
            print("LivePurchaseProvider: Purchase successful and verified for product: \(transaction.productID)")
            return transaction
        case .unverified(_, let verificationError):
            print("🔴 LivePurchaseProvider: Purchase failed verification: \(verificationError.localizedDescription)")
            throw PurchaseError.verificationFailed(verificationError)
        }
    }


    /// Initiates the purchase flow for a given product, optionally with a specific promotional offer.
    func purchase(_ product: Product, offerIdentifier: String? = nil) async throws -> Transaction {
        let result: Product.PurchaseResult
        var purchaseOptions: Set<Product.PurchaseOption> = []

        if let offerID = offerIdentifier, product.type == .autoRenewable {
            var foundSKOffer: Product.SubscriptionOffer? = nil

            if #available(iOS 17.4, macOS 14.4, *) { // For offer.id
                foundSKOffer = product.subscription?.promotionalOffers.first { $0.id == offerID }
            } else {
                // On older OS, offer.id is not available.
                // We might still find *an* skOffer if it's the main introductory offer
                // and the offerID provided happened to be for that (though matching by ID is better).
                if product.subscription?.introductoryOffer != nil {
                    // This is a simplification; without offer.id, robustly matching a specific
                    // offerID to a specific offer object is hard on older OS.
                    // We'll assume if an offerID is passed on old OS, and there's an intro offer,
                    // the intent might be for that intro offer. StoreKit might apply it by default anyway.
                    foundSKOffer = product.subscription?.introductoryOffer
                    if foundSKOffer != nil {
                        print("LivePurchaseProvider: Found product's main introductory offer on older OS without explicit ID matching (offerID: \(offerID) was provided).")
                    }
                }
                if foundSKOffer == nil {
                    print("LivePurchaseProvider: Attempting to use offerID '\(offerID)' on an OS version older than iOS 17.4/macOS 14.4. Matching by offer.id is not available. Specific offer may not be applied.")
                }
            }

            if let skOffer = foundSKOffer {
                let offerDescriptionForLog = "type: \(skOffer.type), paymentMode: \(skOffer.paymentMode), price: \(skOffer.price), period: \(skOffer.period.unit) \(skOffer.period.value)"
                print("LivePurchaseProvider: Found matching StoreKit promotional offer (ID: \(offerID), Details: \(offerDescriptionForLog)).")

                // === XCODE 16.4 SDK REGRESSION HANDLING ===
                // As of Xcode 16.4 (stable) and its bundled SDK (likely targeting iOS 18.4 or slightly earlier if 18.5 isn't fully baked in),
                // the standard PurchaseOption cases for applying client-side offers are problematic:
                // 1. `.promotionalOffer(offer: Product.SubscriptionOffer, signature: Product.SubscriptionOffer.Signature?)`
                //    - The compiler fails to resolve this overload, expecting `offerID: String` instead.
                // 2. `.introductory`
                //    - The compiler reports this case as not being a member of Product.PurchaseOption.
                //
                // This is a known issue/regression in the SDK provided with Xcode 16.4.
                // This means we cannot reliably apply a *specific* client-side offer programmatically in this environment.
                // The purchase will proceed without these specific options. StoreKit *may* still apply
                // a default introductory offer if the user is eligible.

                print("🔴 Xcode 16.4 SDK Limitation: Due to issues with StoreKit's Product.PurchaseOption API in the current SDK, ASimplePurchaseKit cannot programmatically apply the specific promotional offer (ID: \(offerID)). The purchase will proceed as a standard purchase. StoreKit may still apply a default introductory offer if eligible. Please monitor Apple SDK updates (e.g., for Xcode 16.5+ / iOS 18.5+) for fixes to these APIs. Reference ASimplePurchaseKit documentation for more details (P7).")

                // The following lines, which are the correct API calls, are commented out
                // because they are reported to cause build failures in Xcode 16.4 stable.
                // When a fixed SDK is available, these should be re-enabled with appropriate #available checks if necessary.
                /*
                    if let introOffer = product.subscription?.introductoryOffer, skOffer == introOffer {
                        // This would be the path if .introductory was available
                        // purchaseOptions.insert(.introductory)
                    } else {
                        // This would be the path if .promotionalOffer(offer:signature:?) was available
                        // let optionToAdd: Product.PurchaseOption = Product.PurchaseOption.promotionalOffer(
                        //     offer: skOffer,
                        //     signature: nil as Product.SubscriptionOffer.Signature?
                        // )
                        // purchaseOptions.insert(optionToAdd)
                    }
                    */

                // Since we cannot set the options, `purchaseOptions` will remain empty for the offer.
                // The purchase call below will proceed without specific offer options.

            } else {
                print("⚠️ LivePurchaseProvider: Promotional offer with ID '\(offerID)' not found for product '\(product.id)'. Proceeding with standard purchase.")
            }
        }

        // Perform the purchase
        do {
            if !purchaseOptions.isEmpty { // This block will likely not be hit for offers in Xcode 16.4
                print("LivePurchaseProvider: Purchasing productID '\(product.id)' with specific options: \(purchaseOptions.map { String(describing: $0) }).")
                result = try await product.purchase(options: purchaseOptions)
            } else {
                let contextMessage = offerIdentifier != nil ? "(Note: Specific offer application might be affected by current Xcode/SDK limitations)" : ""
                print("LivePurchaseProvider: Purchasing productID '\(product.id)' with no specific purchase options. \(contextMessage)")
                result = try await product.purchase()
            }
        } catch {
            let offerContext = offerIdentifier != nil ? " with offerID '\(offerIdentifier!)'" : ""
            print("🔴 LivePurchaseProvider: product.purchase() for productID '\(product.id)'\(offerContext) threw an error directly: \(error). Error Type: \(type(of: error)). This error will be re-thrown.")
            throw error
        }

        switch result {
        case .success(let verificationResult):
            return try handlePurchaseVerificationResult(verificationResult)
        case .pending:
            print("ℹ️ LivePurchaseProvider: Purchase is pending user action for productID: \(product.id).")
            throw PurchaseError.purchasePending
        case .userCancelled:
            let offerContext = offerIdentifier != nil ? " with offerID '\(offerIdentifier!)'" : ""
            print("ℹ️ LivePurchaseProvider: User cancelled purchase (via Product.PurchaseResult.userCancelled) for productID: \(product.id)\(offerContext).")
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
                print("LivePurchaseProvider: Encountered unverified transaction \(unverifiedTransaction.id) during getAllTransactions: \(verificationError.localizedDescription)")
            }
        }
        print("LivePurchaseProvider: Fetched \(allTransactions.count) verified transactions from Transaction.all.")
        return allTransactions
    }



    // MARK: - ReceiptValidator

    func checkCurrentEntitlements() async throws -> EntitlementStatus {
        var highestPriorityTransaction: Transaction? = nil
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }
            if let current = highestPriorityTransaction {
                if transaction.purchaseDate > current.purchaseDate {
                    highestPriorityTransaction = transaction
                }
            } else {
                highestPriorityTransaction = transaction
            }
        }

        guard let finalTransaction = highestPriorityTransaction else {
            print("LivePurchaseProvider: No active entitlements found.")
            return .notSubscribed
        }
        return try await self.validate(transaction: finalTransaction)
    }

    func validate(transaction: Transaction) async throws -> EntitlementStatus {
        if transaction.revocationDate != nil || transaction.isUpgraded {
            return .notSubscribed
        }

        switch transaction.productType {
        case .autoRenewable:
            guard let expirationDate = transaction.expirationDate else {
                return .unknown
            }
            let subscriptionStatus = await transaction.subscriptionStatus
            let currentSubscriptionState = subscriptionStatus?.state
            var isInGracePeriod = false
            if let state = currentSubscriptionState, state == .inGracePeriod {
                isInGracePeriod = true
            }
            return .subscribed(expires: expirationDate, isInGracePeriod: isInGracePeriod)

        case .nonConsumable, .nonRenewable:
            // Non-consumables and non-renewing subscriptions grant a persistent entitlement.
            return .subscribed(expires: nil, isInGracePeriod: false)

        case .consumable:
            // Consumables are single-use and do not grant a persistent entitlement.
            // The app grants the item and then finishes the transaction.
            return .notSubscribed

        default:
            // Handle any future product types Apple might introduce.
            return .notSubscribed
        }

    }
}
