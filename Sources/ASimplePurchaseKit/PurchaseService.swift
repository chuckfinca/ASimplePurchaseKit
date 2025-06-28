//
//  PurchaseService.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn.
//

import Foundation
import StoreKit
import Combine

/// An enumeration representing the current operational state of the `PurchaseService`.
///
/// Use this to update your UI with activity indicators or to disable buttons during
/// long-running operations.
///
/// ## Usage
/// ```swift
/// switch purchaseService.purchaseState {
/// case .purchasing(let productID):
///     ProgressView("Purchasing \(productID)...")
/// case .restoring:
///     ProgressView("Restoring purchases...")
/// default:
///     Button("Buy Now") { /* ... */ }
/// }
/// ```
public enum PurchaseState: Equatable, Sendable {
    /// The service is not performing any operations.
    case idle
    /// The service is currently fetching product information from the App Store.
    case fetchingProducts
    /// The service is processing a purchase for a specific product.
    case purchasing(productID: String)
    /// The service is restoring previously purchased transactions.
    case restoring
    /// The service is checking the user's current entitlement status.
    case checkingEntitlement
}

/// An observable service that manages in-app purchases and user entitlements using StoreKit 2.
///
/// This is the main entry point for interacting with the ASimplePurchaseKit library.
/// It simplifies fetching products, making purchases, restoring transactions, and checking entitlement status.
///
/// ## Usage
/// ```swift
/// @main
/// struct YourApp: App {
///     @StateObject private var purchaseService: PurchaseService
///
///     init() {
///         let config = PurchaseConfig(productIDs: ["com.myapp.pro.monthly"])
///         _purchaseService = StateObject(wrappedValue: PurchaseService(config: config))
///     }
///
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///                 .environmentObject(purchaseService)
///         }
///     }
/// }
/// ```
@MainActor
public class PurchaseService: ObservableObject {

    // MARK: - Published State

    /// The list of products that are available for purchase, conforming to `ProductProtocol`.
    ///
    /// This array is populated by calling `fetchProducts()` and can be used to build your paywall UI.
    /// It will be empty until the initial fetch is complete.
    @Published public internal(set) var availableProducts: [any ProductProtocol] = []
    
    /// The user's current entitlement status.
    ///
    /// Observe this property in your UI to grant or deny access to premium features.
    /// Use the `.isActive` computed property for a simple boolean check.
    @Published public internal(set) var entitlementStatus: EntitlementStatus = .unknown
    
    /// The current state of the purchase service, indicating if it's idle or performing an operation.
    ///
    /// Use this to show activity indicators or disable UI elements during operations like
    /// `.fetchingProducts`, `.purchasing`, or `.restoring`.
    @Published public internal(set) var purchaseState: PurchaseState = .idle
    
    /// The last failure that occurred, containing the error and operational context.
    ///
    /// This is set to `nil` at the start of a new operation. Check this property to display
    /// relevant error messages to the user.
    @Published public private(set) var lastFailure: PurchaseFailure?
    
    /// A delegate to receive logging and other service events.
    ///
    /// Assign a delegate to this property to pipe logs and metrics into your own analytics system.
    public weak var delegate: PurchaseServiceDelegate?

    // MARK: - Dependencies

    private let productProvider: ProductProvider
    private let purchaser: Purchaser
    private let receiptValidator: ReceiptValidator
    private let transactionListenerProvider: TransactionListenerProvider
    private let appStoreSyncer: AppStoreSyncer

    // MARK: - Private State

    private let productIDs: [String]
    private var transactionListener: Task<Void, Error>? = nil
    private let enableLogging: Bool
    private var storeKitProducts: [String: Product] = [:]

    // MARK: - Initialization

    /// Creates an instance of the purchase service with the given configuration.
    ///
    /// This is the primary initializer you should use in your app.
    ///
    /// - Parameter config: The `PurchaseConfig` struct containing product IDs and logging options.
    public convenience init(config: PurchaseConfig) {
        let liveProvider = LivePurchaseProvider()
        let liveListenerProvider = LiveTransactionListenerProvider()
        let liveSyncer = LiveAppStoreSyncer()

        self.init(
            productIDs: config.productIDs,
            productProvider: liveProvider,
            purchaser: liveProvider,
            receiptValidator: liveProvider,
            transactionListenerProvider: liveListenerProvider,
            appStoreSyncer: liveSyncer,
            enableLogging: config.enableLogging
        )
    }

    internal init(
        productIDs: [String],
        productProvider: ProductProvider,
        purchaser: Purchaser,
        receiptValidator: ReceiptValidator,
        transactionListenerProvider: TransactionListenerProvider,
        appStoreSyncer: AppStoreSyncer,
        enableLogging: Bool = true
    ) {
        self.productIDs = productIDs
        self.productProvider = productProvider
        self.purchaser = purchaser
        self.receiptValidator = receiptValidator
        self.transactionListenerProvider = transactionListenerProvider
        self.appStoreSyncer = appStoreSyncer
        self.enableLogging = enableLogging

        log(.info, "Initializing PurchaseService. Product IDs: \(productIDs.joined(separator: ", ")).")

        self.transactionListener = Task.detached { [weak self] in
            guard let self = self else { return }
            await self.logOnMainActor(.debug, "Transaction.updates listener starting.", operation: "transactionListener")

            for await result in Transaction.updates {
                await self.handle(transactionResult: result)
            }
            await self.logOnMainActor(.debug, "Transaction.updates listener ended normally.", operation: "transactionListener")
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

    /// Fetches product information from the App Store.
    ///
    /// This method fetches product details for the `productIDs` provided during initialization.
    /// It updates the `availableProducts` property upon completion.
    /// The `purchaseState` will be set to `.fetchingProducts` during the operation.
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
            let fetchedProducts: [any ProductProtocol] = try await productProvider.fetchProducts(for: productIDs)

            self.availableProducts = fetchedProducts

            self.storeKitProducts.removeAll()
            for product in fetchedProducts {
                if let adapter = product as? StoreKitProductAdapter {
                    self.storeKitProducts[adapter.id] = adapter.underlyingStoreKitProduct
                }
            }

            log(.info, "Successfully fetched \(availableProducts.count) products.", operation: currentOperation)

            if availableProducts.isEmpty && !productIDs.isEmpty {
                log(.warning, "Fetched 0 products, but product IDs were provided. Check configuration or StoreKit availability.", operation: currentOperation)
                setFailure(.productsNotFound, operation: currentOperation)
            }

        } catch let e as PurchaseError {
            self.availableProducts = []
            self.storeKitProducts.removeAll()
            setFailure(e, operation: currentOperation)
        } catch {
            self.availableProducts = []
            self.storeKitProducts.removeAll()
            setFailure(.underlyingError(error), operation: currentOperation)
        }
        setPurchaseState(.idle, operation: currentOperation)
    }

    // MARK: - Public API - Purchasing

    /// Initiates the purchase flow for a given product identifier.
    ///
    /// The product must have been previously fetched and be present in `availableProducts`.
    /// The service's `purchaseState` will be updated to `.purchasing(productID)` during the flow.
    /// Upon completion, `entitlementStatus` will be updated and `lastFailure` will be set if an error occurred.
    ///
    /// - Parameters:
    ///   - productID: The string identifier of the product to purchase.
    ///   - offerID: An optional identifier for a specific promotional offer. Required for purchasing promotional offers.
    public func purchase(productID: String, offerID: String? = nil) async {
        let currentOperation = "purchase"
        let logProductID = productID
        let logOfferID = offerID

        if case .purchasing(let currentPurchasingProductID) = purchaseState {
            log(.warning, "Purchase already in progress for product \(currentPurchasingProductID). Requested: \(logProductID).", productID: logProductID, operation: currentOperation)
            setFailure(.purchasePending, productID: logProductID, operation: currentOperation)
            return
        }

        guard availableProducts.first(where: { $0.id == logProductID }) != nil else {
            log(.error, "Product ID \(logProductID) not found in availableProducts.", productID: logProductID, operation: currentOperation)
            setFailure(.productNotAvailableForPurchase(productID: logProductID), productID: logProductID, operation: currentOperation)
            return
        }

        guard let underlyingStoreKitProduct = storeKitProducts[logProductID] else {
            log(.error, "Product \(logProductID) does not have a corresponding StoreKit.Product. It may be a mock or purchase is not possible.", productID: logProductID, operation: currentOperation)
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

    /// Returns the promotional offers available for a given subscription product.
    ///
    /// - Parameter product: The subscription product for which to retrieve offers.
    /// - Returns: An array of `PromotionalOfferProtocol` objects. Returns an empty array if the product is not a subscription or has no offers.
    public func eligiblePromotionalOffers(for product: any ProductProtocol) -> [PromotionalOfferProtocol] {
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

    /// Retrieves the user's complete, verified transaction history.
    ///
    /// This method fetches all of the user's past transactions from the App Store.
    /// It can be used for building a receipt history view or for auditing purposes.
    ///
    /// - Returns: An array of verified `Transaction` objects. Returns an empty array if an error occurs.
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

    /// Retrieves detailed status information for a specific auto-renewable subscription.
    ///
    /// This method searches through all user transactions to find the latest one
    /// for the given product ID and returns its `Product.SubscriptionInfo.Status`.
    /// This is useful for checking expiration dates, renewal status, and more.
    ///
    /// - Parameter productID: The product identifier of the auto-renewable subscription.
    /// - Returns: A `Product.SubscriptionInfo.Status` object if a valid transaction is found, otherwise `nil`.
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

            guard let status = await latestTransactionForProductID.subscriptionStatus else {
                log(.warning, "Could not retrieve Product.SubscriptionInfo.Status from latest transaction (\(latestTransactionForProductID.id)) for productID: \(productID).", productID: productID, operation: currentOperation)
                return nil
            }

            var logParts: [String] = []
            logParts.append("OverallState: \(status.state)")
            switch status.transaction {
            case .verified(let transactionPayload):
                if let expDate = transactionPayload.expirationDate { logParts.append("CurrentPeriodExpires: \(expDate)") }
            case .unverified(_, let error):
                logParts.append("CurrentPeriodExpires: UnverifiedTxInStatus(\(error.localizedDescription))")
            }

            switch status.renewalInfo {
            case .verified(let renewalInfoPayload):
                logParts.append("WillAutoRenewNextPeriod: \(renewalInfoPayload.willAutoRenew)")
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

    /// Restores previously completed purchases.
    ///
    /// This method syncs with the App Store to restore non-consumable products and
    /// active subscriptions. The `entitlementStatus` will be updated automatically.
    /// The `purchaseState` will be set to `.restoring` during the operation.
    public func restorePurchases() async {
        let currentOperation = "restorePurchases"
        guard purchaseState != .restoring else {
            log(.warning, "Restore purchases already in progress.", operation: currentOperation)
            return
        }
        setPurchaseState(.restoring, operation: currentOperation)
        self.lastFailure = nil
        log(.info, "Attempting to restore purchases.", operation: currentOperation)

        do {
            log(.debug, "Calling AppStoreSyncer.sync().", operation: currentOperation)
            try await appStoreSyncer.sync()
            log(.info, "AppStoreSyncer.sync() completed.", operation: currentOperation)
        } catch {
            log(.error, "AppStoreSyncer.sync() failed during restore.", error: error, operation: "\(currentOperation)_sync")
            setFailure(.underlyingError(error), operation: "\(currentOperation)_sync")
        }

        await _updateEntitlementStatusInternal(operation: "\(currentOperation)_updateEntitlement")
        setPurchaseState(.idle, operation: currentOperation)

        if lastFailure == nil {
            log(.info, "Restore purchases process completed. Final entitlement: \(entitlementStatus).", operation: currentOperation)
        } else {
            log(.warning, "Restore purchases process completed with a failure: \(lastFailure!.error.localizedDescription) during operation: \(lastFailure!.operation). Final entitlement: \(entitlementStatus).", operation: currentOperation)
        }
    }

    /// Manually triggers an update of the user's entitlement status.
    ///
    /// This method forces a re-check of the user's current entitlements with the App Store.
    /// It's useful for scenarios where you need to be certain you have the latest status.
    public func updateEntitlementStatus() async {
        self.lastFailure = nil
        await _updateEntitlementStatusInternal(operation: "updateEntitlementStatus_explicit")
    }

    /// Checks if the user is allowed to make payments.
    ///
    /// This method returns `false` if the user is restricted from authorizing payments
    /// (e.g., due to parental controls).
    /// - Returns: `true` if the user can make payments, `false` otherwise.
    public func canMakePayments() -> Bool {
        let currentOperation = "canMakePayments"
        let canPay = SKPaymentQueue.canMakePayments()
        log(.info, "canMakePayments check result: \(canPay)", operation: currentOperation)
        return canPay
    }

    // MARK: - Private Helpers

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
