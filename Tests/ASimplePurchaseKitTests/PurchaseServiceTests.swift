//
//  PurchaseServiceTests.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/10/25.
//

import XCTest
import Combine
import StoreKit // Keep for types like Transaction, Product (even if not instantiating Product here)
@testable import ASimplePurchaseKit

@MainActor
final class PurchaseServiceTests: XCTestCase {

    var sut: PurchaseService!
    var mockProvider: MockPurchaseProvider!
    var cancellables: Set<AnyCancellable>!

    let testProductIDs = ["com.example.pro.monthly", "com.example.pro.yearly"]

    override func setUp() async throws {
        cancellables = []
        mockProvider = MockPurchaseProvider()
        // SUT initialization is deferred to helper or specific tests to allow
        // mockProvider setup *before* SUT's init calls its async tasks.
    }

    private func initializeSUT(productIDs: [String]? = nil) {
        let productIDs: [String] = productIDs ?? testProductIDs

        // Ensure mockProvider is configured for initial fetch/update before SUT init.
        if mockProvider.fetchProductsCallCount == 0 && mockProvider.checkCurrentEntitlementsCallCount == 0 {
            // Default setup for init if not specified by test
            mockProvider.productsResult = .success([])
            mockProvider.entitlementResult = .success(.unknown)
        }

        sut = PurchaseService(
            productIDs: productIDs,
            productProvider: mockProvider,
            purchaser: mockProvider,
            receiptValidator: mockProvider,
            isUnitTesting: true // IMPORTANT: Prevents real Transaction.updates listener
        )
    }

    override func tearDown() async throws {
        sut = nil
        mockProvider = nil
        cancellables?.forEach { $0.cancel() }
        cancellables = nil
    }

    // MARK: - Initialization Tests
    func test_initialization_fetchesProductsAndUpdatesEntitlements() async {
        // ARRANGE
        mockProvider.productsResult = .success([])
        mockProvider.entitlementResult = .success(.notSubscribed)

        // ACT
        initializeSUT()
        
        // Wait for async tasks in init to likely complete
        await Task.yield()

        // ASSERT
        XCTAssertEqual(mockProvider.fetchProductsCallCount, 1, "fetchProducts should be called once on init.")
        XCTAssertEqual(sut.availableProducts.count, 0, "availableProducts should be empty if mock returns empty.")
        XCTAssertEqual(mockProvider.checkCurrentEntitlementsCallCount, 1, "checkCurrentEntitlements should be called once on init.")
        XCTAssertEqual(sut.entitlementStatus, .notSubscribed, "entitlementStatus should reflect mock provider's initial check.")
    }
    
    // MARK: - Product Fetching Tests
    func test_fetchProducts_success_updatesAvailableProducts_empty() async {
        // ARRANGE
        initializeSUT() // Initial fetch already happened during SUT init
        mockProvider.reset() // Reset call counts and results for this specific test call
        
        let expectedProducts: [Product] = [] // Simulating fetching zero products
        mockProvider.productsResult = .success(expectedProducts)

        // ACT
        await sut.fetchProducts()

        // ASSERT
        XCTAssertEqual(mockProvider.fetchProductsCallCount, 1)
        XCTAssertEqual(sut.availableProducts.count, expectedProducts.count)
        XCTAssertNil(sut.lastError)
    }

    func test_fetchProducts_failure_setsLastErrorAndClearsProducts() async {
        // ARRANGE
        initializeSUT()
        mockProvider.reset()
        // Simulate products were already loaded, then fetch fails
        // This requires a way to set availableProducts, which is private(set).
        // So, we test fetch failure from an initially empty state.
        sut.availableProducts = [] // Ensure it's clear before this test. Actually, SUT init will call fetch.

        mockProvider.productsResult = .failure(PurchaseError.productsNotFound)

        // ACT
        await sut.fetchProducts()

        // ASSERT
        XCTAssertEqual(mockProvider.fetchProductsCallCount, 1)
        XCTAssertEqual(sut.lastError, .productsNotFound)
        XCTAssertTrue(sut.availableProducts.isEmpty, "Available products should be empty on fetch failure.")
    }

    // MARK: - Purchase Tests
    func test_purchase_productNotFoundInAvailableProducts_setsError() async {
        // ARRANGE
        mockProvider.productsResult = .success([]) // Ensure availableProducts is empty after init
        initializeSUT()
        await Task.yield() // Ensure init tasks complete

        // ACT
        await sut.purchase(productID: "nonexistent.id")

        // ASSERT
        XCTAssertEqual(sut.lastError, .productsNotFound)
        XCTAssertFalse(sut.isPurchasing)
        XCTAssertEqual(mockProvider.purchaseCallCount, 0)
    }
    
    func test_purchase_whenAlreadyPurchasing_setsPurchasePendingError() async {
        // ARRANGE
        initializeSUT() // availableProducts is empty
        // To test the `isPurchasing` guard, PurchaseService needs to be in that state.
        // This typically happens after `purchaser.purchase()` is called but before it completes.
        // Since `availableProducts` is empty, `sut.purchase()` will return early.
        // This test highlights the difficulty of testing states without controlling `availableProducts`
        // or being able to provide mock Product instances.
        // For now, we assume this scenario (product exists, isPurchasing is true) is hard to set up in pure unit test.
        XCTSkip("Skipping test: Complex to set up isPurchasing state without mock Product instances.")
    }

    func test_purchase_purchaserReturnsError_setsLastErrorAndResetsIsPurchasing() async {
        // ARRANGE
        // This test requires a Product to be "available" to attempt purchase.
        // As Product instantiation is difficult, this specific flow is better for integration tests.
        // The unit test can verify that IF purchase proceeds and the mock purchaser fails, error is set.
        // However, making the purchase proceed requires `availableProducts` to be non-empty.
        XCTSkip("Skipping test: Requires mocking/providing StoreKit.Product instances for availableProducts.")
    }
    
    func test_purchase_purchaserReturnsPurchaseCancelled_setsCorrectError() async {
        XCTSkip("Skipping test: Requires mocking/providing StoreKit.Product instances for availableProducts.")
    }

    func test_purchase_verificationFails_setsCorrectError() async {
        XCTSkip("Skipping test: Requires mocking/providing StoreKit.Product instances for availableProducts.")
    }

    func test_purchase_success_updatesEntitlementAndFinishesTransaction_mocked() async {
        // ARRANGE
        // This test simulates the PurchaseService logic *after* a product has been found
        // and passed to the `purchaser`. It tests the interaction with `receiptValidator`
        // and `transaction.finish()`. This also requires a `Transaction` instance.
        // `Transaction` is also a StoreKit type, hard to mock fully.
        // We can use a simplified mock or acknowledge this is better for integration.
        XCTSkip("Skipping test: Requires complex mocking of Product and Transaction for full flow.")
    }


    // MARK: - Entitlement Update Tests
    func test_updateEntitlementStatus_success_updatesStatus() async {
        // ARRANGE
        mockProvider.entitlementResult = .success(.unknown) // Initial SUT state
        initializeSUT()
        mockProvider.reset() // Reset for the explicit call

        let expectedStatus: EntitlementStatus = .subscribed(expires: Date().addingTimeInterval(3600), isInGracePeriod: false)
        mockProvider.entitlementResult = .success(expectedStatus)

        // ACT
        await sut.updateEntitlementStatus()

        // ASSERT
        XCTAssertEqual(mockProvider.checkCurrentEntitlementsCallCount, 1)
        XCTAssertEqual(sut.entitlementStatus, expectedStatus)
        XCTAssertNil(sut.lastError)
    }

    func test_updateEntitlementStatus_failure_setsLastError() async {
        // ARRANGE
        mockProvider.entitlementResult = .success(.unknown) // Initial SUT state
        initializeSUT()
        mockProvider.reset()

        mockProvider.entitlementResult = .failure(PurchaseError.missingEntitlement)

        // ACT
        await sut.updateEntitlementStatus()

        // ASSERT
        XCTAssertEqual(mockProvider.checkCurrentEntitlementsCallCount, 1)
        XCTAssertEqual(sut.lastError, .missingEntitlement)
        // Entitlement status should ideally remain unchanged or become .unknown on error
        // Current SUT does not change entitlementStatus if checkCurrentEntitlements throws. This is reasonable.
    }

    // MARK: - Restore Purchases Tests
    func test_restorePurchases_callsCheckCurrentEntitlementsAndUpdatesStatus() async {
        // ARRANGE
        mockProvider.entitlementResult = .success(.unknown) // Initial SUT state
        initializeSUT()
        mockProvider.reset()

        let expectedStatus: EntitlementStatus = .subscribed(expires: nil, isInGracePeriod: false) // e.g., lifetime
        mockProvider.entitlementResult = .success(expectedStatus)
        // Note: `AppStore.sync()` is not called because `isUnitTesting` is true in SUT's init.

        // ACT
        await sut.restorePurchases()

        // ASSERT
        // `restorePurchases` calls `updateEntitlementStatus`, which calls `checkCurrentEntitlements`.
        XCTAssertEqual(mockProvider.checkCurrentEntitlementsCallCount, 1)
        XCTAssertEqual(sut.entitlementStatus, expectedStatus)
        XCTAssertNil(sut.lastError)
    }
    
    func test_restorePurchases_whenSyncThrows_setsUnknownError() async {
        // ARRANGE
        // This test is for the scenario where AppStore.sync() itself throws.
        // However, in `isUnitTesting: true` mode, `AppStore.sync()` is NOT called.
        // So, this specific path of `restorePurchases` is not coverable by these unit tests.
        // It's an integration concern.
        XCTSkip("Skipping test: AppStore.sync() is not called when isUnitTesting is true.")
    }
}
