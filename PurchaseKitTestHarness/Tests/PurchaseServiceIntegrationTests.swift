//
//  PurchaseServiceIntegrationTests.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/13/25.
//

import XCTest
import Combine
import StoreKitTest
@testable import ASimplePurchaseKit

@MainActor
final class PurchaseServiceIntegrationTests: XCTestCase {

    var session: SKTestSession!
    var sut: PurchaseService!
    var config: PurchaseConfig!
    var cancellables: Set<AnyCancellable>!

    let monthlyProductID = "com.asimplepurchasekit.pro.monthly"
    let yearlyProductID = "com.asimplepurchasekit.pro.yearly"
    let lifetimeProductID = "com.asimplepurchasekit.pro.lifetime"
    lazy var allTestProductIDs = [monthlyProductID, yearlyProductID, lifetimeProductID]

    override func setUp() async throws {
        print("🧪 [SETUP] Starting PurchaseServiceIntegrationTests.setUp")
        let testBundle = Bundle(for: PurchaseServiceIntegrationTests.self)
        guard let url = testBundle.url(forResource: "Products", withExtension: "storekit") else {
            XCTFail("Could not find Products.storekit in bundle. testBundle path: \(testBundle.bundlePath)")
            return
        }
        print("🧪 [SETUP] StoreKit Configuration URL: \(url.path)")

        // 1. Initialize SKTestSession
        do {
            session = try SKTestSession(contentsOf: url)
            print("🧪 [SETUP] SKTestSession initialized.")
        } catch {
            XCTFail("❌ [SETUP] SKTestSession initialization failed: \(error)")
            throw error // rethrow to stop test further execution
        }

        // 2. Configure the session (Order Matters!)
        session.resetToDefaultState() // Reset first for a clean environment
        session.clearTransactions() // Clear any lingering transactions
        session.disableDialogs = true // Standard for automated tests
        session.storefront = "USA" // Set storefront, can help with localization/availability
        print("🧪 [SETUP] SKTestSession configured: reset, clearTransactions, disableDialogs, storefront='USA'.")

        // 3. CRITICAL PAUSE: Give StoreKit's internal mock server time to initialize with products
        let setupDelayMilliseconds: UInt64 = 1500 // Start with 1.5s, adjust if needed
        print("🧪 [SETUP] Pausing for \(setupDelayMilliseconds)ms for StoreKit to settle...")
        try await Task.sleep(for: .milliseconds(setupDelayMilliseconds))
        print("🧪 [SETUP] Pause complete.")

        // 4. (Optional but Recommended Debug Step) Verify product availability directly from StoreKit
        //    This helps isolate if the issue is SKTestSession itself or SUT's interaction.
        do {
            print("🧪 [SETUP] Performing direct check with Product.products(for: allTestProductIDs)...")
            let directProductCheck = try await Product.products(for: allTestProductIDs)
            print("🧪 [SETUP] Direct check: Product.products(for: [specific IDs]) found \(directProductCheck.count) products.")
            if directProductCheck.isEmpty {
                print("🧪 [SETUP] Direct check (specific IDs) was empty. Trying Product.products(for: [])...")
                let allDirect = try await Product.products(for: []) // Equivalent to Product.all
                print("🧪 [SETUP] Direct check: Product.products(for: []) found \(allDirect.count) products.")
                if allDirect.isEmpty {
                    print("⚠️ [SETUP] CRITICAL: Even Product.products(for: []) returned 0 products directly from StoreKit.")
                }
            }
        } catch {
            print("⚠️ [SETUP] Direct product check (Product.products(for:)) failed: \(error)")
        }

        // 5. Initialize SUT (PurchaseService)
        // IMPORTANT: Pass isUnitTesting: true to prevent auto-fetching in SUT's init
        // and to disable its global Transaction.updates listener.
        config = PurchaseConfig(productIDs: allTestProductIDs, isUnitTesting: true)
        sut = PurchaseService(config: config)
        cancellables = []
        print("🧪 [SETUP] PurchaseService (SUT) initialized with isUnitTesting: true.")

        // 6. Explicitly fetch products using the SUT *after* SKTestSession is presumably ready
        print("🧪 [SETUP] Attempting to fetch products via SUT.fetchProducts()...")
        await sut.fetchProducts() // This internally uses LivePurchaseProvider -> Product.products(for:)
        print("🧪 [SETUP] SUT.fetchProducts() completed. Available products in SUT: \(sut.availableProducts.count)")

        // 7. Wait for SUT's @Published availableProducts to update
        if sut.availableProducts.isEmpty {
            print("🧪 [SETUP] SUT products still empty, setting up expectation for $availableProducts publisher.")
            let expectation = XCTestExpectation(description: "Wait for SUT to load products via publisher")

            // Check current value again before sink, in case of rapid update
            if !sut.availableProducts.isEmpty {
                print("✅ [SETUP] SUT $availableProducts already non-empty before sink.")
                expectation.fulfill()
            } else {
                sut.$availableProducts
                // .dropFirst() // Only if you expect an initial empty emission *after* explicit fetch
                .sink { products in
                    if !products.isEmpty {
                        print("✅ [SETUP] SUT $availableProducts updated with \(products.count) products.")
                        expectation.fulfill()
                    } else {
                        print("⏳ [SETUP] SUT $availableProducts published empty array (again?).")
                    }
                }
                    .store(in: &cancellables)
            }
            await fulfillment(of: [expectation], timeout: 5.0)
        } else {
            print("✅ [SETUP] SUT already had products after explicit sut.fetchProducts() call.")
        }

        // Final assertion for setup's success
        if sut.availableProducts.isEmpty {
            print("❌ [SETUP] FINAL VERDICT: SUT availableProducts is STILL EMPTY.")
            XCTFail("PurchaseService SUT failed to load products after all setup steps and waits.")
        } else {
            print("✅ [SETUP] FINAL VERDICT: SUT has \(sut.availableProducts.count) products. Setup successful.")
        }
    }

    override func tearDown() async throws {
        print("🧪 [TEARDOWN] Clearing transactions and nilling objects.")
        session?.clearTransactions() // Good practice
        session = nil
        sut = nil
        config = nil
        cancellables?.forEach { $0.cancel() }
        cancellables = nil
    }

    // JEDI MANEUVER #9: Simplified test to isolate the issue
    func test_skTestSession_canFetchProducts() async throws {
        // This test ONLY checks if SKTestSession works, nothing else
        let products = try await Product.products(for: [monthlyProductID, lifetimeProductID])
        XCTAssertFalse(products.isEmpty, "SKTestSession should be able to fetch products")

        // Also try Product.all
        let allProducts = try await Product.all
        print("🔍 Product.all returned \(allProducts.count) products")
        XCTAssertFalse(allProducts.isEmpty, "Product.all should return products")
    }

    // MARK: - Focused StoreKit File Tests

    private func setupSUTWithStoreKitFile(
        storeKitFilename: String,
        productIDsForConfig: [String]
    ) async throws -> (sut: PurchaseService, session: SKTestSession, cancellables: Set<AnyCancellable>) {
        print("🧪 [FOCUSED SETUP] Starting for \(storeKitFilename)")
        let testBundle = Bundle(for: PurchaseServiceIntegrationTests.self)
        guard let url = testBundle.url(forResource: storeKitFilename, withExtension: "storekit") else {
            XCTFail("Could not find \(storeKitFilename).storekit in bundle. Path: \(testBundle.bundlePath)")
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "StoreKit file not found"])
        }
        print("🧪 [FOCUSED SETUP] StoreKit Configuration URL: \(url.path)")

        let newSession = try SKTestSession(contentsOf: url)
        print("🧪 [FOCUSED SETUP] SKTestSession initialized for \(storeKitFilename).")

        newSession.resetToDefaultState()
        newSession.clearTransactions()
        newSession.disableDialogs = true
        newSession.storefront = "USA"
        print("🧪 [FOCUSED SETUP] SKTestSession configured.")

        let setupDelayMilliseconds: UInt64 = 1500
        print("🧪 [FOCUSED SETUP] Pausing for \(setupDelayMilliseconds)ms for StoreKit to settle...")
        try await Task.sleep(for: .milliseconds(setupDelayMilliseconds))
        print("🧪 [FOCUSED SETUP] Pause complete.")

        // Direct check
        let directProductCheck = try await Product.products(for: productIDsForConfig)
        print("🧪 [FOCUSED SETUP] Direct check: Product.products(for: [specific IDs]) found \(directProductCheck.count) products for \(storeKitFilename).")
        if directProductCheck.isEmpty {
            print("⚠️ [FOCUSED SETUP] Direct check for \(storeKitFilename) found NO products. Trying Product.products(for: [])...")
            let allDirect = try await Product.products(for: [])
            print("🧪 [FOCUSED SETUP] Direct check (Product.all): Product.products(for: []) found \(allDirect.count) products for \(storeKitFilename).")
        }


        let newConfig = PurchaseConfig(productIDs: productIDsForConfig, isUnitTesting: true)
        let newSut = PurchaseService(config: newConfig)
        var newCancellables = Set<AnyCancellable>()
        print("🧪 [FOCUSED SETUP] PurchaseService (SUT) initialized for \(storeKitFilename).")

        print("🧪 [FOCUSED SETUP] Attempting to fetch products via SUT.fetchProducts()...")
        await newSut.fetchProducts()
        print("🧪 [FOCUSED SETUP] SUT.fetchProducts() completed. Available products in SUT: \(newSut.availableProducts.count)")

        if newSut.availableProducts.isEmpty && !productIDsForConfig.isEmpty {
            let expectation = XCTestExpectation(description: "Wait for SUT to load products for \(storeKitFilename)")
            if !newSut.availableProducts.isEmpty {
                expectation.fulfill()
            } else {
                newSut.$availableProducts
                    .sink { products in
                    if !products.isEmpty {
                        print("✅ [FOCUSED SETUP] SUT $availableProducts updated for \(storeKitFilename) with \(products.count) products.")
                        expectation.fulfill()
                    }
                }
                    .store(in: &newCancellables)
            }
            await fulfillment(of: [expectation], timeout: 5.0)
        }

        if newSut.availableProducts.count != productIDsForConfig.count && !productIDsForConfig.isEmpty {
            print("⚠️ [FOCUSED SETUP] SUT product count (\(newSut.availableProducts.count)) does not match expected (\(productIDsForConfig.count)) for \(storeKitFilename).")
        }

        return (newSut, newSession, newCancellables)
    }

    func test_fetchLifetimeProduct_withLifetimeOnlyStoreKitFile() async throws {
        let (sut, session, cancellables) = try await setupSUTWithStoreKitFile(
            storeKitFilename: "TestLifetimeOnly",
            productIDsForConfig: [lifetimeProductID]
        )
        // Hold onto session and cancellables to keep them alive
        _ = session
        var localCancellables = cancellables

        XCTAssertEqual(sut.availableProducts.count, 1, "Should load 1 lifetime product.")
        XCTAssertEqual(sut.availableProducts.first?.id, lifetimeProductID)
        XCTAssertNil(sut.lastError)

        // Clean up cancellables if needed, or let them deinit with the test method scope
        localCancellables.forEach { $0.cancel() }
    }

    func test_fetchSubscriptionProducts_withSubscriptionOnlyStoreKitFile() async throws {
        let productIDs = [monthlyProductID, yearlyProductID]
        let (sut, session, cancellables) = try await setupSUTWithStoreKitFile(
            storeKitFilename: "TestSubscriptionOnly",
            productIDsForConfig: productIDs
        )
        _ = session
        var localCancellables = cancellables

        XCTAssertEqual(sut.availableProducts.count, 2, "Should load 2 subscription products.")
        XCTAssertTrue(sut.availableProducts.contains(where: { $0.id == monthlyProductID }))
        XCTAssertTrue(sut.availableProducts.contains(where: { $0.id == yearlyProductID }))
        XCTAssertNil(sut.lastError)

        localCancellables.forEach { $0.cancel() }
    }

    func test_purchaseMonthlySubscription_withSubscriptionOnlyStoreKitFile() async throws {
        let productIDs = [monthlyProductID, yearlyProductID] // Need both for SUT init
        let (sut, session, _) = try await setupSUTWithStoreKitFile(
            storeKitFilename: "TestSubscriptionOnly",
            productIDsForConfig: productIDs
        )
        // Make session available to test assertions if needed
        self.session = session // Assign to the class property if your original tests need it

        // Ensure the product we want to purchase is actually available
        guard sut.availableProducts.contains(where: { $0.id == monthlyProductID }) else {
            XCTFail("Monthly product \(monthlyProductID) not found in SUT.availableProducts. SUT has: \(sut.availableProducts.map(\.id))")
            return
        }

        let expectation = XCTestExpectation(description: "Entitlement status should become active after purchasing monthly.")
        var purchaseCancellables = Set<AnyCancellable>() // Local cancellables for this test
        sut.$entitlementStatus
            .sink { status in
            if status.isActive {
                expectation.fulfill()
            }
        }
            .store(in: &purchaseCancellables)

        print("🧪 Attempting to purchase \(monthlyProductID)...")
        await sut.purchase(productID: monthlyProductID)

        await fulfillment(of: [expectation], timeout: 10.0) // Increased timeout for purchase

        XCTAssertTrue(sut.entitlementStatus.isActive, "Entitlement should be active.")
        XCTAssertNil(sut.lastError, "Purchase should not result in an error: \(sut.lastError?.localizedDescription ?? "nil")")

        // Check transactions exist (optional, but good for sanity)
        var hasTransactions = false
        for await _ in Transaction.all { // Transaction.all should work with SKTestSession
            hasTransactions = true
            break
        }
        XCTAssertTrue(hasTransactions, "Should have at least one transaction after purchase.")

        purchaseCancellables.forEach { $0.cancel() }
    }

    func test_complete_storekit_structure() throws {

        let testBundle = Bundle(for: PurchaseServiceIntegrationTests.self)
        guard let url = testBundle.url(forResource: "Products", withExtension: "storekit") else {
            XCTFail("Could not find Products.storekit")
            return
        }

        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Check main products
        let products = json?["products"] as? [[String: Any]] ?? []
        print("📦 Main products: \(products.count)")
        for product in products {
            print("  - \(product["productID"] ?? "unknown")")
        }

        // Check subscription groups
        let subscriptionGroups = json?["subscriptionGroups"] as? [[String: Any]] ?? []
        print("📦 Subscription groups: \(subscriptionGroups.count)")
        for group in subscriptionGroups {
            let subscriptions = group["subscriptions"] as? [[String: Any]] ?? []
            print("  Group with \(subscriptions.count) subscriptions:")
            for sub in subscriptions {
                print("    - \(sub["productID"] ?? "unknown")")
            }
        }
    }

    func test_purchaseMonthlySubscription_succeeds() async throws {
        // Skip this test if products couldn't be loaded
        try XCTSkipIf(sut.availableProducts.isEmpty, "No products available to test purchasing")

        let expectation = XCTestExpectation(description: "Entitlement status should become active.")
        sut.$entitlementStatus
            .sink { status in
            if status.isActive {
                expectation.fulfill()
            }
        }
            .store(in: &cancellables)

        await sut.purchase(productID: monthlyProductID)

        await fulfillment(of: [expectation], timeout: 5.0)

        XCTAssertTrue(sut.entitlementStatus.isActive)
        XCTAssertNil(sut.lastError)

        // Check transactions exist
        var hasTransactions = false
        for await _ in Transaction.all {
            hasTransactions = true
            break
        }
        XCTAssertTrue(hasTransactions, "Should have at least one transaction")
    }

    func test_purchase_whenCancelledByUser_setsCancelledError() async throws {
        // Skip this test if products couldn't be loaded
        try XCTSkipIf(sut.availableProducts.isEmpty, "No products available to test purchasing")

        session.failTransactionsEnabled = true
        session.failureError = .paymentCancelled

        await sut.purchase(productID: monthlyProductID)

        XCTAssertFalse(sut.entitlementStatus.isActive)
        XCTAssertEqual(sut.lastError, .purchaseCancelled)
    }
}

// JEDI MANEUVER #10: Extension to help debug Product issues
extension Product {
    static var all: [Product] {
        get async throws {
            // This fetches ALL products configured in the StoreKit configuration
            return try await products(for: [])
        }
    }
}
