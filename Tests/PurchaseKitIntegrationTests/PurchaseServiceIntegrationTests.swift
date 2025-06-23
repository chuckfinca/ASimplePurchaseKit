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

    var session: SKTestSession! // General session for Products.storekit, used by setUp
    var sut: PurchaseService! // General SUT for Products.storekit, used by setUp
    var config: PurchaseConfig!
    var cancellables: Set<AnyCancellable>!

    let monthlyProductID = "com.asimplepurchasekit.pro.monthly"
    let yearlyProductID = "com.asimplepurchasekit.pro.yearly"
    let lifetimeProductID = "com.asimplepurchasekit.pro.lifetime"
    lazy var allTestProductIDs = [monthlyProductID, yearlyProductID, lifetimeProductID]

    // Original setUp - uses "Products.storekit" (mixed types)
    // IMPORTANT: Due to P3 (Unreliable Product Loading with Mixed-Type .storekit Files),
    // self.sut and self.session initialized here will likely only have the non-consumable 'lifetimeProductID'
    // available on iOS 17 simulators. Tests for subscriptions relying on this setUp will likely fail early.
    override func setUp() async throws {
        print("🧪 [SETUP] Starting PurchaseServiceIntegrationTests.setUp (using Products.storekit)")
        guard let url = getStoreKitURLInSPMBundle(filename: "Products.storekit") else {
            // The XCTFail is now inside getStoreKitURLForIntegrationTest or getSPMTestResourceBundle
            // Add a specific XCTFail here if it returns nil to make it obvious in this test's log.
            XCTFail("Could not get URL for Products.storekit in setUp. Check diagnostic logs from helper functions.")
            return
        }
        print("🧪 [SETUP] StoreKit Configuration URL: \(url.path)")

        do {
            session = try SKTestSession(contentsOf: url)
            print("🧪 [SETUP] SKTestSession initialized.")
        } catch {
            XCTFail("❌ [SETUP] SKTestSession initialization failed: \(error)")
            throw error
        }

        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.storefront = "USA"
        print("🧪 [SETUP] SKTestSession configured: reset, clearTransactions, disableDialogs, storefront='USA'.")

        let setupDelayMilliseconds: UInt64 = 1500
        print("🧪 [SETUP] Pausing for \(setupDelayMilliseconds)ms for StoreKit to settle...")
        try await Task.sleep(for: .milliseconds(setupDelayMilliseconds))
        print("🧪 [SETUP] Pause complete.")

        // Direct product check
        do {
            print("🧪 [SETUP] Performing direct check with Product.products(for: allTestProductIDs from Products.storekit)...")
            let directProductCheck = try await Product.products(for: allTestProductIDs)
            print("🧪 [SETUP] Direct check (Products.storekit): Product.products(for: [specific IDs]) found \(directProductCheck.count) products. Expected mostly 1 (lifetime) due to P3.")
            if directProductCheck.count != 1 && !directProductCheck.isEmpty { // If it's not 0 and not 1, it's unusual for P3.
                print("⚠️ [SETUP] Direct check from Products.storekit found \(directProductCheck.count) products. Typically P3 results in 1 (non-consumable only).")
            }
            if directProductCheck.isEmpty && !allTestProductIDs.isEmpty {
                print("🧪 [SETUP] Direct check (specific IDs) from Products.storekit was empty. Trying Product.products(for: [])...")
                let allDirect = try await Product.products(for: [])
                print("🧪 [SETUP] Direct check (Products.storekit): Product.products(for: []) found \(allDirect.count) products.")
                if allDirect.isEmpty {
                    print("⚠️ [SETUP] CRITICAL: Even Product.products(for: []) returned 0 products directly from StoreKit using Products.storekit.")
                }
            }
        } catch {
            print("⚠️ [SETUP] Direct product check (Product.products(for:)) failed: \(error) using Products.storekit")
        }

        config = PurchaseConfig(productIDs: allTestProductIDs, isUnitTesting: false)
        sut = PurchaseService(config: config)
        cancellables = []
        print("🧪 [SETUP] PurchaseService (SUT for Products.storekit) initialized with isUnitTesting: false.")

        print("🧪 [SETUP] SUT's init (Products.storekit) should have fetched products. Available products in SUT: \(sut.availableProducts.count)")

        // Expectation: for Products.storekit (mixed), only the lifetime product might load due to P3.
        let expectedProductsFromMixedFile = 1 // Assuming only lifetime loads
        if sut.availableProducts.count < expectedProductsFromMixedFile && !allTestProductIDs.isEmpty { // Use < in case more than 1 loads unexpectedly
            print("🧪 [SETUP] SUT products for Products.storekit (count: \(sut.availableProducts.count)) less than expected (\(expectedProductsFromMixedFile)), setting up expectation.")
            let expectation = XCTestExpectation(description: "Wait for SUT to load products (Products.storekit - expecting mostly lifetime)")

            if sut.availableProducts.count >= expectedProductsFromMixedFile { // Check again
                print("✅ [SETUP] SUT $availableProducts (Products.storekit) already sufficient before sink.")
                expectation.fulfill()
            } else {
                sut.$availableProducts
                    .sink { products in
                    // We fulfill if at least the lifetime product loads, acknowledging P3 for subscriptions
                    if products.contains(where: { $0.id == self.lifetimeProductID }) {
                        print("✅ [SETUP] SUT $availableProducts (Products.storekit) updated, contains lifetime. Count: \(products.count).")
                        expectation.fulfill()
                    } else if !products.isEmpty {
                        print("⏳ [SETUP] SUT $availableProducts (Products.storekit) updated with \(products.count) products, but not the expected lifetime yet.")
                    } else {
                        print("⏳ [SETUP] SUT $availableProducts (Products.storekit) published empty array.")
                    }
                }
                    .store(in: &cancellables)
            }
            await fulfillment(of: [expectation], timeout: 5.0)
        } else if !allTestProductIDs.isEmpty {
            print("✅ [SETUP] SUT (Products.storekit) already had products after init. Count: \(sut.availableProducts.count).")
        }

        if !sut.availableProducts.contains(where: { $0.id == self.lifetimeProductID }) && !allTestProductIDs.isEmpty {
            print("❌ [SETUP] FINAL VERDICT (Products.storekit): SUT availableProducts does NOT contain lifetime. This is unexpected even with P3.")
        } else if !allTestProductIDs.isEmpty {
            print("✅ [SETUP] FINAL VERDICT (Products.storekit): SUT has \(sut.availableProducts.count) products (likely just lifetime). Setup for general tests complete.")
        }
    }

    override func tearDown() async throws {
        print("🧪 [TEARDOWN] Clearing transactions and nilling objects.")
        session?.clearTransactions()
        session = nil
        sut = nil
        config = nil
        cancellables?.forEach { $0.cancel() }
        cancellables = nil
    }

    private var nestedBundleName: String { // Make it a computed property for flexibility
        // You might need to adjust this if SPM's naming convention changes
        // or make it more dynamic if possible. For now, hardcoding is okay
        // based on what the diagnostic test found.
        return "ASimplePurchaseKitProject_PurchaseKitIntegrationTests.bundle"
    }

    private func getSPMTestResourceBundle(mainTestBundle: Bundle) -> Bundle? {
        // Use the exact logic from SPMStoreKitDiagnostics.swift's getSPMTestResourceBundle
        // that successfully found the nested bundle.
        // For example:
        guard let nestedBundleURL = mainTestBundle.url(forResource: (nestedBundleName as NSString).deletingPathExtension,
                                                       withExtension: (nestedBundleName as NSString).pathExtension) else {
            print("⚠️ [PSI] Could not find nested resource bundle '\(nestedBundleName)' directly in main test bundle: \(mainTestBundle.bundlePath).")
            // Add robust enumeration fallback if needed, as in SPMStoreKitDiagnostics
            if let resourcePath = mainTestBundle.resourcePath,
                let enumerator = FileManager.default.enumerator(atPath: resourcePath) {
                for case let path as String in enumerator {
                    if path.hasSuffix(".bundle") && path.contains("PurchaseKitIntegrationTests") {
                        let potentialURL = URL(fileURLWithPath: resourcePath).appendingPathComponent(path)
                        if let bundle = Bundle(url: potentialURL) {
                            print("✅ [PSI] Found potential nested bundle via enumeration: \(bundle.bundlePath)")
                            return bundle
                        }
                    }
                }
            }
            print("❌ [PSI] Failed to find nested resource bundle via enumeration as well.")
            return nil
        }

        guard let bundle = Bundle(url: nestedBundleURL) else {
            print("❌ [PSI] Found URL for '\(nestedBundleName)' but could not create Bundle instance from it: \(nestedBundleURL.path)")
            return nil
        }
        print("✅ [PSI] Successfully loaded nested resource bundle: \(bundle.bundlePath)")
        return bundle
    }

    private func getStoreKitURLInSPMBundle(filename: String) -> URL? {
        // Use the exact logic from SPMStoreKitDiagnostics.swift's getStoreKitURLInSPMBundle
        // that successfully found the .storekit files.
        // For example:
        let mainTestBundle = Bundle(for: PurchaseServiceIntegrationTests.self) // Specific to this class
        guard let spmResourceBundle = getSPMTestResourceBundle(mainTestBundle: mainTestBundle) else {
            XCTFail("[PSI] CRITICAL: Could not get SPM resource bundle. StoreKit file '\(filename)' cannot be loaded.")
            return nil
        }

        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension

        print("ℹ️ [PSI] Attempting to load '\(filename)' from SPM bundle: \(spmResourceBundle.bundlePath), name: '\(name)', ext: '\(ext)'")

        guard let url = spmResourceBundle.url(forResource: name, withExtension: ext) else { // Loading from root of spmResourceBundle
            XCTFail("[PSI] Failed to get URL for '\(filename)' (name: '\(name)', ext: '\(ext)') from root of SPM resource bundle: \(spmResourceBundle.bundlePath)")
            // ... (optional content listing for debug as before)
            return nil
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("[PSI] URL for '\(filename)' obtained but file does not exist at: \(url.path)")
            return nil
        }
        print("✅ [PSI] Confirmed URL for '\(filename)': \(url.path)")
        return url
    }

    // Helper to set up SUT with a specific .storekit file
    private func setupSUTWithStoreKitFile(
        storeKitFilename: String,
        productIDsForConfig: [String]
    ) async throws -> (sut: PurchaseService, session: SKTestSession, cancellables: Set<AnyCancellable>) {
        print("🧪 [FOCUSED SETUP] Starting for \(storeKitFilename)")

        guard let url = getStoreKitURLInSPMBundle(filename: storeKitFilename) else {
            // Throwing an error is appropriate here as the function signature allows it
            let errorMsg = "Could not get URL for \(storeKitFilename). Check diagnostic logs from helper functions."
            XCTFail(errorMsg) // Also log it
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        print("🧪 [FOCUSED SETUP] StoreKit Configuration URL: \(url.path)")


        let newSession = try SKTestSession(contentsOf: url)
        print("🧪 [FOCUSED SETUP] SKTestSession initialized for \(storeKitFilename).")

        newSession.resetToDefaultState()
        newSession.clearTransactions()
        newSession.disableDialogs = true
        newSession.storefront = "USA"
        print("🧪 [FOCUSED SETUP] SKTestSession configured for \(storeKitFilename).")

        let setupDelayMilliseconds: UInt64 = 2000
        print("🧪 [FOCUSED SETUP] Pausing for \(setupDelayMilliseconds)ms for StoreKit to settle with \(storeKitFilename)...")
        try await Task.sleep(for: .milliseconds(setupDelayMilliseconds))
        print("🧪 [FOCUSED SETUP] Pause complete for \(storeKitFilename).")

        var directProductCheck: [Product] = []
        if !productIDsForConfig.isEmpty {
            directProductCheck = try await Product.products(for: productIDsForConfig)
            print("🧪 [FOCUSED SETUP] Direct check from StoreKit: Product.products(for: [specific IDs]) found \(directProductCheck.count) products for \(storeKitFilename).")
        }
        if directProductCheck.isEmpty && !productIDsForConfig.isEmpty {
            print("⚠️ [FOCUSED SETUP] Direct check for \(storeKitFilename) found NO products with specific IDs. Trying Product.products(for: [])...")
            let allDirect = try await Product.products(for: [])
            print("🧪 [FOCUSED SETUP] Direct check (Product.all) from StoreKit: Product.products(for: []) found \(allDirect.count) products for \(storeKitFilename).")
        }

        let newConfig = PurchaseConfig(productIDs: productIDsForConfig, isUnitTesting: false)
        let newSut = PurchaseService(config: newConfig)
        var newCancellables = Set<AnyCancellable>()
        print("🧪 [FOCUSED SETUP] PurchaseService (SUT) initialized for \(storeKitFilename) with isUnitTesting: false.")

        print("🧪 [FOCUSED SETUP] SUT's init for \(storeKitFilename) should have fetched. Available products: \(newSut.availableProducts.count)")

        if newSut.availableProducts.count != productIDsForConfig.count && !productIDsForConfig.isEmpty {
            let expectation = XCTestExpectation(description: "Wait for SUT to load products for \(storeKitFilename)")
            if newSut.availableProducts.count == productIDsForConfig.count {
                print("✅ [FOCUSED SETUP] SUT $availableProducts already correct for \(storeKitFilename) before sink.")
                expectation.fulfill()
            } else {
                print("⏳ [FOCUSED SETUP] SUT $availableProducts for \(storeKitFilename) not yet \(productIDsForConfig.count), current: \(newSut.availableProducts.count). Waiting...")
                newSut.$availableProducts
                    .sink { products in
                    if products.count == productIDsForConfig.count {
                        print("✅ [FOCUSED SETUP] SUT $availableProducts updated for \(storeKitFilename) with \(products.count) products.")
                        expectation.fulfill()
                    } else if storeKitFilename == "TestSubscriptionOnly" && products.isEmpty {
                        // For TestSubscriptionOnly, if P1 hits, products will be empty. Don't fulfill here, let timeout.
                        print("⏳ [FOCUSED SETUP] SUT $availableProducts for \(storeKitFilename) (subscriptions) published empty (P1 likely).")
                    } else {
                        print("⏳ [FOCUSED SETUP] SUT $availableProducts for \(storeKitFilename) published \(products.count) (expected \(productIDsForConfig.count)).")
                    }
                }
                    .store(in: &newCancellables)
            }
            // Allow timeout for subscription tests if P1 is active
            let timeout = storeKitFilename == "TestSubscriptionOnly" ? 10.0 : 5.0
            let result = await XCTWaiter.fulfillment(of: [expectation], timeout: timeout)
            if result == .timedOut && storeKitFilename == "TestSubscriptionOnly" {
                print("⏳ [FOCUSED SETUP] Timed out waiting for subscription products for \(storeKitFilename), likely due to P1.")
            }
        } else if !productIDsForConfig.isEmpty {
            print("✅ [FOCUSED SETUP] SUT for \(storeKitFilename) product count (\(newSut.availableProducts.count)) matches expected (\(productIDsForConfig.count)) after init.")
        }

        if newSut.availableProducts.count != productIDsForConfig.count && !productIDsForConfig.isEmpty {
            print("⚠️ [FOCUSED SETUP] After wait, SUT product count (\(newSut.availableProducts.count)) still mismatch for \(storeKitFilename) (expected \(productIDsForConfig.count)).")
        }
        return (newSut, newSession, newCancellables)
    }

    func test_fetchLifetimeProduct_withLifetimeOnlyStoreKitFile() async throws {
        let (sut, _, cancellables) = try await setupSUTWithStoreKitFile(
            storeKitFilename: "TestLifetimeOnly.storekit",
            productIDsForConfig: [lifetimeProductID]
        )
        var localCancellables = cancellables
        defer { localCancellables.forEach { $0.cancel() } }

        XCTAssertEqual(sut.availableProducts.count, 1, "Should load 1 lifetime product from TestLifetimeOnly.storekit.")
        XCTAssertEqual(sut.availableProducts.first?.id, lifetimeProductID)
        XCTAssertNil(sut.lastFailure?.error)
    }

    // This test acts as a canary for P1 (iOS 17 Sim bug with auto-renewables)
    func test_fetchSubscriptionProducts_withSubscriptionOnlyStoreKitFile() async throws {
        let subscriptionProductIDs = [monthlyProductID, yearlyProductID]
        let (sut, _, cancellables) = try await setupSUTWithStoreKitFile(
            storeKitFilename: "TestSubscriptionOnly.storekit",
            productIDsForConfig: subscriptionProductIDs
        )
        var localCancellables = cancellables
        defer { localCancellables.forEach { $0.cancel() } }

        if sut.availableProducts.count != subscriptionProductIDs.count {
            print("⚠️ WARNING (P1): Expected \(subscriptionProductIDs.count) subscription products from TestSubscriptionOnly.storekit, but found \(sut.availableProducts.count). This is likely due to StoreKit simulator bug P1 (iOS 17).")
            // This test is expected to fail on affected simulators due to P1.
            // The XCTAssertEqual below will capture the failure.
        }

        XCTAssertEqual(sut.availableProducts.count, subscriptionProductIDs.count, "P1 CHECK: Should load \(subscriptionProductIDs.count) subscription products from TestSubscriptionOnly.storekit. Failure indicates P1 is active.")
        if sut.availableProducts.count == subscriptionProductIDs.count { // Only check contents if count matches
            XCTAssertTrue(sut.availableProducts.contains(where: { $0.id == monthlyProductID }))
            XCTAssertTrue(sut.availableProducts.contains(where: { $0.id == yearlyProductID }))
        }
        // If products didn't load, lastError might be .productsNotFound
        if sut.availableProducts.isEmpty && !subscriptionProductIDs.isEmpty {
            XCTAssertEqual(sut.lastFailure?.error, .productsNotFound, "If P1 causes no products to load, lastError should be .productsNotFound")
        } else {
            XCTAssertNil(sut.lastFailure?.error)
        }
    }

    // This test acts as a canary for P1/P2 (iOS 17/18.x Sim bug with auto-renewables purchase)
    func test_purchaseMonthlySubscription_withSubscriptionOnlyStoreKitFile() async throws {
        let subscriptionProductIDs = [monthlyProductID, yearlyProductID]
        let (sut, session, cancellables) = try await setupSUTWithStoreKitFile(
            storeKitFilename: "TestSubscriptionOnly.storekit",
            productIDsForConfig: subscriptionProductIDs
        )
        var localCancellables = cancellables
        defer { localCancellables.forEach { $0.cancel() } }

        guard sut.availableProducts.contains(where: { $0.id == monthlyProductID }) else {
            let message = "P1 CHECK: Monthly product (\(monthlyProductID)) not found for purchase. SUT has: \(sut.availableProducts.map(\.id)). This is expected if P1 (StoreKit bug) is active."
            print("⚠️ \(message)")
            // If P1 prevents product loading, this XCTFail is expected.
            XCTFail(message + " Test cannot proceed to purchase.")
            return
        }

        let expectation = XCTestExpectation(description: "Entitlement status should become active after purchasing monthly from TestSubscriptionOnly.storekit.")
        sut.$entitlementStatus
            .sink { status in
            if status.isActive {
                expectation.fulfill()
            }
        }
            .store(in: &localCancellables)

        print("🧪 Attempting to purchase \(monthlyProductID) using TestSubscriptionOnly.storekit...")
        await sut.purchase(productID: monthlyProductID)

        await fulfillment(of: [expectation], timeout: 10.0)

        XCTAssertTrue(sut.entitlementStatus.isActive, "Entitlement should be active after successful subscription purchase.")
        if case .subscribed(let expires, _) = sut.entitlementStatus {
            XCTAssertNotNil(expires, "Subscription should have an expiration date.")
        } else {
            XCTFail("Entitlement status is not .subscribed for subscription: \(sut.entitlementStatus)")
        }
        XCTAssertNil(sut.lastFailure?.error, "Purchase should not result in an error: \(sut.lastFailure?.error.localizedDescription ?? "nil")")

        var hasTransactions = false
        if !session.allTransactions().isEmpty {
            hasTransactions = true
        }
        XCTAssertTrue(hasTransactions, "SKTestSession should have at least one transaction after purchase.")
    }

    func test_nonConsumable_fullFlow_usingLifetimeOnlyFile() async throws {
        let (sut, session, cancellables) = try await setupSUTWithStoreKitFile(
            storeKitFilename: "TestLifetimeOnly.storekit",
            productIDsForConfig: [lifetimeProductID]
        )
        var activeCancellables = cancellables
        defer { activeCancellables.forEach { $0.cancel() } }

        XCTAssertEqual(sut.availableProducts.count, 1, "Should load 1 lifetime product.")
        guard let productToPurchase = sut.availableProducts.first(where: { $0.id == lifetimeProductID }) else {
            XCTFail("Lifetime product not found.")
            return
        }
        XCTAssertEqual(productToPurchase.id, lifetimeProductID)
        XCTAssertNil(sut.lastFailure?.error)

        await sut.updateEntitlementStatus()
        XCTAssertFalse(sut.entitlementStatus.isActive, "Entitlement should not be active before purchase.")

        let purchaseExpectation = XCTestExpectation(description: "Entitlement status becomes .subscribed (non-consumable) after purchase.")
        sut.$entitlementStatus
            .dropFirst()
            .sink { status in
            if case .subscribed(let expires, let isInGracePeriod) = status, expires == nil, !isInGracePeriod {
                purchaseExpectation.fulfill()
            }
        }
            .store(in: &activeCancellables)

        await sut.purchase(productID: lifetimeProductID)
        await fulfillment(of: [purchaseExpectation], timeout: 10.0)

        XCTAssertTrue(sut.entitlementStatus.isActive, "Entitlement should be active after purchase.")
        if case .subscribed(let expires, let isInGracePeriod) = sut.entitlementStatus {
            XCTAssertNil(expires)
            XCTAssertFalse(isInGracePeriod)
        } else {
            XCTFail("Entitlement status is not correct for non-consumable: \(sut.entitlementStatus)")
        }
        XCTAssertNil(sut.lastFailure?.error, "Purchase should be successful. Error: \(sut.lastFailure?.error.localizedDescription ?? "nil")")
        XCTAssertFalse(session.allTransactions().isEmpty, "SKTestSession should have transaction after non-consumable purchase.")

        sut.entitlementStatus = .notSubscribed
        let restoreExpectation = XCTestExpectation(description: "Entitlement status restored to active (non-consumable).")
        sut.$entitlementStatus
            .dropFirst()
            .sink { status in
            if case .subscribed(let expires, let isInGracePeriod) = status, expires == nil, !isInGracePeriod {
                restoreExpectation.fulfill()
            }
        }
            .store(in: &activeCancellables)

        await sut.restorePurchases()
        await fulfillment(of: [restoreExpectation], timeout: 5.0)

        XCTAssertTrue(sut.entitlementStatus.isActive, "Entitlement should be restored.")
        if case .subscribed(let expires, let isInGracePeriod) = sut.entitlementStatus {
            XCTAssertNil(expires)
            XCTAssertFalse(isInGracePeriod)
        } else {
            XCTFail("Restored entitlement status is not correct for non-consumable: \(sut.entitlementStatus)")
        }
        XCTAssertNil(sut.lastFailure?.error, "Restore purchases should be successful.")

        // Cancellation Test for Non-Consumable
        print("🧪 Setting up for non-consumable purchase cancellation test...")
        let (sutCancel, cancelSession, cancelCancellablesSetup) = try await setupSUTWithStoreKitFile(
            storeKitFilename: "TestLifetimeOnly.storekit",
            productIDsForConfig: [lifetimeProductID]
        )
        var activeCancelCancellables = cancelCancellablesSetup
        defer { activeCancelCancellables.forEach { $0.cancel() } }

        await sutCancel.updateEntitlementStatus()
        XCTAssertFalse(sutCancel.entitlementStatus.isActive, "Entitlement should not be active for cancellation test setup.")

        cancelSession.failTransactionsEnabled = true
        cancelSession.failureError = .paymentCancelled

        await sutCancel.purchase(productID: lifetimeProductID)

        if sutCancel.lastFailure?.error == .purchaseCancelled {
            XCTAssertFalse(sutCancel.entitlementStatus.isActive, "Entitlement should not be active after correctly cancelled purchase.")
            print("✅ Cancellation simulated as .paymentCancelled correctly.")
        } else if case .underlyingError(let underlyingError) = sutCancel.lastFailure?.error,
            let skError = underlyingError as? StoreKitError, // Make sure it's specifically StoreKitError
            case .unknown = skError { // And specifically .unknown
            print("⚠️ P6 DETECTED: `SKTestSession.failureError = .paymentCancelled` resulted in `.underlyingError(StoreKitError.unknown)`. This is an Apple StoreKit testing bug (P6).")
            XCTAssertFalse(sutCancel.entitlementStatus.isActive, "Entitlement should not be active after P6-affected cancelled purchase.")
            // Using XCTSkip here is appropriate as the SUT correctly reports an error, but not the one StoreKit *should* have given.
            XCTSkip("Skipping direct assertion for .purchaseCancelled due to P6 - SKTestSession bug where .paymentCancelled results in a generic StoreKitError.unknown.")
        } else {
            XCTFail("Expected .purchaseCancelled or P6-related .underlyingError(StoreKitError.unknown), but got \(String(describing: sutCancel.lastFailure?.error)).")
        }

        cancelSession.failTransactionsEnabled = false
    }

    func test_complete_storekit_structure() throws {
        let testBundle = Bundle(for: PurchaseServiceIntegrationTests.self)
        guard let url = getStoreKitURLInSPMBundle(filename: "Products.storekit") else {
            XCTFail("Could not find Products.storekit")
            return
        }
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let products = json?["products"] as? [[String: Any]] ?? []
        print("📦 Main products in Products.storekit: \(products.count)")
        XCTAssertFalse(products.isEmpty, "Products.storekit should have non-consumable products defined.")

        let subscriptionGroups = json?["subscriptionGroups"] as? [[String: Any]] ?? []
        print("📦 Subscription groups in Products.storekit: \(subscriptionGroups.count)")
        XCTAssertFalse(subscriptionGroups.isEmpty, "Products.storekit should have subscription groups defined.")
    }

    // Refactored to use TestSubscriptionOnly.storekit; expected to fail product loading due to P1.
    func test_purchaseMonthlySubscription_succeeds_usingSubscriptionFile() async throws {
        let subscriptionProductIDs = [monthlyProductID, yearlyProductID]
        let (sutSub, sessionSub, cancellablesSub) = try await setupSUTWithStoreKitFile(
            storeKitFilename: "TestSubscriptionOnly.storekit",
            productIDsForConfig: subscriptionProductIDs
        )
        var localCancellables = cancellablesSub
        defer { localCancellables.forEach { $0.cancel() } }

        guard sutSub.availableProducts.contains(where: { $0.id == monthlyProductID }) else {
            let message = "P1 CHECK (from test_purchaseMonthlySubscription_succeeds_usingSubscriptionFile): Monthly product not loaded from TestSubscriptionOnly.storekit due to P1. Available: \(sutSub.availableProducts.map(\.id))."
            print("⚠️ \(message)")
            XCTFail(message + " Test cannot proceed.") // This XCTFail is expected if P1 is active.
            return
        }

        let expectation = XCTestExpectation(description: "Entitlement status should become active (TestSubscriptionOnly.storekit).")
        sutSub.$entitlementStatus
            .sink { status in
            if status.isActive {
                expectation.fulfill()
            }
        }
            .store(in: &localCancellables)

        await sutSub.purchase(productID: monthlyProductID)
        await fulfillment(of: [expectation], timeout: 10.0)

        XCTAssertTrue(sutSub.entitlementStatus.isActive, "Entitlement via TestSubscriptionOnly.storekit. Check P1 if fails.")
        XCTAssertNil(sutSub.lastFailure?.error)
        XCTAssertFalse(sessionSub.allTransactions().isEmpty, "SKTestSession (TestSubscriptionOnly.storekit) should have transactions.")
    }

    // Refactored to test cancellation of a non-consumable using self.sut (Products.storekit)
    func test_purchase_nonConsumable_whenCancelledByUser_setsCancelledError() async throws {
        // self.sut is from setUp(), uses Products.storekit. Expect lifetimeProductID to be available.
        try XCTSkipIf(self.sut == nil || self.session == nil, "SUT or Session from global setUp is nil.")
        guard self.sut.availableProducts.contains(where: { $0.id == lifetimeProductID }) else {
            XCTFail("P3 CHECK: Lifetime product (\(lifetimeProductID)) not found in SUT from Products.storekit. Available: \(self.sut.availableProducts.map(\.id)). Cannot test cancellation.")
            return
        }

        // Ensure the global session from setUp is used.
        self.session.failTransactionsEnabled = true
        self.session.failureError = .paymentCancelled

        await self.sut.purchase(productID: lifetimeProductID)

        if self.sut.lastFailure?.error == .purchaseCancelled {
            XCTAssertFalse(self.sut.entitlementStatus.isActive, "Entitlement should not be active after correctly cancelled purchase.")
            print("✅ Non-consumable cancellation simulated as .paymentCancelled correctly using Products.storekit.")
        } else if case .underlyingError(let underlyingError) = self.sut.lastFailure?.error,
            let skError = underlyingError as? StoreKitError, // Make sure it's specifically StoreKitError
            case .unknown = skError { // And specifically .unknown
            print("⚠️ P6 DETECTED (Products.storekit): `SKTestSession.failureError = .paymentCancelled` resulted in `.underlyingError(StoreKitError.unknown)`. This is an Apple StoreKit testing bug (P6).")
            XCTAssertFalse(self.sut.entitlementStatus.isActive, "Entitlement should not be active after P6-affected cancelled purchase.")
            // Using XCTSkip here is appropriate
            XCTSkip("Skipping direct assertion for .purchaseCancelled due to P6 - SKTestSession bug where .paymentCancelled results in a generic StoreKitError.unknown.")
        } else {
            XCTFail("Expected .purchaseCancelled or P6-related .underlyingError(StoreKitError.unknown) for non-consumable cancellation, but got \(String(describing: self.sut.lastFailure?.error)).")
        }

        self.session.failTransactionsEnabled = false // Reset for other tests
    }

    // Original test_skTestSession_canFetchProducts
    // This test relies on the scheme's StoreKit config if session is not used, or session if used.
    // The test name implies it uses SKTestSession, so it should use the one from setUp or a local one.
    func test_skTestSession_canFetchProducts() async throws {
        // This test uses the `session` from `setUp()`, which is configured with "Products.storekit"
        try XCTSkipIf(session == nil, "SKTestSession from setUp was not initialized.")

        try await Task.sleep(for: .milliseconds(500))

        let products = try await Product.products(for: [monthlyProductID, lifetimeProductID])
        // With P3, only lifetimeProductID is expected from Products.storekit
        print("🔍 test_skTestSession_canFetchProducts (Products.storekit): Fetched \(products.count) products using specific IDs. Expected 1 (lifetime) due to P3.")
        XCTAssertEqual(products.count, 1, "P3 Check: Should fetch only 1 product (lifetime) from mixed Products.storekit with specific IDs.")
        XCTAssertTrue(products.contains(where: { $0.id == lifetimeProductID }), "P3 Check: The fetched product should be lifetime.")


        let allProducts = try await Product.all // Product.products(for: [])
        print("🔍 test_skTestSession_canFetchProducts (Products.storekit): Product.all returned \(allProducts.count) products. Expected 0 or 1 due to P3 unreliability.")
        // P3 states Product.all is unreliable. It might return 0 or just the non-consumable.
        // XCTAssertTrue(allProducts.count <= 1, "P3 Check: Product.all from mixed Products.storekit should return 0 or 1 product.")
        if allProducts.count > 1 {
            print("⚠️ P3 behavior Product.all from mixed Products.storekit returned \(allProducts.count) products unexpectedly.")
        }
    }
}
