# StoreKit Testing Guide for ASimplePurchaseKit

This document outlines the strategy, known issues, and best practices for testing StoreKit interactions within the ASimplePurchaseKit project, especially when using Swift Package Manager (SPM).

## Current Status (As of June 2025, Xcode 16.x, iOS 17.x/18.x Simulators)

StoreKit testing in simulators, particularly for newer iOS versions (iOS 17.x, 18.x), can be unreliable due to bugs within Apple's StoreKit testing framework and simulator environment. Our test suite has been structured to identify and, where possible, work around these issues.

**Key Achievements:**
1.  **Reliable Resource Loading:** `.storekit` configuration files are correctly packaged into a nested resource bundle for the `IntegrationTests` target (e.g., `ASimplePurchaseKit_IntegrationTests.bundle`) and are loaded successfully from the root of this nested bundle in tests.
2.  **Diagnostic Suite:** `SPMStoreKitDiagnostics.swift` provides robust checks for bundle paths, resource loading, basic `SKTestSession` initialization, and JSON validation of `.storekit` files. It serves as the first point of debugging for environment-related StoreKit issues.
3.  **Identification of Known Simulator Bugs:** Our tests can now correctly reach the point where known StoreKit simulator bugs manifest, and the test suite correctly fails or skips in response to these known issues.

## Known StoreKit Simulator Issues & Their Impact

These issues have been observed and are documented by the wider developer community (e.g., RevenueCat, StackOverflow, Apple Developer Forums). They primarily affect simulator environments for specific iOS versions.

*   **P1: Subscription Products Not Loading (iOS 17.x/18.x Simulators)**
    *   **Symptom:** `Product.products(for:)` calls for auto-renewable subscription product IDs return an empty array or an error, even if the `.storekit` file is correctly configured and loaded. Non-consumable products often load correctly from the same file or a different one.
    *   **Impact:** Tests relying on fetching or purchasing subscription products (e.g., `test_fetchSubscriptionProducts_withSubscriptionOnlyStoreKitFile`, `test_purchaseMonthlySubscription_...`, `test_purchaseSubscription_withIntroductoryOffer`) will fail on affected simulators because no products are found. Our tests include "P1 CHECK" in their assertions/logs and correctly fail when this occurs.
    *   **Status:** This is a known Apple bug.

*   **P2: Purchase/Transaction Flow Bugs (iOS 17.x/18.x Simulators)**
    *   **Symptom:** Even if a product (consumable, non-consumable, or sometimes subscription if P1 isn't hit) is fetched successfully, the `product.purchase()` call or subsequent transaction processing might fail with "unknown" `StoreKitError`s, "Missing transaction data," or lead to inconsistent entitlement states. Background "AMSStatusCode=400" errors from StoreKit's test server (see "Environment Instability" below) might also contribute to this.
    *   **Impact:** Tests like `test_nonConsumable_fullFlow_usingLifetimeOnlyFile` may fail during the purchase or entitlement validation phase due to these underlying simulator instabilities. The test attempts to purchase a non-consumable, but `product.purchase()` can throw an `.unknown` `StoreKitError`.
    *   **Status:** This points to general instability in the simulator's StoreKit purchase processing. Consider using `XCTSkipIf` in tests if this error consistently blocks valid test paths, or break down very long "full flow" tests.

*   **P3: Unreliable Product Loading with Mixed-Type `.storekit` Files or `Product.all` (iOS 17.x/18.x Simulators)**
    *   **Symptom:** When using a `.storekit` file containing both non-consumable and subscription products (like our main `Products.storekit`), fetching products using specific IDs might only return the non-consumable product. Using `Product.products(for: [])` (equivalent to `Product.all`) can be unreliable, sometimes returning 0 products or only non-consumables.
    *   **Impact:** Tests using `Products.storekit` (like the `setUp` for `PurchaseServiceIntegrationTests` or `test_skTestSession_canFetchProducts`) correctly observe this behavior, typically only loading the lifetime product.
    *   **Status:** This is a known StoreKit testing limitation/bug. Separating product types into different `.storekit` files for focused testing (e.g., `TestLifetimeOnly.storekit`, `TestSubscriptionOnly.storekit`) helps isolate this.

*   **P4: Promotional Offer `id` Availability & Testing (iOS 17.4+)**
    *   **Symptom:** The `Product.SubscriptionOffer.id` property, crucial for uniquely identifying specific promotional offers, is only available on iOS 17.4+, macOS 14.4+, etc.
    *   **Impact:**
        *   When testing `purchase(productID:offerID:)` on OS versions **older than iOS 17.4**, `LivePurchaseProvider` cannot match offers by this `id`.
        *   On **iOS 17.4+**, matching by `id` should work, provided the `id` is correctly defined in the `.storekit` file (like in `TestSubscriptionWithIntroOffer.storekit`).
    *   **Status:** An OS version dependency. Test specific offer ID purchases on iOS 17.4+ simulators/devices.

*   **P6: `SKTestSession.failureError = .paymentCancelled` Results in `.unknown` Error (iOS 17.x/18.x Simulators)**
    *   **Symptom:** When `session.failureError = .paymentCancelled` is set to simulate user cancellation, the error often received by `PurchaseService` is a generic `.unknown` `StoreKitError` (due to an underlying `AMSErrorDomain Code=305` or `ASDErrorDomain Code=9999 "Received failure in response from Xcode"`) instead of the expected `.purchaseCancelled`.
    *   **Impact:** Tests like `test_purchase_nonConsumable_whenCancelledByUser_setsCancelledError_globalSUT` detect this and use `XCTSkip` to acknowledge the P6 bug, preventing false negatives.
    *   **Status:** This is a known Apple bug in `SKTestSession`'s error reporting for cancellations.

*   **P7: Xcode 16.4 SDK Regression with `Product.PurchaseOption` for Offers**
    *   **Symptom:** The Xcode 16.4 SDK (and potentially early Xcode 17 betas if not fixed) has a regression where `Product.PurchaseOption.promotionalOffer(offer:signature:)` and `Product.PurchaseOption.introductory` are not usable (compiler errors or unavailability).
    *   **Impact:** `ASimplePurchaseKit`'s `LivePurchaseProvider` cannot programmatically apply a *specific chosen* client-side promotional offer using these `PurchaseOption` cases. It logs this limitation and proceeds with a standard purchase call. StoreKit *may* still apply a default introductory offer if the user is eligible.
    *   **Status:** An SDK-level issue. Tests for purchasing specific offers cannot currently verify the *application* of the specific offer via `options`, only that the purchase flow was attempted with the offer ID. Monitor Apple SDK updates (Xcode 16.5+, Xcode 17) for fixes.

*   **NEW: Environment Instability - AMS/ASD Errors (Simulators)**
    *   **Symptom:** Test logs frequently show errors like `Error Domain=ASDErrorDomain Code=500` or `Error Domain=AMSErrorDomain Code=301 "Invalid Status Code" (AMSStatusCode=400)`. These often appear during `SKTestSession` initialization, transaction enumeration (`Transaction.all`, `Transaction.currentEntitlements`), or when the StoreKit test daemon communicates with its local mock server (`http://localhost:xxxx/inApps/history`).
    *   **Impact:** These indicate instability or issues within the StoreKit test environment's backend simulator. They can contribute to general test flakiness, product loading failures (P1), and purchase flow issues (P2).
    *   **Status:** These are generally outside direct developer control. They are symptoms of the simulator's StoreKit environment flakiness. Retrying tests or testing on physical devices can sometimes mitigate.

## Test Suite Structure & Strategy

1.  **`SPMStoreKitDiagnostics.swift`:**
    *   **Purpose:** Low-level checks for the testing environment. Run first if `PurchaseServiceIntegrationTests` show widespread resource loading or session initialization failures.
    *   **Key Tests:**
        *   `test_A1_DebugResourceLoadingAndPaths`: Verifies nested SPM resource bundle and `.storekit` file locations.
        *   `test_A2_ProgrammaticSKTestSession_ProductFetch`: Ensures `SKTestSession` creation and product fetching (observing P1/P3).
        *   `test_A3_SchemeOrPlanBased_ProductFetch`: Checks default StoreKit configuration pickup.
        *   `test_A5_ValidateStoreKitFileJSONStructure`: Validates `.storekit` file content.

2.  **`PurchaseServiceIntegrationTests.swift`:**
    *   **Purpose:** Tests `PurchaseService` logic against a live (mocked by `SKTestSession`) StoreKit environment.
    *   **Resource Loading:** Uses robust helper functions to load `.storekit` files.
    *   **Specific `.storekit` Files:**
        *   `Products.storekit`: Mixed non-consumable and subscription products.
        *   `TestLifetimeOnly.storekit`: Focused non-consumable testing.
        *   `TestSubscriptionOnly.storekit`: Focused subscription testing (often hit by P1).
        *   `TestSubscriptionWithIntroOffer.storekit`: For promotional offer fetching/purchasing (hit by P1, P4 considerations, P7 impact).
    *   **Handling Simulator Bugs:**
        *   Tests affected by P1 (subscription loading) correctly fail with "P1 CHECK" messages.
        *   Tests affected by P2 (purchase flow instability) may fail; consider `XCTSkipIf` for consistently problematic `StoreKitError.unknown` on purchase.
        *   Tests affected by P6 (cancellation error) use `XCTSkip` when P6 is detected.
        *   Promotional offer tests acknowledge P7 limitations.

## Running Tests Effectively

1.  **Clean Build Folder:** Before a test run, "Product > Clean Build Folder" in Xcode.
2.  **Simulator Choice:**
    *   For best results with subscriptions and promotional offers (ID matching), try **iOS 17.4+ simulators**.
    *   Be aware that even these may exhibit P1, P2, P6, P7, and AMS/ASD errors.
    *   **Physical devices** with Sandbox Apple IDs remain the gold standard.
3.  **Interpreting Failures:**
    *   **File Not Found:** Run `SPMStoreKitDiagnostics.swift` first.
    *   **Subscription Tests Failing (0 products):** Likely P1.
    *   **Promotional Offer by ID purchase issues:** Check P4 (OS version) and P7 (SDK limitations).
    *   **Purchase Flow Failing with "Unknown Error" or AMS/ASD errors:** Likely P2 or general environment instability.
    *   **Cancellation Test Skipped or Failing Unexpectedly:** P6 or P2 interaction.
4.  **Test Plan Configuration:** Rely on programmatic `SKTestSession(contentsOf: url)` initialization within tests for deterministic behavior.

## ⚠️ Xcode 17+ Re-evaluation Needed

**Once Xcode 17 is released (or during its beta cycle), this entire guide and all StoreKit-related tests and workarounds (especially for P1, P2, P3, P4, P6, P7, and AMS/ASD error prevalence) must be re-evaluated.**
Apple may have fixed existing simulator bugs or introduced new behaviors.
Refer to GitHub Issue #[YourIssueNumberForXcode17Retest] for tracking.
Search the codebase for `XCODE17_RETEST` tags.

## Future Improvements & Considerations

*   **Conditional Skipping for P1/P2:** Implement more robust logic (e.g., based on OS version if correlations are strong) to use `XCTSkipIf` for tests known to be affected by P1/P2, making CI results cleaner if desired.
*   **Isolate Flaky Tests:** If tests like `test_nonConsumable_fullFlow_usingLifetimeOnlyFile` remain very flaky due to P2, consider breaking them into smaller, more targeted tests or increasing their P2-specific skip conditions.
*   **Monitor Apple's Fixes:** Keep an eye on Apple Developer release notes and community discussions.

This guide should help current and future developers understand the complexities of StoreKit testing in this project and provide a clear path for debugging and maintaining the test suite.
