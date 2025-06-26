// File: Sources/ASimplePurchaseKit/PurchaseService.swift

import Foundation
import StoreKit // For SKPaymentQueue (SK1) for canMakePayments
import Combine

public enum PurchaseState: Equatable, Sendable {
    case idle
    case fetchingProducts
    case purchasing(productID: String) // Stays simple for now; offerID is logged
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
            await self.fetchProducts()
            await self._updateEntitlementStatusInternal(operation: "init_updateEntitlement")
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Logging Helpers
    private func log(_ level: LogLevel, _ message: String, productID: String? = nil, error: Error? = nil, operation: String? = nil) {
        if !enableLogging && level == .debug { return }

        var context: [String: String] = [:]
        if let productID = productID { context["productID"] = productID }
        if let error = error {
            if let purchaseError = error as? PurchaseError {
                context["errorCode"] = String(describing: purchaseError)
                context["errorDescription"] = purchaseError.localizedDescription
            } else if let skError = error as? SKError {
                context["errorCode"] = "SKError.\(skError.code.rawValue)"
                context["errorDescription"] = skError.localizedDescription
            } else {
                context["error"] = String(describing: type(of: error))
                context["errorDescription"] = error.localizedDescription
            }
        }
        if let operation = operation { context["operation"] = operation }

        delegate?.purchaseService(didLog: message, level: level, context: context.isEmpty ? nil : context)
    }

    @MainActor
    private func logOnMainActor(_ level: LogLevel, _ message: String, productID: String? = nil, error: Error? = nil, operation: String? = nil) {
        self.log(level, message, productID: productID, error: error, operation: operation)
    }

    private func setFailure(_ purchaseError: PurchaseError, productID: String? = nil, operation: String) {
        let failure = PurchaseFailure(error: purchaseError, productID: productID, operation: operation)
        self.lastFailure = failure
        log(.error, "Operation '\(operation)' failed for product '\(productID ?? "N/A")'.", productID: productID, error: purchaseError, operation: operation)
    }

    // MARK: - Public API - Product Fetching
    public func fetchProducts() async {
        let currentOperation = "fetchProducts"
        guard purchaseState != .fetchingProducts else {
            log(.warning, "Already fetching products.", operation: currentOperation)
            return
        }
        setPurchaseState(.fetchingProducts, operation: currentOperation)
        self.lastFailure = nil
        log(.info, "Fetching products for IDs: \(productIDs.joined(separator: ", ")).", operation: currentOperation)

        do {
            self.availableProducts = try await productProvider.fetchProducts(for: productIDs)
            log(.info, "Successfully fetched \(availableProducts.count) products.", operation: currentOperation)
            if availableProducts.isEmpty && !productIDs.isEmpty {
                log(.warning, "Fetched 0 products, but product IDs were provided. Check configuration or StoreKit availability.", operation: currentOperation)
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

    // MARK: - Public API - Purchasing
    public func purchase(productID: String, offerID: String? = nil) async {
        let currentOperation = "purchase"
        let logProductID = productID
        let logOfferID = offerID

        if case .purchasing(let currentPurchasingProductID) = purchaseState {
            log(.warning, "Purchase already in progress for product \(currentPurchasingProductID). Requested: \(logProductID).", productID: logProductID, operation: currentOperation)
            setFailure(.purchasePending, productID: logProductID, operation: currentOperation)
            return
        }

        guard let productToPurchase = availableProducts.first(where: { $0.id == logProductID }) else {
            log(.error, "Product ID \(logProductID) not found in availableProducts.", productID: logProductID, operation: currentOperation)
            setFailure(.productNotAvailableForPurchase(productID: logProductID), productID: logProductID, operation: currentOperation)
            return
        }

        guard let underlyingStoreKitProduct = productToPurchase.underlyingStoreKitProduct else {
            log(.error, "Product \(logProductID) is a mock or adapter without an underlying StoreKit.Product. Cannot purchase.", productID: logProductID, operation: currentOperation)
            setFailure(.productNotAvailableForPurchase(productID: logProductID), productID: logProductID, operation: currentOperation)
            return
        }

        setPurchaseState(.purchasing(productID: logProductID), operation: currentOperation)
        self.lastFailure = nil
        let offerLog = logOfferID != nil ? " with offerID: \(logOfferID!)" : ""
        log(.info, "Attempting to purchase productID: \(logProductID)\(offerLog).", productID: logProductID, operation: currentOperation)

        do {
            let transaction = try await purchaser.purchase(underlyingStoreKitProduct, offerIdentifier: logOfferID)
            log(.info, "Purchase successful for productID: \(logProductID), transactionID: \(transaction.id). Validating...", productID: logProductID, operation: currentOperation)
            self.entitlementStatus = try await receiptValidator.validate(transaction: transaction)
            log(.info, "Entitlement updated to \(self.entitlementStatus) after purchase of \(logProductID). Finishing transaction.", productID: logProductID, operation: currentOperation)
            await transaction.finish()
            log(.info, "Transaction finished for \(logProductID).", productID: logProductID, operation: currentOperation)
        } catch let e as PurchaseError {
            setFailure(e, productID: logProductID, operation: currentOperation)
        } catch let skError as SKError {
            log(.error, "Purchase failed for productID \(logProductID) with SKError.", productID: logProductID, error: skError, operation: currentOperation)
            switch skError.code {
            case .paymentCancelled:
                setFailure(.purchaseCancelled, productID: logProductID, operation: currentOperation)
            default:
                setFailure(.purchaseFailed(skError.code), productID: logProductID, operation: currentOperation)
            }
        }
        catch {
            log(.error, "Purchase failed for productID \(logProductID) with an unexpected error.", productID: logProductID, error: error, operation: currentOperation)
            setFailure(.underlyingError(error), productID: logProductID, operation: currentOperation)
        }
        setPurchaseState(.idle, operation: currentOperation, productID: logProductID)
    }

    public func eligiblePromotionalOffers(for product: ProductProtocol) -> [PromotionalOfferProtocol] {
        let currentOperation = "eligiblePromotionalOffers"
        guard product.type == .autoRenewable, let subInfo = product.subscription else {
            log(.debug, "Product \(product.id) is not an auto-renewable subscription or has no subscription info. No promotional offers.", productID: product.id, operation: currentOperation)
            return []
        }
        let offers = subInfo.promotionalOffers
        log(.info, "Found \(offers.count) promotional offers for productID \(product.id).", productID: product.id, operation: currentOperation)
        return offers
    }

    // MARK: - Public API - Transactions & Entitlement
    public func getAllTransactions() async -> [Transaction] {
        let currentOperation = "getAllTransactions"
        log(.info, "Attempting to get all transactions.", operation: currentOperation)
        self.lastFailure = nil
        do {
            let transactions = try await purchaser.getAllTransactions()
            log(.info, "Successfully fetched \(transactions.count) transactions.", operation: currentOperation)
            return transactions
        } catch let e as PurchaseError {
            setFailure(e, operation: currentOperation)
        } catch {
            setFailure(.underlyingError(error), operation: currentOperation)
        }
        return []
    }

    public func getSubscriptionDetails(for productID: String) async -> Product.SubscriptionInfo.Status? {
        let currentOperation = "getSubscriptionDetails"
        log(.info, "Attempting to get subscription details for productID: \(productID)", productID: productID, operation: currentOperation)
        self.lastFailure = nil

        do {
            let allTX = try await purchaser.getAllTransactions()
            let productTransactions = allTX
                .filter { $0.productID == productID && $0.productType == .autoRenewable && !$0.isUpgraded }
                .sorted { $0.purchaseDate > $1.purchaseDate }

            guard let latestTransactionForProductID = productTransactions.first else {
                log(.info, "No current, non-upgraded auto-renewable transactions found for productID: \(productID)", productID: productID, operation: currentOperation)
                return nil
            }

            // `latestTransactionForProductID.subscriptionStatus` returns `Product.SubscriptionInfo.Status?`
            guard let status = await latestTransactionForProductID.subscriptionStatus else {
                log(.warning, "Could not retrieve Product.SubscriptionInfo.Status from latest transaction (\(latestTransactionForProductID.id)) for productID: \(productID).", productID: productID, operation: currentOperation)
                return nil
            }

            // Log essential and reliably available information
            var logParts: [String] = []
            logParts.append("OverallState: \(status.state)") // This is Product.SubscriptionInfo.RenewalState

            // Expiration date of the current subscription period (from the transaction in the status)
            switch status.transaction {
            case .verified(let transactionPayload):
                if let expDate = transactionPayload.expirationDate {
                    logParts.append("CurrentPeriodExpires: \(expDate)")
                } else {
                    logParts.append("CurrentPeriodExpires: None")
                }
            case .unverified(_, let error):
                logParts.append("CurrentPeriodExpires: UnverifiedTxInStatus(\(error.localizedDescription))")
            }

            // Information from RenewalInfo (next renewal period)
            switch status.renewalInfo {
            case .verified(let renewalInfoPayload):
                logParts.append("WillAutoRenewNextPeriod: \(renewalInfoPayload.willAutoRenew)")
                logParts.append("NextRenewalAttemptDate: \(renewalInfoPayload.renewalDate)") // Using renewalDate
                // Add other known-to-exist and simple properties from renewalInfoPayload if desired for logging
                // For example: renewalInfoPayload.originalTransactionID, renewalInfoPayload.productID
                // Avoid properties that your Xcode 16.4 compiler flags as missing.
                if let futureOfferID = renewalInfoPayload.offerID {
                    logParts.append("NextRenewalOfferID: \(futureOfferID)")
                }
                if let autoRenewPref = renewalInfoPayload.autoRenewPreference { // This seemed to be okay
                    logParts.append("AutoRenewPreferenceProductID: \(autoRenewPref)")
                }
                
            case .unverified(_, let error):
                logParts.append("RenewalInfo: Unverified(\(error.localizedDescription))")
            }

            log(.info, "Subscription details for \(productID) (TxID: \(latestTransactionForProductID.id)): \(logParts.joined(separator: ", "))", productID: productID, operation: currentOperation)
            return status

        } catch let e as PurchaseError {
            setFailure(e, productID: productID, operation: currentOperation)
            return nil
        } catch {
            setFailure(.underlyingError(error), productID: productID, operation: currentOperation)
            return nil
        }
    }

    public func restorePurchases() async {
        let currentOperation = "restorePurchases"
        guard purchaseState != .restoring else {
            log(.warning, "Restore purchases already in progress.", operation: currentOperation)
            return
        }
        setPurchaseState(.restoring, operation: currentOperation)
        self.lastFailure = nil
        log(.info, "Attempting to restore purchases.", operation: currentOperation)

        if !self.isUnitTesting_prop {
            do {
                log(.debug, "Calling AppStore.sync().", operation: currentOperation)
                try await AppStore.sync()
                log(.info, "AppStore.sync() completed.", operation: currentOperation)
            } catch {
                log(.error, "AppStore.sync() failed during restore.", error: error, operation: "\(currentOperation)_sync")
                setFailure(.underlyingError(error), operation: "\(currentOperation)_sync")
            }
        } else {
            log(.debug, "Skipping AppStore.sync() due to isUnitTesting=true.", operation: currentOperation)
        }

        await _updateEntitlementStatusInternal(operation: "\(currentOperation)_updateEntitlement")
        setPurchaseState(.idle, operation: currentOperation)

        if lastFailure == nil {
            log(.info, "Restore purchases process completed. Final entitlement: \(entitlementStatus).", operation: currentOperation)
        } else {
            log(.warning, "Restore purchases process completed with a failure: \(lastFailure!.error.localizedDescription) during operation: \(lastFailure!.operation). Final entitlement: \(entitlementStatus).", operation: currentOperation)
        }
    }

    public func updateEntitlementStatus() async {
        self.lastFailure = nil
        await _updateEntitlementStatusInternal(operation: "updateEntitlementStatus_explicit")
    }

    public func canMakePayments() -> Bool {
        let currentOperation = "canMakePayments"
        let canPay = SKPaymentQueue.canMakePayments()
        log(.info, "canMakePayments check result: \(canPay)", operation: currentOperation)
        return canPay
    }

    private func _updateEntitlementStatusInternal(operation contextOperation: String) async {
        if contextOperation == "updateEntitlementStatus_explicit" && purchaseState == .checkingEntitlement {
            log(.debug, "Already checking entitlement (explicitly).", operation: contextOperation)
            return
        }

        let previousState = self.purchaseState
        if contextOperation == "updateEntitlementStatus_explicit" {
            setPurchaseState(.checkingEntitlement, operation: contextOperation)
        }

        log(.info, "Internal: Updating entitlement status (Triggering Operation: \(contextOperation)).", operation: contextOperation)

        do {
            let newStatus = try await receiptValidator.checkCurrentEntitlements()
            if self.entitlementStatus != newStatus {
                log(.info, "Entitlement status changed from \(self.entitlementStatus) to \(newStatus) (via op: \(contextOperation)).", operation: contextOperation)
                self.entitlementStatus = newStatus
            } else {
                log(.info, "Entitlement status remains \(self.entitlementStatus) (via op: \(contextOperation)).", operation: contextOperation)
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
            log(.debug, "PurchaseState changed: \(self.purchaseState) -> \(newState) (Op: \(operation))", productID: productID, operation: operation)
            self.purchaseState = newState
        }
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        let currentOperation = "handleTransactionUpdate"
        log(.info, "Handling incoming transaction update.", operation: currentOperation)

        do {
            let transaction: Transaction
            switch transactionResult {
            case .unverified(_, let error):
                log(.error, "Received unverified transaction.", error: error, operation: currentOperation)
                setFailure(.verificationFailed(error), operation: currentOperation)
                return
            case .verified(let trans):
                transaction = trans
                log(.info, "Received verified transactionID: \(transaction.id), productID: \(transaction.productID).", productID: transaction.productID, operation: currentOperation)
            }

            let newValidatedStatus = try await receiptValidator.validate(transaction: transaction)

            var shouldUpdate = false
            if !entitlementStatus.isActive {
                shouldUpdate = true
            } else if newValidatedStatus.isActive {
                shouldUpdate = true
            }

            if shouldUpdate && self.entitlementStatus != newValidatedStatus {
                log(.info, "Entitlement updated from \(self.entitlementStatus) to \(newValidatedStatus) due to transaction \(transaction.id).", productID: transaction.productID, operation: currentOperation)
                self.entitlementStatus = newValidatedStatus
            } else if shouldUpdate && self.entitlementStatus == newValidatedStatus {
                log(.info, "Entitlement status \(self.entitlementStatus) reaffirmed by transaction \(transaction.id).", productID: transaction.productID, operation: currentOperation)
            } else {
                log(.info, "Current entitlement status \(self.entitlementStatus) is preferred or same; not changing due to transaction \(transaction.id) (new validated status: \(newValidatedStatus)).", productID: transaction.productID, operation: currentOperation)
            }

            log(.info, "Finishing transaction \(transaction.id).", productID: transaction.productID, operation: currentOperation)
            await transaction.finish()
            log(.info, "Transaction \(transaction.id) finished.", productID: transaction.productID, operation: currentOperation)

        } catch let e as PurchaseError {
            setFailure(e, operation: "\(currentOperation)_validation")
        } catch {
            setFailure(.underlyingError(error), operation: "\(currentOperation)_validation")
        }
    }
}
