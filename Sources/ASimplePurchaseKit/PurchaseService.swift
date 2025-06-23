// File: Sources/ASimplePurchaseKit/PurchaseService.swift

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

        // For this initial log, operation context isn't critical or well-defined yet.
        log(.info, "Initializing PurchaseService. Unit testing: \(isUnitTesting), Product IDs: \(productIDs.joined(separator: ", ")).")

        if !isUnitTesting_prop {
            self.transactionListener = Task.detached { [weak self] in
                guard let self = self else { return }
                // Pass "transactionListener" as operation for these logs
                await self.logOnMainActor(.debug, "Transaction.updates listener starting.", operation: "transactionListener")
                do {
                    for await result in Transaction.updates {
                        await self.handle(transactionResult: result)
                    }
                    await self.logOnMainActor(.debug, "Transaction.updates listener ended normally.", operation: "transactionListener")
                } catch {
                    await self.logOnMainActor(.error, "Transaction.updates listener terminated with error.", error: error, operation: "transactionListener")
                }
            }
        }

        Task { [weak self] in
            guard let self = self else { return }
            await self.fetchProducts() // fetchProducts will log with its own operation
            await self._updateEntitlementStatusInternal(operation: "init_updateEntitlement") // This also logs with its operation
        }
    }

    deinit {
        // For deinit, a static log without instance context is fine.
//        PurchaseService.staticLog(.debug, "PurchaseService deinit. Cancelling transaction listener.")
        transactionListener?.cancel()
    }

    // MARK: - Logging Helpers
    private func log(_ level: LogLevel, _ message: String, productID: String? = nil, error: Error? = nil, operation: String? = nil) {
        if !enableLogging && level == .debug { return }

        let fullMessage = "\(message)" + (error != nil ? " Error: \(error!.localizedDescription)" : "")
        print("[\(level)] PurchaseService: \(fullMessage)")

        var context: [String: String] = [:]
        if let productID = productID { context["productID"] = productID }
        if let error = error { context["error"] = String(describing: type(of: error)) + ": " + error.localizedDescription }
        if let operation = operation { context["operation"] = operation }
        
        print("[PurchaseService.log INTERNAL DEBUG] Message: '\(message)', Final Context before delegate call: \(context), IsEmpty: \(context.isEmpty)")
                
        delegate?.purchaseService(didLog: message, level: level, context: context.isEmpty ? nil : context)
    }
    
    @MainActor
    private func logOnMainActor(_ level: LogLevel, _ message: String, productID: String? = nil, error: Error? = nil, operation: String? = nil) {
        // This just ensures the call to self.log happens on the main actor.
        self.log(level, message, productID: productID, error: error, operation: operation)
    }

    private static func staticLog(_ level: LogLevel, _ message: String) {
        print("[\(level)] PurchaseService (static/deinit): \(message)")
    }

    private func setFailure(_ purchaseError: PurchaseError, productID: String? = nil, operation: String) {
        let failure = PurchaseFailure(error: purchaseError, productID: productID, operation: operation)
        self.lastFailure = failure
        // Pass all relevant info to log, including the operation that set the failure
        log(.error, "Operation '\(operation)' failed.", productID: productID, error: purchaseError, operation: operation)
    }

    // MARK: - Public API
    public func fetchProducts() async {
        let currentOperation = "fetchProducts" // Define operation for this scope
        guard purchaseState != .fetchingProducts else {
            log(.warning, "Already fetching products.", operation: currentOperation)
            return
        }
        setPurchaseState(.fetchingProducts, operation: currentOperation)
        self.lastFailure = nil
        log(.info, "Fetching products for IDs: \(productIDs.joined(separator: ", ")).", operation: currentOperation) // FIXED: Add operation

        do {
            self.availableProducts = try await productProvider.fetchProducts(for: productIDs)
            log(.info, "Successfully fetched \(availableProducts.count) products.", operation: currentOperation) // FIXED: Add operation
            if availableProducts.isEmpty && !productIDs.isEmpty {
                 log(.warning, "Fetched 0 products, but product IDs were provided. Check configuration or StoreKit availability.", operation: currentOperation) // FIXED: Add operation
                 setFailure(.productsNotFound, operation: currentOperation)
            }
        } catch let e as PurchaseError {
            self.availableProducts = []
            setFailure(e, operation: currentOperation)
        } catch {
            self.availableProducts = []
            setFailure(.underlyingError(error), operation: currentOperation)
        }
        setPurchaseState(.idle, operation: currentOperation)
    }

    public func purchase(productID: String) async {
        let currentOperation = "purchase" // Define operation
        if case .purchasing(let currentProductID) = purchaseState {
            log(.warning, "Purchase already in progress for product \(currentProductID). Requested: \(productID).", productID: productID, operation: currentOperation) // FIXED: Add operation
            setFailure(.purchasePending, productID: productID, operation: currentOperation)
            return
        }

        guard let productToPurchase = availableProducts.first(where: { $0.id == productID }) else {
            log(.error, "Product ID \(productID) not found in availableProducts.", productID: productID, operation: currentOperation) // FIXED: Add operation
            setFailure(.productNotAvailableForPurchase(productID: productID), productID: productID, operation: currentOperation)
            return
        }
        
        guard let underlyingStoreKitProduct = productToPurchase.underlyingStoreKitProduct else {
            log(.error, "Product \(productID) is a mock or adapter without an underlying StoreKit.Product. Cannot purchase.", productID: productID, operation: currentOperation) // FIXED: Add operation
            setFailure(.unknown, productID: productID, operation: currentOperation) // Keep .unknown or make more specific?
            return
        }

        setPurchaseState(.purchasing(productID: productID), operation: currentOperation)
        self.lastFailure = nil
        log(.info, "Attempting to purchase productID: \(productID).", productID: productID, operation: currentOperation) // FIXED: Add operation

        do {
            let transaction = try await purchaser.purchase(underlyingStoreKitProduct)
            log(.info, "Purchase successful for productID: \(productID), transactionID: \(transaction.id). Validating...", productID: productID, operation: currentOperation) // FIXED: Add operation
            self.entitlementStatus = try await receiptValidator.validate(transaction: transaction)
            log(.info, "Entitlement updated to \(self.entitlementStatus) after purchase of \(productID). Finishing transaction.", productID: productID, operation: currentOperation) // FIXED: Add operation
            await transaction.finish()
            log(.info, "Transaction finished for \(productID).", productID: productID, operation: currentOperation) // FIXED: Add operation
        } catch let e as PurchaseError {
            // setFailure handles its own logging with operation
            setFailure(e, productID: productID, operation: currentOperation)
        } catch let skError as SKError {
            // Log the SKError itself before calling setFailure
            log(.error, "Purchase failed for productID \(productID) with SKError.", productID: productID, error: skError, operation: currentOperation) // Keep this log
            switch skError.code {
            case .paymentCancelled:
                setFailure(.purchaseCancelled, productID: productID, operation: currentOperation)
            default:
                setFailure(.purchaseFailed(skError.code), productID: productID, operation: currentOperation)
            }
        }
        catch {
            // Log the unexpected error before calling setFailure
            log(.error, "Purchase failed for productID \(productID) with an unexpected error.", productID: productID, error: error, operation: currentOperation) // Keep this log
            setFailure(.underlyingError(error), productID: productID, operation: currentOperation)
        }
        setPurchaseState(.idle, operation: currentOperation, productID: productID)
    }
    
    public func getAllTransactions() async -> [Transaction] {
        let currentOperation = "getAllTransactions" // Define operation
        log(.info, "Attempting to get all transactions.", operation: currentOperation) // FIXED: Add operation
        self.lastFailure = nil
        do {
            let transactions = try await purchaser.getAllTransactions()
            log(.info, "Successfully fetched \(transactions.count) transactions.", operation: currentOperation) // FIXED: Add operation
            return transactions
        } catch let e as PurchaseError {
            setFailure(e, operation: currentOperation)
        } catch {
            setFailure(.underlyingError(error), operation: currentOperation)
        }
        return []
    }

    public func restorePurchases() async {
        let currentOperation = "restorePurchases" // Define operation
        guard purchaseState != .restoring else {
            log(.warning, "Restore purchases already in progress.", operation: currentOperation)
            return
        }
        setPurchaseState(.restoring, operation: currentOperation)
        self.lastFailure = nil
        log(.info, "Attempting to restore purchases.", operation: currentOperation) // FIXED: Add operation

        if !self.isUnitTesting_prop {
            do {
                log(.debug, "Calling AppStore.sync().", operation: currentOperation) // FIXED: Add operation (or a sub-operation like "restore_sync")
                try await AppStore.sync()
                log(.info, "AppStore.sync() completed.", operation: currentOperation) // FIXED: Add operation
            } catch {
                // Log the AppStore.sync specific error before setFailure
                log(.error, "AppStore.sync() failed during restore.", error: error, operation: "\(currentOperation)_sync")
                setFailure(.underlyingError(error), operation: "\(currentOperation)_sync")
            }
        } else {
            log(.debug, "Skipping AppStore.sync() due to isUnitTesting=true.", operation: currentOperation) // FIXED: Add operation
        }

        await _updateEntitlementStatusInternal(operation: "\(currentOperation)_updateEntitlement")
        setPurchaseState(.idle, operation: currentOperation)
        
        if lastFailure == nil {
             log(.info, "Restore purchases process completed successfully. Final entitlement: \(entitlementStatus).", operation: currentOperation) // FIXED: Add operation
        } else {
             log(.warning, "Restore purchases process completed, but a failure occurred: \(lastFailure!.error.localizedDescription) during operation: \(lastFailure!.operation). Final entitlement: \(entitlementStatus).", operation: currentOperation) // FIXED: Add operation
        }
    }

    public func updateEntitlementStatus() async {
        self.lastFailure = nil
        await _updateEntitlementStatusInternal(operation: "updateEntitlementStatus_explicit")
    }

    private func _updateEntitlementStatusInternal(operation contextOperation: String) async { // Renamed internal param for clarity
        if contextOperation == "updateEntitlementStatus_explicit" && purchaseState == .checkingEntitlement {
            log(.debug, "Already checking entitlement (explicitly).", operation: contextOperation)
            return
        }
        
        let previousState = self.purchaseState
        if contextOperation == "updateEntitlementStatus_explicit" {
            setPurchaseState(.checkingEntitlement, operation: contextOperation)
        }
        
        // Pass the received 'contextOperation' to the log function
        log(.info, "Internal: Updating entitlement status (Triggering Operation: \(contextOperation)).", operation: contextOperation)

        do {
            let newStatus = try await receiptValidator.checkCurrentEntitlements()
            if self.entitlementStatus != newStatus {
                log(.info, "Entitlement status changed from \(self.entitlementStatus) to \(newStatus) (via op: \(contextOperation)).", operation: contextOperation) // FIXED: Pass contextOperation
                self.entitlementStatus = newStatus
            } else {
                log(.info, "Entitlement status remains \(self.entitlementStatus) (via op: \(contextOperation)).", operation: contextOperation) // FIXED: Pass contextOperation
            }
        } catch let e as PurchaseError {
            setFailure(e, operation: contextOperation)
        } catch {
            setFailure(.underlyingError(error), operation: contextOperation)
        }
        
        if contextOperation == "updateEntitlementStatus_explicit" {
            setPurchaseState(previousState == .checkingEntitlement ? .idle : previousState, operation: contextOperation)
        }
    }

    // MARK: - Private Helpers
    private func setPurchaseState(_ newState: PurchaseState, operation: String, productID: String? = nil) {
        if self.purchaseState != newState {
            // This log call already includes the operation in its context via the `operation` parameter
            log(.debug, "PurchaseState changed: \(self.purchaseState) -> \(newState) (Op: \(operation))", productID: productID, operation: operation)
            self.purchaseState = newState
        }
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        let currentOperation = "handleTransactionUpdate" // Define operation for this scope
        log(.info, "Handling incoming transaction update.", operation: currentOperation) // FIXED: Add operation
        
        do {
            let transaction: Transaction
            switch transactionResult {
            case .unverified(_, let error):
                log(.error, "Received unverified transaction.", error: error, operation: currentOperation) // FIXED: Add operation
                setFailure(.verificationFailed(error), operation: currentOperation)
                return
            case .verified(let trans):
                transaction = trans
                log(.info, "Received verified transactionID: \(transaction.id), productID: \(transaction.productID).", productID: transaction.productID, operation: currentOperation) // FIXED: Add operation
            }
            
            // let oldStatus = self.entitlementStatus // Not strictly needed for logic here
            let newValidatedStatus = try await receiptValidator.validate(transaction: transaction)
            
            if newValidatedStatus.isActive || entitlementStatus == .unknown || entitlementStatus == .notSubscribed {
                if self.entitlementStatus != newValidatedStatus {
                     log(.info, "Entitlement updated to \(newValidatedStatus) due to transaction \(transaction.id).", productID: transaction.productID, operation: currentOperation) // FIXED: Add operation
                    self.entitlementStatus = newValidatedStatus
                } else {
                     log(.info, "Entitlement status \(self.entitlementStatus) reaffirmed by transaction \(transaction.id).", productID: transaction.productID, operation: currentOperation) // FIXED: Add operation
                }
            } else {
                 log(.info, "Current entitlement status \(self.entitlementStatus) is active and preferred over non-active status from transaction \(transaction.id) (\(newValidatedStatus)).", productID: transaction.productID, operation: currentOperation) // FIXED: Add operation
            }

            log(.info, "Finishing transaction \(transaction.id).", productID: transaction.productID, operation: currentOperation) // FIXED: Add operation
            await transaction.finish()
            log(.info, "Transaction \(transaction.id) finished.", productID: transaction.productID, operation: currentOperation) // FIXED: Add operation

        } catch let e as PurchaseError {
            setFailure(e, operation: "\(currentOperation)_validation")
        } catch {
            setFailure(.underlyingError(error), operation: "\(currentOperation)_validation")
        }
    }
}
