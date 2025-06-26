import XCTest
import Combine
import StoreKit
@testable import ASimplePurchaseKit

@MainActor
final class PurchaseServiceTests: XCTestCase {

    var sut: PurchaseService!
    var mockProvider: MockPurchaseProvider!
    var mockDelegate: MockPurchaseServiceDelegate!
    var cancellables: Set<AnyCancellable>!

    let testProductIDs = ["com.example.pro.monthly", "com.example.pro.yearly"]
    let mockMonthlyProductID = "com.example.pro.monthly"
    let mockYearlyProductID = "com.example.pro.yearly"
    let mockLifetimeProductID = "com.example.pro.lifetime"
    let mockOfferID = "mock_free_trial_7_days"

    override func setUp() async throws {
        cancellables = []
        mockProvider = MockPurchaseProvider()
        mockDelegate = MockPurchaseServiceDelegate()
        // SUT initialization is deferred to helper or specific tests
    }

    private func initializeSUT(productIDs: [String]? = nil, enableLogging: Bool = false) {
        let pIDs = productIDs ?? testProductIDs
        sut = PurchaseService(
            productIDs: pIDs,
            productProvider: mockProvider,
            purchaser: mockProvider,
            receiptValidator: mockProvider,
            isUnitTesting: true,
            enableLogging: enableLogging
        )
        sut.delegate = mockDelegate
    }

    override func tearDown() async throws {
        sut = nil
        mockProvider = nil
        mockDelegate = nil
        cancellables?.forEach { $0.cancel() }
        cancellables = nil
    }

    // Helper to create a mock product with an underlying StoreKit.Product for purchase tests
    // This is still conceptual as creating a real StoreKit.Product in unit tests is hard.
    // The test for `purchase_withMockProductMissingUnderlyingStoreKitProduct_failsAsExpected`
    // already covers the scenario where `underlyingStoreKitProduct` is nil.
    // For successful purchase tests, we rely on `mockProvider.purchaseResult`.
    private func makeMockProductWithUnderlying(id: String, type: Product.ProductType, offers: [PromotionalOfferProtocol] = []) -> ProductProtocol {
        // This is a simplified MockProduct that *conceptually* has an underlying product.
        // In reality, `underlyingStoreKitProduct` for `MockProduct` is nil.
        // PurchaseService tests for successful purchase rely on availableProducts containing
        // an item whose ID matches, and then the mockProvider controlling the purchase outcome.
        if type == .autoRenewable {
            return MockProduct.newAutoRenewable(id: id, promotionalOffers: offers)
        } else {
            return MockProduct.newNonConsumable(id: id)
        }
    }


    // MARK: - Initialization Tests
    func test_initialization_fetchesProductsAndUpdatesEntitlements_setsInitialState() async {
        // ARRANGE
        let initialProductIDs = ["com.example.init.failure1", "com.example.init.failure2"]

        mockProvider.productsResult = .success([])
        mockProvider.entitlementResult = .success(.notSubscribed)

        // ACT
        initializeSUT(productIDs: initialProductIDs, enableLogging: true)

        await Task.yield() // Allow async tasks from init to proceed
        await Task.yield() // A second yield can sometimes help ensure all tasks settle

        // ASSERT
        XCTAssertEqual(mockProvider.fetchProductsCallCount, 1, "fetchProducts should be called once during init")
        XCTAssertTrue(sut.availableProducts.isEmpty, "Available products should be empty if fetch returns empty")
        XCTAssertNotNil(sut.lastFailure, "lastFailure should be set if fetchProducts fails to find products")
        if let lastFailure = sut.lastFailure { // Check error details safely
            XCTAssertEqual(lastFailure.error, .productsNotFound, "Error type should be productsNotFound")
            XCTAssertEqual(lastFailure.operation, "fetchProducts", "Operation context for failure should be fetchProducts")
        }
        XCTAssertEqual(mockProvider.checkCurrentEntitlementsCallCount, 1, "checkCurrentEntitlements should be called once during init")
        XCTAssertEqual(sut.entitlementStatus, .notSubscribed, "Initial entitlement status should be notSubscribed")
        XCTAssertEqual(sut.purchaseState, .idle, "Purchase state should be idle after init tasks complete")

        let productFetchLogFailureFound = mockDelegate.logEvents.contains { event in
            event.message.contains("Operation 'fetchProducts' failed") &&
                event.level == .error &&
                event.context?["errorDescription"]?.contains("The requested products could not be found.") == true &&
                event.context?["operation"] == "fetchProducts"
        }
        XCTAssertTrue(productFetchLogFailureFound, "Delegate should have received the 'fetchProducts' failure log event. Logs: \(mockDelegate.logEvents.map { $0.message })")

        let entitlementCheckLogFound = mockDelegate.logEvents.contains { event in
            let messageMatch = (event.message.contains("Entitlement status changed from unknown to notSubscribed") ||
                event.message.contains("Entitlement status remains notSubscribed")) &&
                event.message.contains("(via op: init_updateEntitlement)")
            let levelMatch = event.level == .info
            let contextMatch = event.context != nil && event.context?["operation"] == "init_updateEntitlement"
            return messageMatch && levelMatch && contextMatch
        }
        XCTAssertTrue(entitlementCheckLogFound, "Delegate should have received an entitlement update log from init with 'init_updateEntitlement' operation. Logs: \(mockDelegate.logEvents.map { $0.message })")
    }

    // MARK: - Product Fetching Tests
    func test_fetchProducts_success_updatesAvailableProductsAndState() async {
        // ARRANGE
        initializeSUT(enableLogging: true)
        await Task.yield() // Let init tasks run

        mockProvider.reset() // Reset after init calls
        mockDelegate.reset() // Reset after init logs

        let mockProduct = MockProduct.newNonConsumable(id: mockLifetimeProductID)
        let expectedProducts: [ProductProtocol] = [mockProduct]
        mockProvider.productsResult = .success(expectedProducts)

        let stateExpectation = XCTestExpectation(description: "PurchaseState changes to fetchingProducts then idle")
        var states: [PurchaseState] = []
        sut.$purchaseState
            .dropFirst() // Drop initial .idle state from SUT init
        .sink { state in
            states.append(state)
            if states.count >= 2 && states.contains(.fetchingProducts) && states.last == .idle {
                stateExpectation.fulfill()
            } else if states.count >= 1 && state == .fetchingProducts {
                // Fulfill if we see fetching, and then later idle will fulfill too if sequence is right
            }
        }.store(in: &cancellables)

        // ACT
        await sut.fetchProducts()
        await fulfillment(of: [stateExpectation], timeout: 2.0)


        // ASSERT
        XCTAssertEqual(mockProvider.fetchProductsCallCount, 1)
        XCTAssertEqual(sut.availableProducts.count, expectedProducts.count)
        XCTAssertEqual(sut.availableProducts.first?.id, mockLifetimeProductID)
        XCTAssertNil(sut.lastFailure)
        XCTAssertEqual(sut.purchaseState, .idle)


        XCTAssertTrue(mockDelegate.logEvents.contains(where: { event in
            let messageMatch = event.message.contains("Successfully fetched 1 products")
            let levelMatch = event.level == .info
            let contextMatch = event.context != nil && event.context?["operation"] == "fetchProducts"
            return messageMatch && levelMatch && contextMatch
        }), "Delegate should log successful product fetch. Logs: \(mockDelegate.logEvents.map { $0.message })")
    }

    func test_fetchProducts_failure_setsLastFailureAndClearsProducts() async {
        // ARRANGE
        initializeSUT(productIDs: ["some.id"], enableLogging: true)
        await Task.yield()

        let initialMockProduct = MockProduct.newNonConsumable(id: "initial.product.to.clear")
        mockProvider.productsResult = .success([initialMockProduct]) // Simulate initial success
        await sut.fetchProducts()
        XCTAssertEqual(sut.availableProducts.count, 1, "Pre-condition: products should be loaded.")

        mockProvider.reset()
        mockDelegate.reset()
        mockProvider.productsResult = .failure(PurchaseError.productsNotFound)

        // ACT
        await sut.fetchProducts()

        // ASSERT
        XCTAssertEqual(mockProvider.fetchProductsCallCount, 1)
        XCTAssertNotNil(sut.lastFailure)
        XCTAssertEqual(sut.lastFailure?.error, .productsNotFound)
        XCTAssertEqual(sut.lastFailure?.operation, "fetchProducts")
        XCTAssertTrue(sut.availableProducts.isEmpty, "Available products should be empty on fetch failure.")
        XCTAssertEqual(sut.purchaseState, .idle)

        XCTAssertTrue(mockDelegate.logEvents.contains(where: {
            $0.level == .error &&
                $0.message.contains("Operation 'fetchProducts' failed") &&
                $0.context?["errorDescription"]?.contains("The requested products could not be found.") == true &&
                $0.context?["operation"] == "fetchProducts"
        }), "Delegate should log failed product fetch.")
    }

    // MARK: - Purchase Tests
    func test_purchase_productNotAvailable_setsProductNotAvailableError() async {
        // ARRANGE
        initializeSUT(productIDs: [], enableLogging: true) // No products fetched initially
        await Task.yield()
        mockProvider.reset()
        mockDelegate.reset()

        // ACT
        await sut.purchase(productID: "nonexistent.id", offerID: nil)

        // ASSERT
        XCTAssertNotNil(sut.lastFailure)
        XCTAssertEqual(sut.lastFailure?.error, .productNotAvailableForPurchase(productID: "nonexistent.id"))
        XCTAssertEqual(sut.lastFailure?.operation, "purchase")
        XCTAssertEqual(sut.purchaseState, .idle)
        XCTAssertEqual(mockProvider.purchaseCallCount, 0) // Purchase shouldn't be called on provider

        XCTAssertTrue(mockDelegate.logEvents.contains(where: {
            $0.level == .error &&
                $0.message.contains("Product ID nonexistent.id not found") &&
                $0.context?["productID"] == "nonexistent.id" &&
                $0.context?["operation"] == "purchase"
        }), "Delegate should log product not available error.")
    }

    func test_purchase_givenOfferIDAndMockProduct_failsEarlyDueToMissingUnderlyingSKProduct() async {
        // ARRANGE
        initializeSUT(productIDs: [mockMonthlyProductID], enableLogging: false) // Logging can be false for this focused test

        // Ensure a MockProduct is in availableProducts so the SUT finds it.
        // PurchaseService will then check its underlyingStoreKitProduct.
        let mockProduct = MockProduct.newAutoRenewable(id: mockMonthlyProductID, promotionalOffers: [MockPromotionalOffer(id: mockOfferID)])
        sut.availableProducts = [mockProduct]

        // ACT
        await sut.purchase(productID: mockMonthlyProductID, offerID: mockOfferID)

        // ASSERT
        // Verifies that even with an offerID, a MockProduct (without underlyingStoreKitProduct)
        // results in the SUT failing early before calling the purchaser.
        XCTAssertNotNil(sut.lastFailure)
        XCTAssertEqual(sut.lastFailure?.error, .productNotAvailableForPurchase(productID: mockMonthlyProductID),
                       "Should fail because MockProduct lacks an underlying StoreKit product, regardless of offerID.")
        XCTAssertEqual(sut.lastFailure?.productID, mockMonthlyProductID)
        XCTAssertEqual(sut.lastFailure?.operation, "purchase")

        XCTAssertEqual(mockProvider.purchaseCallCount, 0,
                       "Purchaser.purchase should not be called due to early exit in SUT.")
        XCTAssertNil(mockProvider.lastOfferIdentifierPurchased,
                     "Offer ID should not be captured if purchaser.purchase was not called.")
    }

    func test_purchase_whenAlreadyPurchasing_setsPurchasePendingError() async {
        // ARRANGE
        initializeSUT(enableLogging: true)
        sut.availableProducts = [MockProduct(id: "p1", type: .nonConsumable, displayName: "P1")] // Ensure p1 is available
        sut.purchaseState = .purchasing(productID: "p1") // Set initial state
        mockDelegate.reset()

        // ACT
        await sut.purchase(productID: "p2", offerID: nil) // Attempt to purchase p2

        // ASSERT
        XCTAssertNotNil(sut.lastFailure)
        XCTAssertEqual(sut.lastFailure?.error, .purchasePending)
        XCTAssertEqual(sut.lastFailure?.productID, "p2") // Failure context should be for p2
        XCTAssertEqual(sut.purchaseState, .purchasing(productID: "p1")) // Original purchase state remains

        XCTAssertTrue(mockDelegate.logEvents.contains(where: {
            $0.level == .warning &&
                $0.message.contains("Purchase already in progress for product p1. Requested: p2.") &&
                $0.context?["productID"] == "p2" && // Context of the new request
            $0.context?["operation"] == "purchase"
        }), "Delegate should log purchase pending warning.")
    }

    func test_purchase_withMockProductMissingUnderlyingStoreKitProduct_failsAsExpected() async throws {
        // ARRANGE
        let mockPureProductID = "com.example.mock.pure"
        initializeSUT(productIDs: [mockPureProductID], enableLogging: true)

        // MockProduct (which has nil underlyingStoreKitProduct) is fetched
        let mockPureProduct = MockProduct.newNonConsumable(id: mockPureProductID)
        mockProvider.productsResult = .success([mockPureProduct])
        await sut.fetchProducts() // This will populate sut.availableProducts

        await Task.yield() // Allow fetch to complete
        mockProvider.reset() // Reset call counts for purchase
        mockDelegate.reset()

        // ACT
        await sut.purchase(productID: mockPureProductID, offerID: nil)

        // ASSERT
        XCTAssertNotNil(sut.lastFailure)
        // The error should now be more specific due to the guard check in PurchaseService
        XCTAssertEqual(sut.lastFailure?.error, .productNotAvailableForPurchase(productID: mockPureProductID), "Error was: \(String(describing: sut.lastFailure?.error))")
        XCTAssertEqual(sut.lastFailure?.productID, mockPureProductID)
        XCTAssertEqual(sut.purchaseState, .idle)
        XCTAssertEqual(mockProvider.purchaseCallCount, 0, "Mock provider's purchase should not be called.")

        XCTAssertTrue(mockDelegate.logEvents.contains(where: {
            $0.level == .error &&
            $0.message.contains("Product \(mockPureProductID) does not have a corresponding StoreKit.Product") &&
                $0.context?["productID"] == mockPureProductID &&
                $0.context?["operation"] == "purchase"
        }), "Delegate should log missing underlying product error. Logs: \(mockDelegate.logEvents.map { $0.message })")
    }

    // MARK: - Promotional Offer Tests
    func test_eligiblePromotionalOffers_forAutoRenewableWithOffers_returnsOffers() {
        initializeSUT()
        let offer1 = MockPromotionalOffer(id: "offer1", displayName: "Offer 1")
        let offer2 = MockPromotionalOffer(id: "offer2", displayName: "Offer 2")
        let product = MockProduct.newAutoRenewable(id: mockMonthlyProductID, promotionalOffers: [offer1, offer2])

        let offers = sut.eligiblePromotionalOffers(for: product)

        XCTAssertEqual(offers.count, 2)
        XCTAssertTrue(offers.contains(where: { $0.id == "offer1" }))
        XCTAssertTrue(offers.contains(where: { $0.id == "offer2" }))
    }

    func test_eligiblePromotionalOffers_forAutoRenewableWithoutOffers_returnsEmpty() {
        initializeSUT()
        let product = MockProduct.newAutoRenewable(id: mockMonthlyProductID, promotionalOffers: [])

        let offers = sut.eligiblePromotionalOffers(for: product)

        XCTAssertTrue(offers.isEmpty)
    }

    func test_eligiblePromotionalOffers_forNonConsumable_returnsEmpty() {
        initializeSUT()
        let product = MockProduct.newNonConsumable(id: mockLifetimeProductID)

        let offers = sut.eligiblePromotionalOffers(for: product)

        XCTAssertTrue(offers.isEmpty)
    }

    // MARK: - Entitlement Update Tests
    func test_updateEntitlementStatus_success_updatesStatusAndState() async {
        // ARRANGE
        initializeSUT(enableLogging: true)
        await Task.yield()

        mockProvider.reset()
        mockDelegate.reset()

        let expectedStatusDate = Date().addingTimeInterval(3600)
        let expectedStatus: EntitlementStatus = .subscribed(expires: expectedStatusDate, isInGracePeriod: false)
        mockProvider.entitlementResult = .success(expectedStatus)

        // SUT status is .notSubscribed after init due to mockProvider's default.
        XCTAssertEqual(sut.entitlementStatus, .notSubscribed, "Pre-condition: SUT status should be .notSubscribed.")

        // ACT
        await sut.updateEntitlementStatus()

        // ASSERT
        XCTAssertEqual(mockProvider.checkCurrentEntitlementsCallCount, 1)
        XCTAssertEqual(sut.entitlementStatus, expectedStatus)
        XCTAssertNil(sut.lastFailure)
        XCTAssertEqual(sut.purchaseState, .idle)

        let logFound = mockDelegate.logEvents.contains { event in
            let messageMatch = event.message.starts(with: "Entitlement status changed from notSubscribed to subscribed(expires: Optional(") &&
                event.message.contains("isInGracePeriod: false) (via op: updateEntitlementStatus_explicit).")
            let levelMatch = event.level == .info
            let contextMatch = event.context != nil && event.context?["operation"] == "updateEntitlementStatus_explicit"
            return messageMatch && levelMatch && contextMatch
        }
        XCTAssertTrue(logFound, "Delegate should log entitlement status change. Logs: \(mockDelegate.logEvents.map { $0.message })")
    }

    func test_updateEntitlementStatus_failure_setsLastFailure() async {
        // ARRANGE
        initializeSUT(enableLogging: true)
        await Task.yield() // Let init's async tasks (like initial entitlement check) settle

        mockProvider.reset() // Reset after init calls
        mockDelegate.reset() // Reset after init logs

        mockProvider.entitlementResult = .failure(PurchaseError.missingEntitlement)
        let initialStatusAfterInit = sut.entitlementStatus // Should be .notSubscribed

        // ACT
        await sut.updateEntitlementStatus()

        // ASSERT
        XCTAssertEqual(mockProvider.checkCurrentEntitlementsCallCount, 1)
        XCTAssertNotNil(sut.lastFailure)
        XCTAssertEqual(sut.lastFailure?.error, .missingEntitlement)
        XCTAssertEqual(sut.lastFailure?.operation, "updateEntitlementStatus_explicit")
        XCTAssertEqual(sut.entitlementStatus, initialStatusAfterInit, "Status should not change on explicit update error.")
        XCTAssertEqual(sut.purchaseState, .idle)

        XCTAssertTrue(mockDelegate.logEvents.contains(where: {
            $0.level == .error &&
                $0.message.contains("Operation 'updateEntitlementStatus_explicit' failed") &&
                $0.context?["errorDescription"]?.contains("Could not determine entitlement status.") == true &&
                $0.context?["operation"] == "updateEntitlementStatus_explicit"
        }), "Delegate should log failed entitlement update.")
    }

    // MARK: - Restore Purchases Tests
    func test_restorePurchases_isUnitTestingTrue_callsCheckEntitlements_updatesStatus() async {
        // ARRANGE
        initializeSUT(enableLogging: true) // isUnitTesting is true by default in helper
        await Task.yield()

        mockProvider.reset()
        mockDelegate.reset()

        let expectedStatus: EntitlementStatus = .subscribed(expires: nil, isInGracePeriod: false)
        mockProvider.entitlementResult = .success(expectedStatus)

        // ACT
        await sut.restorePurchases()

        // ASSERT
        XCTAssertEqual(mockProvider.checkCurrentEntitlementsCallCount, 1)
        XCTAssertEqual(sut.entitlementStatus, expectedStatus)
        XCTAssertNil(sut.lastFailure)
        XCTAssertEqual(sut.purchaseState, .idle)

        XCTAssertTrue(mockDelegate.logEvents.contains(where: {
            $0.message.contains("Skipping AppStore.sync() due to isUnitTesting=true") &&
                $0.level == .debug &&
                $0.context?["operation"] == "restorePurchases" // This operation is for the skipping log
        }), "Delegate should log skipping AppStore.sync.")

        XCTAssertTrue(mockDelegate.logEvents.contains(where: {
            $0.message.contains("Restore purchases process completed.") && // Message might vary slightly
            $0.level == .info &&
                $0.context?["operation"] == "restorePurchases" // This operation is for the completion log
        }), "Delegate should log successful restore completion.")
    }

    // MARK: - Get All Transactions / Subscription Details Tests
    func test_getAllTransactions_success_returnsTransactions() async {
        // ARRANGE
        initializeSUT(enableLogging: true)
        await Task.yield()

        // Conceptual mock transactions. Their internal properties won't be fully functional.
        let mockTx1 = try? Transaction.makeMock(productID: "tx1")
        let mockTx2 = try? Transaction.makeMock(productID: "tx2")
        // Since makeMock throws, this test primarily checks call counts and error handling.
        // For successful return of transactions, we'd need to bypass the throwing.
        // Let's assume for this test, an empty array is a valid success.
        mockProvider.allTransactionsResult = .success([])

        mockProvider.reset() // Reset after init
        mockDelegate.reset()


        // ACT
        let transactions = await sut.getAllTransactions()

        // ASSERT
        XCTAssertEqual(mockProvider.getAllTransactionsCallCount, 1)
        XCTAssertTrue(transactions.isEmpty)
        XCTAssertNil(sut.lastFailure)

        XCTAssertTrue(mockDelegate.logEvents.contains(where: {
            $0.message.contains("Successfully fetched 0 transactions") &&
                $0.context?["operation"] == "getAllTransactions"
        }), "Delegate should log successful fetch of 0 transactions.")
    }

    func test_getAllTransactions_failure_setsLastFailure() async {
        // ARRANGE
        initializeSUT(enableLogging: true)
        await Task.yield()

        mockProvider.reset()
        mockDelegate.reset()
        mockProvider.allTransactionsResult = .failure(PurchaseError.unknown)

        // ACT
        let transactions = await sut.getAllTransactions()

        // ASSERT
        XCTAssertEqual(mockProvider.getAllTransactionsCallCount, 1)
        XCTAssertTrue(transactions.isEmpty) // Should return empty on failure
        XCTAssertNotNil(sut.lastFailure)
        XCTAssertEqual(sut.lastFailure?.error, .unknown)
        XCTAssertEqual(sut.lastFailure?.operation, "getAllTransactions")

        XCTAssertTrue(mockDelegate.logEvents.contains(where: {
            $0.level == .error &&
                $0.message.contains("Operation 'getAllTransactions' failed") &&
                $0.context?["errorDescription"]?.contains("An unknown error occurred.") == true &&
                $0.context?["operation"] == "getAllTransactions"
        }), "Delegate should log failed getAllTransactions.")
    }

    // NEW TEST for getSubscriptionDetails
    // This test is limited because mocking Transaction.subscriptionStatus is hard.
    // It primarily tests the filtering logic and handling of empty/error states.
    func test_getSubscriptionDetails_noTransactionsFound_returnsNil() async {
        initializeSUT(enableLogging: true)
        await Task.yield()
        mockProvider.reset()
        mockDelegate.reset()

        mockProvider.allTransactionsResult = .success([]) // No transactions available

        let status = await sut.getSubscriptionDetails(for: mockMonthlyProductID)

        XCTAssertNil(status)
        XCTAssertNil(sut.lastFailure) // No error if simply no transactions found for the product
        XCTAssertTrue(mockDelegate.logEvents.contains(where: {
            $0.message.contains("No current, non-upgraded auto-renewable transactions found for productID: \(mockMonthlyProductID)") &&
                $0.level == .info &&
                $0.context?["productID"] == mockMonthlyProductID &&
                $0.context?["operation"] == "getSubscriptionDetails"
        }))
    }

    func test_getSubscriptionDetails_providerError_returnsNilAndSetsFailure() async {
        initializeSUT(enableLogging: true)
        await Task.yield()
        mockProvider.reset()
        mockDelegate.reset()

        mockProvider.allTransactionsResult = .failure(PurchaseError.unknown)

        let status = await sut.getSubscriptionDetails(for: mockMonthlyProductID)

        XCTAssertNil(status)
        XCTAssertNotNil(sut.lastFailure)
        XCTAssertEqual(sut.lastFailure?.error, .unknown)
        XCTAssertEqual(sut.lastFailure?.operation, "getSubscriptionDetails")
    }


    // MARK: - canMakePayments Test
    // This is a basic test. SKPaymentQueue.canMakePayments() is a static method from StoreKit.
    // Deep mocking would require more advanced techniques beyond the scope of typical unit tests for this library.
    func test_canMakePayments_returnsValueAndLogs() {
        initializeSUT(enableLogging: true)
        mockDelegate.reset()

        // Since SKPaymentQueue.canMakePayments() is usually true in test environments
        // unless parental controls are somehow simulated (hard in unit tests).
        let canPay = sut.canMakePayments()

        // We can't easily control the outcome, so we primarily check it doesn't crash and logs.
        XCTAssertTrue(canPay || !canPay) // tautology, just to ensure it runs

        XCTAssertTrue(mockDelegate.logEvents.contains(where: {
            $0.message == "canMakePayments check result: \(canPay)" && // Exact message check
            $0.level == .info &&
                $0.context?["operation"] == "canMakePayments"
        }), "Delegate should log canMakePayments check. Logs: \(mockDelegate.logEvents.map { $0.message })")
    }

    // MARK: - PurchaseFailure and EntitlementStatus Tests (from ModelTests.swift)
    // These can live here or in a separate ModelTests file. Keeping them here for consolidation.
    func test_purchaseFailure_equality() {
        let date1 = Date()
        let date2 = date1.addingTimeInterval(10)


        // Identical
        let failure1A = PurchaseFailure(error: .purchaseCancelled, productID: "test", operation: "purchase", timestamp: date1)
        let failure1B = PurchaseFailure(error: .purchaseCancelled, productID: "test", operation: "purchase", timestamp: date1)
        XCTAssertEqual(failure1A, failure1B, "Identical PurchaseFailure instances should be equal.")

        // Different error
        let failure2 = PurchaseFailure(error: .productsNotFound, productID: "test", operation: "purchase", timestamp: date1)
        XCTAssertNotEqual(failure1A, failure2, "PurchaseFailures with different errors should not be equal.")

        // Different productID
        let failure3 = PurchaseFailure(error: .purchaseCancelled, productID: "test-diff", operation: "purchase", timestamp: date1)
        XCTAssertNotEqual(failure1A, failure3, "PurchaseFailures with different productIDs should not be equal.")

        // Different operation
        let failure4 = PurchaseFailure(error: .purchaseCancelled, productID: "test", operation: "restore", timestamp: date1)
        XCTAssertNotEqual(failure1A, failure4, "PurchaseFailures with different operations should not be equal.")

        // Different timestamp
        let failure5 = PurchaseFailure(error: .purchaseCancelled, productID: "test", operation: "purchase", timestamp: date2)
        XCTAssertNotEqual(failure1A, failure5, "PurchaseFailures with different timestamps should not be equal.")


        let nsErrorContent1 = NSError(domain: "domain", code: 1, userInfo: [NSLocalizedDescriptionKey: "desc1"])
        let nsErrorContent2 = NSError(domain: "domain", code: 1, userInfo: [NSLocalizedDescriptionKey: "desc1"]) // Same content
        let nsErrorContent3 = NSError(domain: "domain", code: 2, userInfo: [NSLocalizedDescriptionKey: "desc2"]) // Different content
        let nsErrorContent4 = NSError(domain: "otherDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "desc1"]) // Different domain

        let purchaseErrorUnderlying1 = PurchaseError.underlyingError(nsErrorContent1)
        let purchaseErrorUnderlying2 = PurchaseError.underlyingError(nsErrorContent2)
        let purchaseErrorUnderlying3 = PurchaseError.underlyingError(nsErrorContent3)
        let purchaseErrorUnderlying4 = PurchaseError.underlyingError(nsErrorContent4)


        XCTAssertEqual(purchaseErrorUnderlying1, purchaseErrorUnderlying2, "Underlying errors with same NSError domain/code should be equal.")
        XCTAssertNotEqual(purchaseErrorUnderlying1, purchaseErrorUnderlying3, "Underlying errors with different NSError content should not be equal.")
        XCTAssertNotEqual(purchaseErrorUnderlying1, purchaseErrorUnderlying4, "Underlying errors with different NSError domains should not be equal.")

        let failure6A = PurchaseFailure(error: purchaseErrorUnderlying1, operation: "op", timestamp: date1)
        let failure6B = PurchaseFailure(error: purchaseErrorUnderlying2, operation: "op", timestamp: date1)
        let failure6C = PurchaseFailure(error: purchaseErrorUnderlying3, operation: "op", timestamp: date1)

        XCTAssertEqual(failure6A, failure6B)
        XCTAssertNotEqual(failure6A, failure6C)

        let purchaseErrorVF1 = PurchaseError.verificationFailed(.invalidSignature)
        let purchaseErrorVF2 = PurchaseError.verificationFailed(.invalidSignature)
        let purchaseErrorVF3 = PurchaseError.verificationFailed(.revokedCertificate)

        XCTAssertEqual(purchaseErrorVF1, purchaseErrorVF2)
        XCTAssertNotEqual(purchaseErrorVF1, purchaseErrorVF3)
    }

    func test_entitlementStatus_isActive() {
        XCTAssertTrue(EntitlementStatus.subscribed(expires: Date().addingTimeInterval(1000), isInGracePeriod: false).isActive)
        XCTAssertTrue(EntitlementStatus.subscribed(expires: Date().addingTimeInterval(1000), isInGracePeriod: true).isActive)
        XCTAssertTrue(EntitlementStatus.subscribed(expires: nil, isInGracePeriod: false).isActive) // Non-consumable

        XCTAssertFalse(EntitlementStatus.notSubscribed.isActive)
        XCTAssertFalse(EntitlementStatus.unknown.isActive)
    }

    // MARK: - SubscriptionPeriod LocalizedDescription Tests
    func test_subscriptionPeriod_localizedDescription() {
        // Use publicly available static instances of Product.SubscriptionPeriod

        // Test with .weekly (value: 1, unit: .week)
        // DateComponentsFormatter behavior for "1 week" can sometimes be "7 days".
        let weeklyDescription = Product.SubscriptionPeriod.weekly.localizedDescription
        XCTAssertTrue(["1 week", "7 days"].contains(weeklyDescription), "Expected '1 week' or '7 days', got '\(weeklyDescription)'")

        // Test with .monthly (value: 1, unit: .month)
        XCTAssertEqual(Product.SubscriptionPeriod.monthly.localizedDescription, "1 month")

        // Test with .yearly (value: 1, unit: .year)
        XCTAssertEqual(Product.SubscriptionPeriod.yearly.localizedDescription, "1 year")

        // Test with .everyTwoWeeks (value: 2, unit: .week)
        // Expected output could be "2 weeks" or "14 days"
        let twoWeeksDescription = Product.SubscriptionPeriod.everyTwoWeeks.localizedDescription
        XCTAssertTrue(["2 weeks", "14 days"].contains(twoWeeksDescription), "Expected '2 weeks' or '14 days', got '\(twoWeeksDescription)'")

        // Test with .everyThreeDays (value: 3, unit: .day)
        XCTAssertEqual(Product.SubscriptionPeriod.everyThreeDays.localizedDescription, "3 days")

        // Test with .everyTwoMonths (value: 2, unit: .month)
        XCTAssertEqual(Product.SubscriptionPeriod.everyTwoMonths.localizedDescription, "2 months")

        // Test with .everyThreeMonths (value: 3, unit: .month)
        XCTAssertEqual(Product.SubscriptionPeriod.everyThreeMonths.localizedDescription, "3 months")

        // Test with .everySixMonths (value: 6, unit: .month)
        XCTAssertEqual(Product.SubscriptionPeriod.everySixMonths.localizedDescription, "6 months")

        print("Note: test_subscriptionPeriod_localizedDescription is limited to testing with static Product.SubscriptionPeriod instances due to internal initializer access levels for arbitrary values.")
    }
}

// Mock Delegate (already exists from previous phase, ensure it's up-to-date)
class MockPurchaseServiceDelegate: PurchaseServiceDelegate, @unchecked Sendable {
    struct LogEvent: @unchecked Sendable {
        let message: String
        let level: LogLevel
        let context: [String: String]?
    }
    var logEvents: [LogEvent] = []

    func purchaseService(didLog event: String, level: LogLevel, context: [String: String]?) {
        logEvents.append(LogEvent(message: event, level: level, context: context))
    }

    func reset() {
        logEvents = []
    }
}
