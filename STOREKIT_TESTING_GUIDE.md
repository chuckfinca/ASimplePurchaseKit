# StoreKit Testing Guide for ASimplePurchaseKitProject

This document outlines the strategy, known issues, and best practices for testing StoreKit interactions within the ASimplePurchaseKit project, especially when using Swift Package Manager (SPM).

## Current Status (As of June 2025, Xcode 16.x, iOS 17.x/18.x Simulators)

StoreKit testing in simulators, particularly for newer iOS versions (iOS 17.x, 18.x), can be unreliable due to bugs within Apple's StoreKit testing framework and simulator environment. Our test suite has been structured to identify and, where possible, work around these issues.

**Key Achievements:**
1.  **Reliable Resource Loading:** `.storekit` configuration files are correctly packaged into a nested resource bundle for the `PurchaseKitIntegrationTests` target (e.g., `ASimplePurchaseKitProject_PurchaseKitIntegrationTests.bundle`) and are loaded successfully from the root of this nested bundle in tests.
2.  **Diagnostic Suite:** `SPMStoreKitDiagnostics.swift` provides robust checks for bundle paths, resource loading, basic `SKTestSession` initialization, and JSON validation of `.storekit` files. It serves as the first point of debugging for environment-related StoreKit issues.
3.  **Identification of Known Simulator Bugs:** Our tests can now correctly reach the point where known StoreKit simulator bugs manifest.

## Known StoreKit Simulator Issues & Their Impact

These issues have been observed and are documented by the wider developer community (e.g., RevenueCat, StackOverflow, Apple Developer Forums). They primarily affect simulator environments for specific iOS versions.

*   **P1: Subscription Products Not Loading (iOS 17.x/18.x Simulators)**
    *   **Symptom:** `Product.products(for:)` calls for auto-renewable subscription product IDs return an empty array or an error, even if the `.storekit` file is correctly configured and loaded. Non-consumable products often load correctly from the same file or a different one.
    *   **Impact:** Tests relying on fetching or purchasing subscription products (e.g., `test_fetchSubscriptionProducts_withSubscriptionOnlyStoreKitFile`, `test_purchaseMonthlySubscription_...`) will fail on affected simulators because no products are found.
    *   **Status:** This is a known Apple bug. Our tests correctly identify this by failing with product not found errors or assertion failures on product counts.

*   **P2: Purchase/Transaction Flow Bugs (iOS 17.x/18.x Simulators)**
    *   **Symptom:** Even if a product (consumable, non-consumable, or sometimes subscription if P1 isn't hit) is fetched successfully, the `product.purchase()` call or subsequent transaction processing might fail with "unknown" errors, "Missing transaction data," or lead to inconsistent entitlement states.
    *   **Impact:** Tests like `test_nonConsumable_fullFlow_usingLifetimeOnlyFile` may fail during the purchase or entitlement validation phase due to these underlying simulator instabilities. Background "AMSStatusCode=400" errors from StoreKit's test server might also contribute to this.
    *   **Status:** This points to general instability in the simulator's StoreKit purchase processing.

*   **P3: Unreliable Product Loading with Mixed-Type `.storekit` Files or `Product.all` (iOS 17.x/18.x Simulators)**
    *   **Symptom:** When using a `.storekit` file containing both non-consumable and subscription products (like our main `Products.storekit`), fetching products using specific IDs might only return the non-consumable product. Using `Product.products(for: [])` (equivalent to `Product.all`) can be unreliable, sometimes returning 0 products or only non-consumables.
    *   **Impact:** Tests using `Products.storekit` (like the `setUp` for `PurchaseServiceIntegrationTests` or `test_skTestSession_canFetchProducts`) correctly observe this behavior, typically only loading the lifetime product.
    *   **Status:** This is a known StoreKit testing limitation/bug. Separating product types into different `.storekit` files for focused testing (e.g., `TestLifetimeOnly.storekit`, `TestSubscriptionOnly.storekit`) helps isolate this.

*   **P6: `SKTestSession.failureError = .paymentCancelled` Results in `.unknown` Error (iOS 17.x/18.x Simulators)**
    *   **Symptom:** When simulating a user-cancelled purchase by setting `session.failureError = .paymentCancelled`, the error received by `PurchaseService` is often a generic `.unknown` error (due to an underlying `AMSErrorDomain Code=305` or similar) instead of the expected `.purchaseCancelled`.
    *   **Impact:** Tests like `test_purchase_nonConsumable_whenCancelledByUser_setsCancelledError` detect this and use `XCTSkip` to acknowledge the P6 bug, preventing false negatives.
    *   **Status:** This is a known Apple bug in `SKTestSession`.

## Test Suite Structure & Strategy

1.  **`SPMStoreKitDiagnostics.swift`:**
    *   **Purpose:** Contains low-level checks for the testing environment. It should be the first place to run if `PurchaseServiceIntegrationTests` show widespread resource loading or session initialization failures.
    *   **Key Tests:**
        *   `test_A1_DebugResourceLoadingAndPaths`: Verifies the nested SPM resource bundle and the location of `.storekit` files within it. **Crucial for debugging file access.**
        *   `test_A2_ProgrammaticSKTestSession_ProductFetch`: Ensures an `SKTestSession` can be created with a found `.storekit` file and can fetch products (observing P1/P3).
        *   `test_A3_SchemeOrPlanBased_ProductFetch`: Checks if any StoreKit configuration is picked up by default (often not for SPM test plans, or might pick up one file like `Products.storekit`).
        *   `test_A5_ValidateStoreKitFileJSONStructure`: Validates the content of `Products.storekit`.

2.  **`PurchaseServiceIntegrationTests.swift`:**
    *   **Purpose:** Tests the `PurchaseService` logic against a live (but mocked by `SKTestSession`) StoreKit environment.
    *   **Resource Loading:** Uses helper functions (`getSPMTestResourceBundle`, `getStoreKitURLInSPMBundle`) derived from the successful logic in `SPMStoreKitDiagnostics.swift` to load `.storekit` files.
    *   **Specific `.storekit` Files:**
        *   `Products.storekit`: Contains a mix of non-consumable and subscription products. Used for general SUT setup and tests like `test_skTestSession_canFetchProducts`.
        *   `TestLifetimeOnly.storekit`: For focused testing of non-consumable product flows.
        *   `TestSubscriptionOnly.storekit`: For focused testing of subscription product flows (often impacted by P1).
    *   **Handling Simulator Bugs:**
        *   Tests affected by P1 (subscription loading) are expected to fail on problematic simulators and include "P1 CHECK" in their assertions or logs.
        *   Tests affected by P6 (cancellation error) use `XCTSkip` when P6 is detected.
        *   Tests like `test_nonConsumable_fullFlow_usingLifetimeOnlyFile` may be flaky due to P2 bugs; further investigation or simplification might be needed if they remain unstable.

## Running Tests Effectively

1.  **Clean Build Folder:** Before a test run, especially after code changes, perform a "Product > Clean Build Folder" in Xcode.
2.  **Simulator Choice:**
    *   For the most stable results (especially for subscriptions), try testing on an **older iOS simulator** (e.g., latest iOS 16.x if your deployment target allows, or an earlier stable iOS 17.x/18.x version not listed as problematic by community reports).
    *   **Physical devices** with Sandbox Apple IDs are the gold standard for validating StoreKit logic.
3.  **Interpreting Failures:**
    *   **File Not Found:** If tests in `PurchaseServiceIntegrationTests` fail to load `.storekit` files, first run `SPMStoreKitDiagnostics.swift` (especially `test_A1_DebugResourceLoadingAndPaths`) to verify resource paths. Ensure the helper functions in `PurchaseServiceIntegrationTests` match the successful logic from the diagnostics.
    *   **Subscription Tests Failing (0 products):** This is likely P1 if on an affected simulator.
    *   **Non-Consumable Purchase Flow Failing with "Unknown Error":** This might be P2. Check console logs for underlying errors from StoreKit.
    *   **Cancellation Test Skipped:** This is P6.
4.  **Test Plan Configuration:**
    *   SPM test targets typically do **not** allow setting a default "StoreKit Configuration" directly in the test plan UI options like traditional targets.
    *   Therefore, tests that need to simulate a scheme-level configuration (like `SPMStoreKitDiagnostics.test_A3_...`) might show 0 products or pick up one of the available `.storekit` files somewhat unpredictably.
    *   **Rely on programmatic `SKTestSession(contentsOf: url)` initialization within tests for deterministic behavior.**

## Future Improvements & Considerations

*   **Conditional Skipping for P1/P2:** Implement logic in `setUpWithError` or individual tests to detect problematic simulator OS versions and use `XCTSkipIf` to gracefully skip tests known to be affected by P1/P2, making CI results cleaner.
*   **Isolate `test_nonConsumable_fullFlow_usingLifetimeOnlyFile`:** If this test remains flaky, consider breaking it down further or using more focused assertions to pinpoint where the "unknown error" in the purchase flow originates.
*   **Monitor Apple's Fixes:** Keep an eye on Apple Developer release notes and community discussions for fixes to the StoreKit simulator bugs. Future Xcode/iOS versions should resolve these.
*   **Host App for Tests:** While `Bundle.main` might point to `xctest.tool`, ensure the `TestHostApp` is correctly set as the "Host Application" in the test scheme/plan settings if more complex app-dependent StoreKit features are tested. For current resource loading and basic session tests, the nested bundle approach is key.

This guide should help current and future developers understand the complexities of StoreKit testing in this project and provide a clear path for debugging and maintaining the test suite.