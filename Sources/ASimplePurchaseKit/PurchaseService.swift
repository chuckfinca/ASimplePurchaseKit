//
//  PurchaseService.swift // Original was Untitled.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/10/25.
//

import Foundation
import StoreKit
import Combine
//
//  PurchaseService.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/10/25.
//

import Foundation
import StoreKit
import Combine

public enum PurchaseState: Equatable, Sendable {
    case idle
    case fetchingProducts
    case purchasing(productID: String)
    case restoring
    case checkingEntitlement
}

@MainActor
public class PurchaseService: ObservableObject {

    // MARK: - Published State
    @Published public internal(set) var availableProducts: [ProductProtocol] = []
    @Published public internal(set) var entitlementStatus: EntitlementStatus = .unknown
    @Published public internal(set) var purchaseState: PurchaseState = .idle
    @Published public private(set) var lastFailure: PurchaseFailure?

    // MARK: - Dependencies
    private let productProvider: ProductProvider
    private let purchaser: Purchaser
    private let receiptValidator: ReceiptValidator
    public weak var delegate: PurchaseServiceDelegate?

    // MARK: - Private State
    private let productIDs: [String]
    private var transactionListener: Task<Void, Error>? = nil
    private let enableLogging: Bool
    private let isUnitTesting_prop: Bool

    // MARK: - Initialization
    public convenience init(config: PurchaseConfig) {
        let liveProvider = LivePurchaseProvider()
        self.init(
            productIDs: config.productIDs,
            productProvider: liveProvider,
            purchaser: liveProvider,
            receiptValidator: liveProvider,
            isUnitTesting: config.isUnitTesting,
            enableLogging: config.enableLogging
        )
    }

    internal init(
        productIDs: [String],
        productProvider: ProductProvider,
        purchaser: Purchaser,
        receiptValidator: ReceiptValidator,
        isUnitTesting: Bool = false,
        enableLogging: Bool = true
    ) {
        self.productIDs = productIDs
        self.productProvider = productProvider
        self.purchaser = purchaser
        self.receiptValidator = receiptValidator
        self.enableLogging = enableLogging
        self.isUnitTesting_prop = isUnitTesting

        log(.info, "Initializing PurchaseService. Unit testing: \(isUnitTesting), Product IDs: \(productIDs.joined(separator: ", ")).")

        if !isUnitTesting_prop {
            self.transactionListener = Task.detached { [weak self] in
                guard let self = self else { return }
                await self.logOnMainActor(.debug, "Transaction.updates listener starting.") // Changed message slightly for clarity
                do {
                    for await result in Transaction.updates {
                        await self.handle(transactionResult: result)
                    }
                    await self.logOnMainActor(.debug, "Transaction.updates listener ended normally.")
                } catch {
                    // This task is detached, errors here won't be caught by default by XCTest
                    // and won't directly fail a test unless they cause other observable issues.
                    // Log the error to understand if the listener itself is crashing.
                    await self.logOnMainActor(.error, "Transaction.updates listener terminated with error.", error: error, operation: "transactionListener")
                }
            }
        }

        Task { [weak self] in
            guard let self = self else { return }
            await self.fetchProducts()
            await self._updateEntitlementStatusInternal(operation: "init_updateEntitlement")
        }
    }

    deinit {
//        PurchaseService.staticLog(.debug, "PurchaseService deinit. Cancelling transaction listener.")
        transactionListener?.cancel()
    }

    // MARK: - Logging Helpers
    private func log(_ level: LogLevel, _ message: String, productID: String? = nil, error: Error? = nil, operation: String? = nil) {
        if !enableLogging && level == .debug { return }

        let fullMessage = "\(message)" + (error != nil ? " Error: \(error!.localizedDescription)" : "")
        // Ensure this print happens on the main thread if self is MainActor
        // For simplicity, direct print is often fine for internal logs, but for strictness:
        // if Thread.isMainThread { print(...) } else { DispatchQueue.main.async { print(...) } }
        print("[\(level)] PurchaseService: \(fullMessage)")

        var context: [String: String] = [:]
        if let productID = productID { context["productID"] = productID }
        if let error = error { context["error"] = String(describing: type(of: error)) + ": " + error.localizedDescription }
        if let operation = operation { context["operation"] = operation }

        // Delegate calls should be on the main thread if the delegate expects it
        // Since PurchaseService is @MainActor, this call is already on the main thread.
        delegate?.purchaseService(didLog: message, level: level, context: context.isEmpty ? nil : context)
    }

    @MainActor
    private func logOnMainActor(_ level: LogLevel, _ message: String, productID: String? = nil, error: Error? = nil, operation: String? = nil) {
        self.log(level, message, productID: productID, error: error, operation: operation)
    }

    private static func staticLog(_ level: LogLevel, _ message: String) {
        print("[\(level)] PurchaseService (static/deinit): \(message)")
    }

    private func setFailure(_ purchaseError: PurchaseError, productID: String? = nil, operation: String) {
        let failure = PurchaseFailure(error: purchaseError, productID: productID, operation: operation)
        self.lastFailure = failure
        log(.error, "Operation '\(operation)' failed.", productID: productID, error: purchaseError, operation: operation)
    }

    // MARK: - Public API
    public func fetchProducts() async {
        guard purchaseState != .fetchingProducts else {
            log(.warning, "Already fetching products.", operation: "fetchProducts")
            return
        }
        setPurchaseState(.fetchingProducts, operation: "fetchProducts")
        self.lastFailure = nil // Explicit fetchProducts clears previous errors for this op
        log(.info, "Fetching products for IDs: \(productIDs.joined(separator: ", ")).")

        do {
            self.availableProducts = try await productProvider.fetchProducts(for: productIDs)
            log(.info, "Successfully fetched \(availableProducts.count) products.")
            if availableProducts.isEmpty && !productIDs.isEmpty {
                log(.warning, "Fetched 0 products, but product IDs were provided. Check configuration or StoreKit availability.")
                setFailure(.productsNotFound, operation: "fetchProducts")
            }
        } catch let e as PurchaseError {
            self.availableProducts = []
            setFailure(e, operation: "fetchProducts")
        } catch {
            self.availableProducts = []
            setFailure(.underlyingError(error), operation: "fetchProducts")
        }
        setPurchaseState(.idle, operation: "fetchProducts")
    }

    public func purchase(productID: String) async {
        if case .purchasing(let currentProductID) = purchaseState {
            log(.warning, "Purchase already in progress for product \(currentProductID). Requested: \(productID).", productID: productID, operation: "purchase")
            setFailure(.purchasePending, productID: productID, operation: "purchase")
            return
        }

        guard let productToPurchase = availableProducts.first(where: { $0.id == productID }) else {
            log(.error, "Product ID \(productID) not found in availableProducts.", productID: productID, operation: "purchase")
            setFailure(.productNotAvailableForPurchase(productID: productID), productID: productID, operation: "purchase")
            return
        }

        guard let underlyingStoreKitProduct = productToPurchase.underlyingStoreKitProduct else {
            log(.error, "Product \(productID) is a mock or adapter without an underlying StoreKit.Product. Cannot purchase.", productID: productID, operation: "purchase")
            setFailure(.unknown, productID: productID, operation: "purchase")
            return
        }

        setPurchaseState(.purchasing(productID: productID), operation: "purchase")
        self.lastFailure = nil // Explicit purchase clears previous errors for this op
        log(.info, "Attempting to purchase productID: \(productID).", productID: productID)

        do {
            let transaction = try await purchaser.purchase(underlyingStoreKitProduct)
            log(.info, "Purchase successful for productID: \(productID), transactionID: \(transaction.id). Validating...", productID: productID)
            self.entitlementStatus = try await receiptValidator.validate(transaction: transaction)
            log(.info, "Entitlement updated to \(self.entitlementStatus) after purchase of \(productID). Finishing transaction.", productID: productID)
            await transaction.finish()
            log(.info, "Transaction finished for \(productID).", productID: productID)
        } catch let e as PurchaseError {
            log(.error, "Purchase failed for productID \(productID) with PurchaseError: \(e.localizedDescription)", productID: productID, error: e, operation: "purchase")
            setFailure(e, productID: productID, operation: "purchase")
        } catch let skError as SKError {
            log(.error, "Purchase failed for productID \(productID) with SKError: \(skError.localizedDescription) (Code: \(skError.errorCode))", productID: productID, error: skError, operation: "purchase")
            switch skError.code {
            case .paymentCancelled:
                setFailure(.purchaseCancelled, productID: productID, operation: "purchase")
            default:
                setFailure(.purchaseFailed(skError.code), productID: productID, operation: "purchase")
            }
        }
        catch {
            log(.error, "Purchase failed for productID \(productID) with an unexpected error: \(error)", productID: productID, error: error, operation: "purchase")
            setFailure(.underlyingError(error), productID: productID, operation: "purchase")
        }
        setPurchaseState(.idle, operation: "purchase", productID: productID)
    }

    public func getAllTransactions() async -> [Transaction] {
        log(.info, "Attempting to get all transactions.", operation: "getAllTransactions")
        self.lastFailure = nil // Explicit getAllTransactions clears previous errors for this op
        do {
            let transactions = try await purchaser.getAllTransactions()
            log(.info, "Successfully fetched \(transactions.count) transactions.", operation: "getAllTransactions")
            return transactions
        } catch let e as PurchaseError {
            setFailure(e, operation: "getAllTransactions")
        } catch {
            setFailure(.underlyingError(error), operation: "getAllTransactions")
        }
        return []
    }

    public func restorePurchases() async {
        guard purchaseState != .restoring else {
            log(.warning, "Restore purchases already in progress.", operation: "restorePurchases")
            return
        }
        setPurchaseState(.restoring, operation: "restorePurchases")
        self.lastFailure = nil // Explicit restore clears previous errors for this op
        log(.info, "Attempting to restore purchases.")

        if !self.isUnitTesting_prop {
            do {
                log(.debug, "Calling AppStore.sync().", operation: "restorePurchases")
                try await AppStore.sync()
                log(.info, "AppStore.sync() completed.", operation: "restorePurchases")
            } catch {
                log(.error, "AppStore.sync() failed.", error: error, operation: "restorePurchases")
                setFailure(.underlyingError(error), operation: "restorePurchases_sync")
                // Failure from sync() will be the current lastFailure.
                // _updateEntitlementStatusInternal will not clear it.
            }
        } else {
            log(.debug, "Skipping AppStore.sync() due to isUnitTesting=true.", operation: "restorePurchases")
        }

        await _updateEntitlementStatusInternal(operation: "restorePurchases_updateEntitlement")
        setPurchaseState(.idle, operation: "restorePurchases")

        if lastFailure == nil {
            log(.info, "Restore purchases process completed successfully. Final entitlement: \(entitlementStatus).", operation: "restorePurchases")
        } else {
            log(.warning, "Restore purchases process completed, but a failure occurred: \(lastFailure!.error.localizedDescription) during operation: \(lastFailure!.operation). Final entitlement: \(entitlementStatus).", operation: "restorePurchases")
        }
    }

    /// Manually triggers a check of the user's current entitlements.
    /// This is a top-level public action, so it will clear any previous `lastFailure`.
    public func updateEntitlementStatus() async {
        self.lastFailure = nil // Clear previous failure for an explicit, fresh check
        await _updateEntitlementStatusInternal(operation: "updateEntitlementStatus_explicit")
    }

    // Internal method that performs the entitlement check without clearing lastFailure initially.
    // It's called by public updateEntitlementStatus, init, and restorePurchases.
    private func _updateEntitlementStatusInternal(operation: String) async {
        // Check for re-entrancy only if this is part of an explicit user-facing check operation
        if operation == "updateEntitlementStatus_explicit" && purchaseState == .checkingEntitlement {
            log(.debug, "Already checking entitlement (explicitly).", operation: operation)
            return
        }

        let previousState = self.purchaseState
        // Set .checkingEntitlement state only for the explicit public call scenario
        if operation == "updateEntitlementStatus_explicit" {
            setPurchaseState(.checkingEntitlement, operation: operation)
        }

        log(.info, "Internal: Updating entitlement status (Triggering Operation: \(operation)).")

        do {
            let newStatus = try await receiptValidator.checkCurrentEntitlements()
            if self.entitlementStatus != newStatus {
                log(.info, "Entitlement status changed from \(self.entitlementStatus) to \(newStatus) (via op: \(operation)).")
                self.entitlementStatus = newStatus
            } else {
                log(.info, "Entitlement status remains \(self.entitlementStatus) (via op: \(operation)).")
            }
        } catch let e as PurchaseError {
            setFailure(e, operation: operation) // Sets lastFailure specific to this check
        } catch {
            setFailure(.underlyingError(error), operation: operation) // Sets lastFailure specific to this check
        }

        // Only reset state to idle if this was the explicit public call that set .checkingEntitlement
        if operation == "updateEntitlementStatus_explicit" {
            // If previous state was already .checkingEntitlement (due to re-entrancy check above), reset to idle.
            // Otherwise, restore the state that was active before this explicit check started.
            setPurchaseState(previousState == .checkingEntitlement ? .idle : previousState, operation: operation)
        }
    }

    // MARK: - Private Helpers
    private func setPurchaseState(_ newState: PurchaseState, operation: String, productID: String? = nil) {
        if self.purchaseState != newState {
            log(.debug, "PurchaseState changed: \(self.purchaseState) -> \(newState) (Op: \(operation))", productID: productID, operation: operation)
            self.purchaseState = newState
        }
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        let operation = "handleTransactionUpdate"
        log(.info, "Handling incoming transaction update.", operation: operation)
        // It's a background update, so we shouldn't clear lastFailure from other user-initiated operations.
        // If this specific handling fails, it will set its own lastFailure.

        do {
            let transaction: Transaction
            switch transactionResult {
            case .unverified(_, let error):
                log(.error, "Received unverified transaction.", error: error, operation: operation)
                // Set failure, but don't necessarily throw to stop all handling,
                // as other verified transactions might come through.
                // The critical part is not to grant entitlement for unverified.
                setFailure(.verificationFailed(error), operation: operation)
                return // Stop processing this unverified transaction
            case .verified(let trans):
                transaction = trans
                log(.info, "Received verified transactionID: \(transaction.id), productID: \(transaction.productID).", productID: transaction.productID, operation: operation)
            }

            let oldStatus = self.entitlementStatus
            let newValidatedStatus = try await receiptValidator.validate(transaction: transaction)

            // Only update if the new status from this single transaction validation is different
            // or if the current status is unknown/notSubscribed, giving priority to active one.
            // More sophisticated logic might be needed if multiple active transactions could yield different statuses.
            // For now, assume this validated transaction gives a more current view if it's active.
            if newValidatedStatus.isActive || entitlementStatus == .unknown || entitlementStatus == .notSubscribed {
                if self.entitlementStatus != newValidatedStatus {
                    log(.info, "Entitlement updated to \(newValidatedStatus) due to transaction \(transaction.id).", productID: transaction.productID, operation: operation)
                    self.entitlementStatus = newValidatedStatus
                } else {
                    log(.info, "Entitlement status \(self.entitlementStatus) reaffirmed by transaction \(transaction.id).", productID: transaction.productID, operation: operation)
                }
            } else {
                log(.info, "Current entitlement status \(self.entitlementStatus) is active and preferred over non-active status from transaction \(transaction.id) (\(newValidatedStatus)).", productID: transaction.productID, operation: operation)
            }


            log(.info, "Finishing transaction \(transaction.id).", productID: transaction.productID, operation: operation)
            await transaction.finish()
            log(.info, "Transaction \(transaction.id) finished.", productID: transaction.productID, operation: operation)

        } catch let e as PurchaseError {
            // This catch is for errors from receiptValidator.validate specifically.
            setFailure(e, operation: "\(operation)_validation")
        } catch {
            setFailure(.underlyingError(error), operation: "\(operation)_validation")
        }
    }
}
