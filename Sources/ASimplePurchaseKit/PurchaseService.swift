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
            receiptValidator: liveProvider,
            isUnitTesting: config.isUnitTesting
        )
    }

    /// The internal initializer for dependency injection and testing.
    internal init(
        productIDs: [String],
        productProvider: ProductProvider,
        purchaser: Purchaser,
        receiptValidator: ReceiptValidator,
        isUnitTesting: Bool = false
    ) {
        self.productIDs = productIDs
        self.productProvider = productProvider
        self.purchaser = purchaser
        self.receiptValidator = receiptValidator

        // Only start the real transaction listener if we are NOT in a unit test.
        if !isUnitTesting { // <-- ADD THIS CHECK
            self.transactionListener = Task.detached { [weak self] in
                for await result in Transaction.updates {
                    await self?.handle(transactionResult: result)
                }
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
    public func purchase(productID: String) async {
        guard !isPurchasing else {
            self.lastError = .purchasePending
            return
        }

        // Find the product from our own state
        guard let productToPurchase = availableProducts.first(where: { $0.id == productID }) else {
            self.lastError = .productsNotFound
            print("PurchaseService: Attempted to purchase unknown productID: \(productID)")
            return
        }

        isPurchasing = true
        self.lastError = nil

        do {
            // Pass the *real* product object to the internal protocol
            let transaction = try await purchaser.purchase(productToPurchase)
            self.entitlementStatus = try await receiptValidator.validate(transaction: transaction)
            await transaction.finish()
        } catch let e as PurchaseError {
            self.lastError = e
        } catch {
            self.lastError = .unknown
        }

        isPurchasing = false
    }

    /// Asks the App Store to sync the latest transactions for the user.
    public func restorePurchases() async {
        // Only call the real AppStore.sync() if we are NOT in a unit test.
        if let listener = self.transactionListener { // A good proxy for not being in a unit test
            do {
                try await AppStore.sync()
            } catch {
                self.lastError = .unknown
                return // Exit early if sync fails
            }
        }

        // The rest of the logic can run in both unit and integration tests.
        await updateEntitlementStatus()
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
