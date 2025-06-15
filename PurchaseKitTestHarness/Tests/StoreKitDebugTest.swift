import XCTest
import StoreKit
import StoreKitTest

/// Run this test in isolation to debug StoreKit configuration issues
@MainActor
final class StoreKitDebugTest: XCTestCase {

    func test_diagnoseStoreKitIssue_inPackage() async throws {
        print("\n🔍 STOREKIT DIAGNOSTIC TEST (PACKAGE FOCUS)")
        print("==================================================================")
        print("This test now relies *only* on the scheme's StoreKit Configuration.")
        print("No manual SKTestSession is created here.")

        // A very short pause might still be helpful for the mock server to spin up,
        // even with the scheme setting.
        let initialDelayMilliseconds: UInt64 = 500
        print("\n1️⃣ Pausing for \(initialDelayMilliseconds)ms for StoreKit to initialize...")
        try await Task.sleep(for: .milliseconds(initialDelayMilliseconds))
        print("  ✅ Pause complete.")

        // The ONLY thing we need to do is try to fetch products.
        // If the scheme configuration is working, this should succeed.
        print("\n2️⃣ Attempting to fetch products...")
        var fetchedProducts: [Product] = []
        let allProductIDsInFile = ["com.asimplepurchasekit.pro.lifetime", "com.asimplepurchasekit.pro.monthly", "com.asimplepurchasekit.pro.yearly"]

        do {
            fetchedProducts = try await Product.products(for: allProductIDsInFile)
            print("  📦 Fetched \(fetchedProducts.count) products using specific IDs.")
            for product in fetchedProducts {
                print("    🛒 \(product.id) - \(product.displayName) (\(product.displayPrice))")
            }
            XCTAssertFalse(fetchedProducts.isEmpty, "Product.products(for:) should return products when the scheme is configured with a .storekit file.")

        } catch {
            XCTFail("❌ Error fetching products: \(error)")
        }

        print("\n" + "=======================================================")
        print("DIAGNOSTIC COMPLETE")
    }
}
