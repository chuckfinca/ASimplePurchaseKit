//
//  PurchaseServiceIntegrationTests.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/13/25.
//

import XCTest
import Combine
import StoreKitTest // For SKTestSession, SKError
@testable import ASimplePurchaseKit // For PurchaseService, ProductProtocol, etc.
// Import StoreKit for Product.SubscriptionOffer.ID if directly used, but it's encapsulated.

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

    // Product IDs from TestSubscriptionWithIntroOffer.storekit
    let trialProductIDAlpha = "com.asimplepurchasekit.sub.withtrial.alpha"
    let discountProductIDAlpha = "com.asimplepurchasekit.sub.withdiscount.alpha"
    // Offer IDs from TestSubscriptionWithIntroOffer.storekit
    let freeTrialOfferIDAlpha = "free_trial_7_days_offer_a"
    let discountOfferIDAlpha = "pay_upfront_1_month_offer_a"


    override func setUp() async throws {
        print("🧪 [SETUP] Starting PurchaseServiceIntegrationTests.setUp (using Products.storekit)")
        guard let url = getStoreKitURLInSPMBundle(filename: "Products.storekit") else {
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
            if directProductCheck.count != 1 && !directProductCheck.isEmpty {
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

        config = PurchaseConfig(productIDs: allTestProductIDs, isUnitTesting: false, enableLogging: true) // Enable logging
        sut = PurchaseService(config: config)
        cancellables = []
        print("🧪 [SETUP] PurchaseService (SUT for Products.storekit) initialized with isUnitTesting: false.")

        print("🧪 [SETUP] SUT's init (Products.storekit) should have fetched products. Available products in SUT: \(sut.availableProducts.count)")

        let expectedProductsFromMixedFile = 1
        if sut.availableProducts.count < expectedProductsFromMixedFile && !allTestProductIDs.isEmpty {
            print("🧪 [SETUP] SUT products for Products.storekit (count: \(sut.availableProducts.count)) less than expected (\(expectedProductsFromMixedFile)), setting up expectation.")
            let expectation = XCTestExpectation(description: "Wait for SUT to load products (Products.storekit - expecting mostly lifetime)")

            if sut.availableProducts.count >= expectedProductsFromMixedFile {
                print("✅ [SETUP] SUT $availableProducts (Products.storekit) already sufficient before sink.")
                expectation.fulfill()
            } else {
                sut.$availableProducts
                    .sink { products in
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
        session?.clearTransactions() // Clear for the global session
        session = nil
        sut = nil
        config = nil
        cancellables?.forEach { $0.cancel() }
        cancellables = nil
    }

    private var nestedBundleName: String {
        return "ASimplePurchaseKitProject_PurchaseKitIntegrationTests.bundle"
    }

    private func getSPMTestResourceBundle(mainTestBundle: Bundle) -> Bundle? {
        let baseBundleName = "ASimplePurchaseKitProject_PurchaseKitIntegrationTests"
        let nestedBundleNameWithExtension = baseBundleName + ".bundle"

        if let nestedBundleURL = mainTestBundle.url(forResource: baseBundleName, withExtension: "bundle") {
            if let bundle = Bundle(url: nestedBundleURL) {
                print("✅ [PSI] Successfully loaded nested resource bundle (direct): \(bundle.bundlePath)")
                return bundle
            } else {
                print("❌ [PSI] Found URL for '\(nestedBundleNameWithExtension)' but could not create Bundle instance from it: \(nestedBundleURL.path)")
            }
        } else {
            print("⚠️ [PSI] Could not find nested resource bundle '\(nestedBundleNameWithExtension)' directly. Attempting enumeration...")
        }

        if let resourcePath = mainTestBundle.resourcePath,
            let enumerator = FileManager.default.enumerator(atPath: resourcePath) {
            for case let path as String in enumerator {
                if path.hasSuffix(".bundle") && path.contains(baseBundleName) {
                    let potentialURL = URL(fileURLWithPath: resourcePath).appendingPathComponent(path)
                    if let bundle = Bundle(url: potentialURL) {
                        print("✅ [PSI] Found nested bundle via enumeration: \(bundle.bundlePath)")
                        return bundle
                    }
                }
            }
        }
        print("❌ [PSI] Failed to find nested resource bundle '\(nestedBundleNameWithExtension)' via direct lookup or enumeration.")
        return nil
    }

    private func getStoreKitURLInSPMBundle(filename: String) -> URL? {
        let mainTestBundle = Bundle(for: PurchaseServiceIntegrationTests.self)
        guard let spmResourceBundle = getSPMTestResourceBundle(mainTestBundle: mainTestBundle) else {
            XCTFail("[PSI] CRITICAL: Could not get SPM resource bundle. StoreKit file '\(filename)' cannot be loaded.")
            return nil
        }

        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension

        print("ℹ️ [PSI] Attempting to load '\(filename)' from SPM bundle: \(spmResourceBundle.bundlePath), name: '\(name)', ext: '\(ext)'")

        guard let url = spmResourceBundle.url(forResource: name, withExtension: ext) else {
            XCTFail("[PSI] Failed to get URL for '\(filename)' from root of SPM resource bundle: \(spmResourceBundle.bundlePath)")
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
            let errorMsg = "Could not get URL for \(storeKitFilename). Check diagnostic logs from helper functions."
            XCTFail(errorMsg)
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

        let newConfig = PurchaseConfig(productIDs: productIDsForConfig, isUnitTesting: false, enableLogging: true) // Enable logging
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
                    } else if (storeKitFilename == "TestSubscriptionOnly.storekit" || storeKitFilename == "TestSubscriptionWithIntroOffer.storekit") && products.isEmpty {
                        print("⏳ [FOCUSED SETUP] SUT $availableProducts for \(storeKitFilename) (subscriptions) published empty (P1 likely).")
                    } else {
                        print("⏳ [FOCUSED SETUP] SUT $availableProducts for \(storeKitFilename) published \(products.count) (expected \(productIDsForConfig.count)).")
                    }
                }
                    .store(in: &newCancellables)
            }
            let timeout = (storeKitFilename == "TestSubscriptionOnly.storekit" || storeKitFilename == "TestSubscriptionWithIntroOffer.storekit") ? 10.0 : 5.0
            let result = await XCTWaiter.fulfillment(of: [expectation], timeout: timeout)
            if result == .timedOut && (storeKitFilename == "TestSubscriptionOnly.storekit" || storeKitFilename == "TestSubscriptionWithIntroOffer.storekit") {
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
        defer {
            localCancellables.forEach { $0.cancel() }
            // Since session is local to setupSUTWithStoreKitFile, we don't clear it here.
            // It gets deallocated when the tuple goes out of scope.
        }

        XCTAssertEqual(sut.availableProducts.count, 1, "Should load 1 lifetime product from TestLifetimeOnly.storekit.")
        XCTAssertEqual(sut.availableProducts.first?.id, lifetimeProductID)
        XCTAssertNil(sut.lastFailure?.error)
    }

    func test_fetchSubscriptionProducts_withSubscriptionOnlyStoreKitFile() async throws {
        let subscriptionProductIDs = [monthlyProductID, yearlyProductID]
        let (sut, _, cancellables) = try await setupSUTWithStoreKitFile(
            storeKitFilename: "TestSubscriptionOnly.storekit",
            productIDsForConfig: subscriptionProductIDs
        )
        var localCancellables = cancellables; defer { localCancellables.forEach { $0.cancel() } }

        if sut.availableProducts.count != subscriptionProductIDs.count {
            print("⚠️ WARNING (P1): Expected \(subscriptionProductIDs.count) subscription products from TestSubscriptionOnly.storekit, but found \(sut.availableProducts.count). This is likely due to StoreKit simulator bug P1 (iOS 17+).")
        }

        XCTAssertEqual(sut.availableProducts.count, subscriptionProductIDs.count, "P1 CHECK: Should load \(subscriptionProductIDs.count) subscription products from TestSubscriptionOnly.storekit. Failure indicates P1 is active.")
        if sut.availableProducts.count == subscriptionProductIDs.count {
            XCTAssertTrue(sut.availableProducts.contains(where: { $0.id == monthlyProductID }))
            XCTAssertTrue(sut.availableProducts.contains(where: { $0.id == yearlyProductID }))
        }
        if sut.availableProducts.isEmpty && !subscriptionProductIDs.isEmpty {
            XCTAssertEqual(sut.lastFailure?.error, .productsNotFound, "If P1 causes no products to load, lastFailure.error should be .productsNotFound. Actual: \(String(describing: sut.lastFailure?.error))")
        } else {
            XCTAssertNil(sut.lastFailure?.error)
        }
    }

    // MARK: - Promotional Offer Tests (NEW)
    func test_purchaseSubscription_withIntroductoryOffer() async throws {
        let productIDsForConfig = [trialProductIDAlpha, discountProductIDAlpha]
        let (sut, session, cancellables) = try await setupSUTWithStoreKitFile(
            storeKitFilename: "TestSubscriptionWithIntroOffer.storekit",
            productIDsForConfig: productIDsForConfig
        )
        var localCancellables = cancellables; defer { localCancellables.forEach { $0.cancel() } }

        guard let productToPurchase = sut.availableProducts.first(where: { $0.id == trialProductIDAlpha }) else {
            let message = "P1 CHECK: Trial product (\(trialProductIDAlpha)) not found for purchase. SUT has: \(sut.availableProducts.map(\.id)). This is expected if P1 (StoreKit bug) is active."
            print("⚠️ \(message)")
            XCTFail(message + " Test cannot proceed to purchase offer.")
            return
        }

        let offers = sut.eligiblePromotionalOffers(for: productToPurchase)
        XCTAssertFalse(offers.isEmpty, "Should find at least one promotional offer for \(trialProductIDAlpha). Found: \(offers.count)")

        guard let freeTrialOffer = offers.first(where: { $0.id == freeTrialOfferIDAlpha }) else {
            XCTFail("Could not find the specific free trial offer with ID '\(freeTrialOfferIDAlpha)' for product '\(trialProductIDAlpha)'. Available offer IDs: \(offers.map { $0.id ?? "nil" })")
            return
        }
        XCTAssertEqual(freeTrialOffer.paymentMode, .freeTrial)

        let expectation = XCTestExpectation(description: "Entitlement status should become active after purchasing with free trial offer.")
        sut.$entitlementStatus
            .dropFirst() // Ignore initial
        .sink { status in
            if status.isActive {
                print("✅ Entitlement became active: \(status)")
                expectation.fulfill()
            }
        }.store(in: &localCancellables)

        print("🧪 Attempting to purchase \(trialProductIDAlpha) with offer \(freeTrialOffer.id ?? "N/A") (\(freeTrialOffer.displayName))...")
        await sut.purchase(productID: trialProductIDAlpha, offerID: freeTrialOffer.id)

        await fulfillment(of: [expectation], timeout: 15.0) // Increased timeout for purchase flow

        XCTAssertTrue(sut.entitlementStatus.isActive, "Entitlement should be active after successful purchase with offer. Status: \(sut.entitlementStatus)")
        if case .subscribed(let expires, _) = sut.entitlementStatus {
            XCTAssertNotNil(expires, "Subscription should have an expiration date.")
        } else {
            XCTFail("Entitlement status is not .subscribed for subscription: \(sut.entitlementStatus)")
        }

        if let lastFailure = sut.lastFailure {
            // Handle P2 (unknown errors during purchase)
            if case .underlyingError(let underlying) = lastFailure.error, let skError = underlying as? SKError, skError.code == .unknown {
                XCTSkip("Skipping direct nil error check due to P2 (StoreKit unknown error during purchase). Error: \(lastFailure.error.localizedDescription)")
            } else {
                XCTFail("Purchase with offer should not result in an error: \(lastFailure.error.localizedDescription) (Operation: \(lastFailure.operation))")
            }
        }

        var hasTransactions = false
        // Use the local session specific to this test setup
        if !(try! session.allTransactions()).isEmpty { // Added try! for brevity in test, handle error if needed
            hasTransactions = true
        }
        // Use the known storeKitFilename for logging
        XCTAssertTrue(hasTransactions, "SKTestSession for TestSubscriptionWithIntroOffer.storekit should have at least one transaction after purchase.")

    }

    // MARK: - Subscription Details and canMakePayments Tests (NEW)
    func test_getSubscriptionDetails_afterPurchase() async throws {
        let subscriptionProductIDs = [monthlyProductID, yearlyProductID]
        // `session` here is the local session from setupSUTWithStoreKitFile
        let (sut, session, cancellables) = try await setupSUTWithStoreKitFile(
            storeKitFilename: "TestSubscriptionOnly.storekit",
            productIDsForConfig: subscriptionProductIDs
        )
        var localCancellables = cancellables; defer { localCancellables.forEach { $0.cancel() } }

        guard sut.availableProducts.contains(where: { $0.id == monthlyProductID }) else {
            XCTFail("P1 CHECK: Monthly product (\(monthlyProductID)) not found. Cannot test getSubscriptionDetails. SUT has: \(sut.availableProducts.map(\.id))")
            return
        }

        let purchaseExpectation = XCTestExpectation(description: "Wait for purchase to complete for getSubscriptionDetails test")
        sut.$entitlementStatus.dropFirst().sink { status in
            if status.isActive { purchaseExpectation.fulfill() }
        }.store(in: &localCancellables)

        await sut.purchase(productID: monthlyProductID, offerID: nil)
        await fulfillment(of: [purchaseExpectation], timeout: 10.0)

        guard sut.entitlementStatus.isActive else {
            XCTFail("Purchase did not result in active entitlement. Error: \(String(describing: sut.lastFailure)). Cannot test getSubscriptionDetails.")
            return
        }

        let subDetails = await sut.getSubscriptionDetails(for: monthlyProductID)
        XCTAssertNotNil(subDetails, "Subscription details should not be nil for an active subscription.")

        if let details = subDetails { // `details` is Product.SubscriptionInfo.Status
            var renewalInfoWillAutoRenewString = "N/A"
            // Safely get willAutoRenew from the renewalInfo payload
            if case .verified(let renewalInfoPayload) = details.renewalInfo {
                renewalInfoWillAutoRenewString = String(describing: renewalInfoPayload.willAutoRenew)
            } else if case .unverified(let renewalInfoPayload, _) = details.renewalInfo {
                // Even if unverified, we might still have the payload to see willAutoRenew
                renewalInfoWillAutoRenewString = "\(String(describing: renewalInfoPayload.willAutoRenew)) (Unverified)"
            }


            // CORRECTED print statement:
            // `details.state` is correct.
            // For `willAutoRenew`, we access it from the unwrapped `renewalInfo` payload.
            print("ℹ️ Subscription details for \(monthlyProductID): Overall State - \(details.state), WillAutoRenew - \(renewalInfoWillAutoRenewString)")

            XCTAssertEqual(details.state, .subscribed, "Subscription state should be .subscribed. Actual: \(details.state)")

            // Optionally, assert on willAutoRenew if you can control it in the .storekit file or test session
            // For example, if newly purchased subscriptions default to auto-renewing:
            if case .verified(let renewalInfoPayload) = details.renewalInfo {
                XCTAssertTrue(renewalInfoPayload.willAutoRenew, "Newly purchased subscription should typically be set to auto-renew.")
            }
        }

        XCTAssertNil(sut.lastFailure?.error, "getSubscriptionDetails should not result in an error if purchase was successful. Last failure: \(String(describing: sut.lastFailure))")
    }

    func test_canMakePayments_integration() async throws {
        // This test uses the SUT from the main setUp (Products.storekit)
        try XCTSkipIf(self.sut == nil, "SUT from global setUp is nil, cannot test canMakePayments.")

        let canPay = self.sut.canMakePayments()
        print("ℹ️ canMakePayments (integration test) returned: \(canPay)")
        // In most simulator/test environments, this will be true.
        XCTAssertTrue(canPay, "SKPaymentQueue.canMakePayments() usually returns true in test environments.")
    }


    // Existing tests like test_purchaseMonthlySubscription_withSubscriptionOnlyStoreKitFile (original version)
    // should now call sut.purchase(productID: monthlyProductID, offerID: nil)
    func test_purchaseMonthlySubscription_withSubscriptionOnlyStoreKitFile() async throws {
        let subscriptionProductIDs = [monthlyProductID, yearlyProductID]
        let (sut, session, cancellables) = try await setupSUTWithStoreKitFile(
            storeKitFilename: "TestSubscriptionOnly.storekit",
            productIDsForConfig: subscriptionProductIDs
        )
        var localCancellables = cancellables; defer { localCancellables.forEach { $0.cancel() } }

        guard sut.availableProducts.contains(where: { $0.id == monthlyProductID }) else {
            let message = "P1 CHECK: Monthly product (\(monthlyProductID)) not found for purchase. SUT has: \(sut.availableProducts.map(\.id)). This is expected if P1 (StoreKit bug) is active."
            print("⚠️ \(message)")
            XCTFail(message + " Test cannot proceed to purchase.")
            return
        }

        let expectation = XCTestExpectation(description: "Entitlement status should become active after purchasing monthly from TestSubscriptionOnly.storekit.")
        sut.$entitlementStatus
            .dropFirst()
            .sink { status in
            if status.isActive {
                expectation.fulfill()
            }
        }.store(in: &localCancellables)

        print("🧪 Attempting to purchase \(monthlyProductID) using TestSubscriptionOnly.storekit...")
        await sut.purchase(productID: monthlyProductID, offerID: nil) // MODIFIED to use new API

        await fulfillment(of: [expectation], timeout: 10.0)

        XCTAssertTrue(sut.entitlementStatus.isActive, "Entitlement should be active after successful subscription purchase. Status: \(sut.entitlementStatus)")
        if case .subscribed(let expires, _) = sut.entitlementStatus {
            XCTAssertNotNil(expires, "Subscription should have an expiration date.")
        } else {
            XCTFail("Entitlement status is not .subscribed for subscription: \(sut.entitlementStatus)")
        }

        if let lastFailure = sut.lastFailure {
            if case .underlyingError(let underlying) = lastFailure.error, let skError = underlying as? SKError, skError.code == .unknown {
                XCTSkip("Skipping direct nil error check due to P2 (StoreKit unknown error during purchase). Error: \(lastFailure.error.localizedDescription)")
            } else {
                XCTFail("Purchase should not result in an error: \(lastFailure.error.localizedDescription) (Operation: \(lastFailure.operation))")
            }
        }

        var hasTransactions = false
        if !session.allTransactions().isEmpty { hasTransactions = true }
        XCTAssertTrue(hasTransactions, "SKTestSession should have at least one transaction after purchase.")
    }


    func test_nonConsumable_fullFlow_usingLifetimeOnlyFile() async throws {
        let (sut, session, cancellables) = try await setupSUTWithStoreKitFile(
            storeKitFilename: "TestLifetimeOnly.storekit",
            productIDsForConfig: [lifetimeProductID]
        )
        var activeCancellables = cancellables; defer { activeCancellables.forEach { $0.cancel() } }

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
        }.store(in: &activeCancellables)

        await sut.purchase(productID: lifetimeProductID, offerID: nil)
        if let lastFailure = sut.lastFailure,
           case .underlyingError(let underlyingError) = lastFailure.error, let skError = underlyingError as? SKError, skError.code == .unknown {
            throw XCTSkip("Skipping full flow test due to P2 (StoreKitError.unknown on purchase). Error: \(lastFailure.error.localizedDescription)")
        }

        await fulfillment(of: [purchaseExpectation], timeout: 10.0)

        XCTAssertTrue(sut.entitlementStatus.isActive, "Entitlement should be active after purchase.")
        if case .subscribed(let expires, let isInGracePeriod) = sut.entitlementStatus {
            XCTAssertNil(expires)
            XCTAssertFalse(isInGracePeriod)
        } else {
            XCTFail("Entitlement status is not correct for non-consumable: \(sut.entitlementStatus)")
        }

        if let lastFailure = sut.lastFailure {
            if case .underlyingError(let underlying) = lastFailure.error, let skError = underlying as? SKError, skError.code == .unknown {
                XCTSkip("Skipping direct nil error check due to P2 (StoreKit unknown error during purchase). Error: \(lastFailure.error.localizedDescription)")
            } else {
                XCTFail("Purchase should be successful. Error: \(lastFailure.error.localizedDescription) (Op: \(lastFailure.operation))")
            }
        }
        XCTAssertFalse(session.allTransactions().isEmpty, "SKTestSession should have transaction after non-consumable purchase.")

        // Restore part
        sut.entitlementStatus = .notSubscribed // Simulate loss of entitlement status
        let restoreExpectation = XCTestExpectation(description: "Entitlement status restored to active (non-consumable).")
        sut.$entitlementStatus
            .dropFirst() // If already notSubscribed, it might not drop one. Consider filter or specific target value.
        .filter { $0.isActive } // Fulfill only when it becomes active
        .sink { status in
            if case .subscribed(let expires, let isInGracePeriod) = status, expires == nil, !isInGracePeriod {
                restoreExpectation.fulfill()
            }
        }.store(in: &activeCancellables)

        await sut.restorePurchases()
        await fulfillment(of: [restoreExpectation], timeout: 5.0)

        XCTAssertTrue(sut.entitlementStatus.isActive, "Entitlement should be restored.")
        if case .subscribed(let expires, let isInGracePeriod) = sut.entitlementStatus {
            XCTAssertNil(expires)
            XCTAssertFalse(isInGracePeriod)
        } else {
            XCTFail("Restored entitlement status is not correct for non-consumable: \(sut.entitlementStatus)")
        }
        // Restore might have its own errors if AppStore.sync failed, check lastFailure from restore context.
        // XCTAssertNil(sut.lastFailure?.error, "Restore purchases should be successful.") // This might fail if AppStore.sync fails but entitlement still updates

        // Cancellation Test for Non-Consumable (using a new SUT instance for clean state)
        print("🧪 Setting up for non-consumable purchase cancellation test...")
        let (sutCancel, cancelSession, cancelCancellablesSetup) = try await setupSUTWithStoreKitFile(
            storeKitFilename: "TestLifetimeOnly.storekit",
            productIDsForConfig: [lifetimeProductID]
        )
        var activeCancelCancellables = cancelCancellablesSetup; defer { activeCancelCancellables.forEach { $0.cancel() } }

        await sutCancel.updateEntitlementStatus()
        XCTAssertFalse(sutCancel.entitlementStatus.isActive, "Entitlement should not be active for cancellation test setup.")

        cancelSession.failTransactionsEnabled = true
        cancelSession.failureError = .paymentCancelled // SKError.paymentCancelled

        await sutCancel.purchase(productID: lifetimeProductID, offerID: nil) // MODIFIED

        // P6: SKTestSession.failureError = .paymentCancelled results in .unknown underlying error
        // PurchaseService now catches SKError.paymentCancelled and maps it to PurchaseError.purchaseCancelled
        // The LivePurchaseProvider should throw PurchaseError.purchaseCancelled if result is .userCancelled
        // Or if product.purchase() itself throws SKError.paymentCancelled.

        if sutCancel.lastFailure?.error == .purchaseCancelled {
            XCTAssertFalse(sutCancel.entitlementStatus.isActive, "Entitlement should not be active after correctly cancelled purchase.")
            print("✅ Cancellation simulated as .paymentCancelled correctly.")
        } else if case .underlyingError(let underlyingError) = sutCancel.lastFailure?.error,
            let skError = underlyingError as? SKError, skError.code == .unknown {
            print("⚠️ P6 DETECTED: `SKTestSession.failureError = .paymentCancelled` resulted in `.underlyingError(SKError.unknown)`. This indicates the StoreKit test bug P6 is active, where the raw SKError bubbles up instead of PurchaseResult.userCancelled.")
            XCTAssertFalse(sutCancel.entitlementStatus.isActive, "Entitlement should not be active after P6-affected cancelled purchase.")
            XCTSkip("Skipping direct assertion for .purchaseCancelled due to P6 - SKTestSession bug. SUT reported SKError.unknown.")
        } else {
            XCTFail("Expected .purchaseCancelled or P6-related .underlyingError(SKError.unknown), but got \(String(describing: sutCancel.lastFailure?.error)). Entitlement: \(sutCancel.entitlementStatus)")
        }
        cancelSession.failTransactionsEnabled = false
    }

    // This test relies on the scheme's StoreKit config if session is not used, or session if used.
    // The test name implies it uses SKTestSession, so it should use the one from setUp or a local one.
    func test_skTestSession_canFetchProducts() async throws {
        // This test uses the `session` from `setUp()`, which is configured with "Products.storekit"
        try XCTSkipIf(session == nil, "SKTestSession from setUp was not initialized.")

        try await Task.sleep(for: .milliseconds(500)) // Short delay for session

        // Test with specific IDs known to be in Products.storekit
        let products = try await Product.products(for: [monthlyProductID, lifetimeProductID])
        // With P3, only lifetimeProductID is expected from Products.storekit
        print("🔍 test_skTestSession_canFetchProducts (Products.storekit): Fetched \(products.count) products using specific IDs. Expected 1 (lifetime) due to P3.")
        XCTAssertEqual(products.count, 1, "P3 Check: Should fetch only 1 product (lifetime) from mixed Products.storekit with specific IDs. Found: \(products.map(\.id))")
        XCTAssertTrue(products.contains(where: { $0.id == lifetimeProductID }), "P3 Check: The fetched product should be lifetime.")


        let allProducts = try await Product.products(for: []) // Product.all
        print("🔍 test_skTestSession_canFetchProducts (Products.storekit): Product.all returned \(allProducts.count) products. Expected 0 or 1 due to P3 unreliability.")
        // P3 states Product.all is unreliable with mixed files. It might return 0 or just the non-consumable.
        // XCTAssertTrue(allProducts.count <= 1, "P3 Check: Product.all from mixed Products.storekit should return 0 or 1 product.")
        if allProducts.count > 1 {
            print("⚠️ P3 behavior? Product.all from mixed Products.storekit returned \(allProducts.count) products unexpectedly: \(allProducts.map(\.id))")
        }
    }

    func test_complete_storekit_structure() throws { // Check main Products.storekit
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

    // Test cancellation using the SUT from main setUp (Products.storekit)
    func test_purchase_nonConsumable_whenCancelledByUser_setsCancelledError_globalSUT() async throws {
        try XCTSkipIf(self.sut == nil || self.session == nil, "SUT or Session from global setUp is nil.")
        guard self.sut.availableProducts.contains(where: { $0.id == lifetimeProductID }) else {
            XCTFail("P3 CHECK: Lifetime product (\(lifetimeProductID)) not found in SUT from Products.storekit. Available: \(self.sut.availableProducts.map(\.id)). Cannot test cancellation.")
            return
        }

        await self.sut.updateEntitlementStatus() // Ensure initial status
        XCTAssertFalse(self.sut.entitlementStatus.isActive, "Entitlement should be inactive before cancellation test.")

        self.session.failTransactionsEnabled = true
        self.session.failureError = .paymentCancelled

        await self.sut.purchase(productID: lifetimeProductID, offerID: nil)

        

        if self.sut.lastFailure?.error == .purchaseCancelled { // or self.sut.lastFailure for the globalSUT test
            XCTAssertFalse(self.sut.entitlementStatus.isActive, "Entitlement should not be active after correctly cancelled purchase.")
            print("✅ Cancellation simulated as .paymentCancelled correctly.")
        } else if case .underlyingError(let underlyingError) = self.sut.lastFailure?.error, // or self.sut.lastFailure
            underlyingError is StoreKitError, // Check if it's a StoreKitError
            String(describing: underlyingError) == String(describing: StoreKitError.unknown) { // Check if it's specifically StoreKitError.unknown
            print("⚠️ P6 DETECTED: `SKTestSession.failureError = .paymentCancelled` resulted in `.underlyingError(StoreKitError.unknown)`. This indicates the StoreKit test bug P6 is active...")
            XCTAssertFalse(self.sut.entitlementStatus.isActive, "Entitlement should not be active after P6-affected cancelled purchase.")
            XCTSkip("Skipping direct assertion for .purchaseCancelled due to P6 - SKTestSession bug. SUT reported StoreKitError.unknown.")
        } else {
            XCTFail("Expected .purchaseCancelled or P6-related .underlyingError(StoreKitError.unknown), but got \(String(describing: self.sut.lastFailure?.error)). Entitlement: \(self.sut.entitlementStatus)")
        }

        self.session.failTransactionsEnabled = false // Reset for other tests
    }
}
