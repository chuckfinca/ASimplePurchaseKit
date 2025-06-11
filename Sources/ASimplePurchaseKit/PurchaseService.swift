//
//  Untitled.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/10/25.
//

import Foundation
import StoreKit
import Combine

@MainActor
public class PurchaseService: ObservableObject {

    // MARK: - Published State
    @Published public private(set) var availableProducts: [Product] = []
    @Published public private(set) var entitlementStatus: EntitlementStatus = .unknown
    @Published public private(set) var isPurchasing: Bool = false
    @Published public private(set) var lastError: PurchaseError?

    // MARK: - Dependencies (Internal)
    private let productProvider: ProductProvider
    private let purchaser: Purchaser
    private let receiptValidator: ReceiptValidator

    // MARK: - Private State
    private let productIDs: [String]
    private var transactionListener: Task<Void, Error>? = nil

    // MARK: - Initialization

    /// The public initializer for production use.
    /// It automatically sets up the live provider to connect to StoreKit.
    public convenience init(config: PurchaseConfig) {
        let liveProvider = LivePurchaseProvider()
        self.init(
            productIDs: config.productIDs,
            productProvider: liveProvider,
            purchaser: liveProvider,
            receiptValidator: liveProvider
        )
    }

    /// The internal initializer for dependency injection and testing.
    internal init(
        productIDs: [String],
        productProvider: ProductProvider,
        purchaser: Purchaser,
        receiptValidator: ReceiptValidator
    ) {
        self.productIDs = productIDs
        self.productProvider = productProvider
        self.purchaser = purchaser
        self.receiptValidator = receiptValidator

        // ** CRITICAL: Start the transaction listener that runs for the app's lifetime **
        self.transactionListener = Task.detached { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(transactionResult: result)
            }
        }

        // Initial setup
        Task {
            await fetchProducts()
            await updateEntitlementStatus()
        }
    }

    deinit {
        // ** CRITICAL: Clean up the listener on deinit **
        transactionListener?.cancel()
    }

    // MARK: - Public API

    /// Fetches the list of products from the App Store based on the initial configuration.
    public func fetchProducts() async {
        do {
            self.availableProducts = try await productProvider.fetchProducts(for: productIDs)
        } catch {
            self.lastError = .productsNotFound
        }
    }

    /// Initiates a purchase for a given product and handles the result.
    public func purchase(_ product: Product) async {
        guard !isPurchasing else {
            self.lastError = .purchasePending
            return
        }

        isPurchasing = true
        self.lastError = nil

        do {
            let transaction = try await purchaser.purchase(product)
            self.entitlementStatus = try await receiptValidator.validate(transaction: transaction)
            await transaction.finish() // Acknowledge the transaction
        } catch let e as PurchaseError {
            self.lastError = e
        } catch {
            self.lastError = .unknown
        }

        isPurchasing = false
    }

    /// Asks the App Store to sync the latest transactions for the user.
    public func restorePurchases() async {
        do {
            try await AppStore.sync()
            // The transaction listener will automatically handle any new transactions.
            // We can also trigger a manual check to update the state immediately.
            await updateEntitlementStatus()
        } catch {
            self.lastError = .unknown
        }
    }

    /// Manually triggers a check of the user's current entitlements.
    public func updateEntitlementStatus() async {
        do {
            self.entitlementStatus = try await receiptValidator.checkCurrentEntitlements()
        } catch let e as PurchaseError {
            self.lastError = e
        } catch {
            self.lastError = .unknown
        }
    }

    // MARK: - Private Helpers

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        do {
            let transaction: Transaction
            switch transactionResult {
            case .unverified(_, let error):
                throw PurchaseError.verificationFailed(error)
            case .verified(let trans):
                transaction = trans
            }

            // A background transaction was received (e.g., renewal, promo code).
            // Validate it and update the user's status.
            self.entitlementStatus = try await receiptValidator.validate(transaction: transaction)

            // ** CRITICAL: Always finish the transaction **
            await transaction.finish()

        } catch let e as PurchaseError {
            self.lastError = e
        } catch {
            self.lastError = .unknown
        }
    }
}
