//
//  SimplifiedStoreKitDebugTest.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/15/25.
//

import XCTest
import StoreKit
import StoreKitTest

@MainActor
final class SimplifiedStoreKitDebugTest: XCTestCase {
    
    func test_schemeConfiguration_only() async throws {
        print("\n🧪 TEST 1: Using ONLY scheme configuration (no SKTestSession)")
        print("=" * 70)
        
        var productsFound = false
        // Test with explicit IDs first, as this sometimes works with scheme-only
        let explicitIDs = [
            "com.asimplepurchasekit.pro.lifetime",
            "com.asimplepurchasekit.pro.monthly", // Will likely not load
            "com.asimplepurchasekit.pro.yearly"   // Will likely not load
        ]

        for delay in [500, 1000, 2000, 3000] {
            print("\n⏱️  Waiting \(delay)ms...")
            try await Task.sleep(for: .milliseconds(UInt64(delay)))
            
            // Try with explicit IDs
            let explicitProducts = try await Product.products(for: explicitIDs)
            print("   Products found (explicit IDs): \(explicitProducts.count)")
            if !explicitProducts.isEmpty {
                print("   ✅ Success with explicit IDs! Products loaded after \(delay)ms")
                for product in explicitProducts { print("      • \(product.id)") }
                productsFound = true
                break // Exit loop if any products found this way
            }

            // If explicit IDs didn't work, try Product.all (less likely to work scheme-only)
            // Only attempt Product.all if explicit IDs failed, to avoid masking the explicit ID success.
            if !productsFound {
                let allProducts = try await Product.products(for: []) // Product.all
                print("   Products found (Product.all): \(allProducts.count)")
                if !allProducts.isEmpty {
                    print("   ✅ Success with Product.all! Products loaded after \(delay)ms")
                    for product in allProducts { print("      • \(product.id)") }
                    productsFound = true
                    break
                }
            }
        }
        
        XCTAssertTrue(productsFound, "❌ No products found even after waiting (scheme-only config). Check if lifetime loads with explicit IDs, or if Product.all yields results.")
    }
    
    func test_programmaticSession_only() async throws {
        print("\n🧪 TEST 2: Using ONLY programmatic SKTestSession")
        print("=" * 70)
        
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "Products", withExtension: "storekit") else {
            XCTFail("❌ Could not find Products.storekit in test bundle")
            return
        }
        print("   Using Products.storekit at \(url.path)")
        
        let session = try SKTestSession(contentsOf: url)
        session.clearTransactions()
        
        var productsFoundCount = 0
        let idsToTest = [
            "com.asimplepurchasekit.pro.lifetime",
            "com.asimplepurchasekit.pro.monthly",
            "com.asimplepurchasekit.pro.yearly"
        ]

        for delay in [500, 1000, 2000, 3000] {
            print("\n⏱️  Waiting \(delay)ms after session creation...")
            try await Task.sleep(for: .milliseconds(UInt64(delay)))
            
            let products = try await Product.products(for: idsToTest)
            print("   Products found: \(products.count)")
            productsFoundCount = products.count
            
            if products.count == 1 && products.first?.id == "com.asimplepurchasekit.pro.lifetime" {
                print("   ✅ Success (P3 behavior)! Lifetime product loaded after \(delay)ms")
                XCTAssertEqual(productsFoundCount, 1, "Expected 1 product (lifetime) from Products.storekit due to P3.")
                return
            } else if products.count > 0 {
                print("   ⚠️ Found \(products.count) products from Products.storekit. P3 behavior might be different or file changed/fixed. Products: \(products.map(\.id))")
                return
            }
        }
        XCTFail("❌ No products found from Products.storekit even after waiting with SKTestSession. Expected at least lifetime (P3). Actual: \(productsFoundCount)")
    }
    
    func test_validateBundleResources() throws {
        print("\n🔍 VALIDATING BUNDLE RESOURCES")
        print("=" * 70)
        
        let bundle = Bundle(for: type(of: self))
        
        print("Test bundle path: \(bundle.bundlePath)")
        print("\nSearching for .storekit files...")
        
        let storekitFiles = bundle.urls(forResourcesWithExtension: "storekit", subdirectory: nil) ?? []
        XCTAssertFalse(storekitFiles.isEmpty, "Should find .storekit files in test bundle resources.")
        print("\nFound \(storekitFiles.count) .storekit files:")

        for url in storekitFiles {
            print("  Validating: \(url.lastPathComponent) at: \(url.path)")
            
            var fileData: Data?
            do {
                fileData = try Data(contentsOf: url)
            } catch {
                XCTFail("Failed to read data for \(url.lastPathComponent): \(error)")
                continue
            }
            
            guard let data = fileData else {
                XCTFail("Data was nil after attempting to read \(url.lastPathComponent)")
                continue
            }

            var jsonObject: Any?
            do {
                jsonObject = try JSONSerialization.jsonObject(with: data)
            } catch {
                 XCTFail("Failed to parse JSON for \(url.lastPathComponent): \(error). File content (first 500 chars): \(String(data: data.prefix(500), encoding: .utf8) ?? "Unable to decode as UTF-8")")
                continue
            }
            
            guard let json = jsonObject as? [String: Any] else {
                XCTFail("Parsed JSON for \(url.lastPathComponent) was not a [String: Any] dictionary.")
                continue
            }

            let topLevelProducts = (json["products"] as? [[String: Any]]) ?? []
            var subscriptionProductCount = 0
            if let groups = json["subscriptionGroups"] as? [[String: Any]] {
                for group in groups {
                    subscriptionProductCount += (group["subscriptions"] as? [[String: Any]] ?? []).count
                }
            }
            
            print("    Successfully parsed. Top-level products: \(topLevelProducts.count), Subscription products: \(subscriptionProductCount)")

            if url.lastPathComponent == "TestSubscriptionOnly.storekit" {
                XCTAssertTrue(topLevelProducts.isEmpty, "\(url.lastPathComponent) should have 0 top-level products.")
                XCTAssertGreaterThan(subscriptionProductCount, 0, "\(url.lastPathComponent) should have subscription products.")
            } else if url.lastPathComponent == "TestLifetimeOnly.storekit" {
                XCTAssertFalse(topLevelProducts.isEmpty, "\(url.lastPathComponent) should have top-level products.")
                XCTAssertEqual(subscriptionProductCount, 0, "\(url.lastPathComponent) should have 0 subscription products.")
            } else if url.lastPathComponent == "Products.storekit" { // Mixed
                 XCTAssertFalse(topLevelProducts.isEmpty, "\(url.lastPathComponent) should have top-level products.")
                 XCTAssertGreaterThan(subscriptionProductCount, 0, "\(url.lastPathComponent) should have subscription products.")
            } else if url.lastPathComponent == "TestMinimalSubscription.storekit" {
                 XCTAssertTrue(topLevelProducts.isEmpty, "\(url.lastPathComponent) should have 0 top-level products.")
                 XCTAssertGreaterThan(subscriptionProductCount, 0, "\(url.lastPathComponent) should have at least one subscription product.")
            }
        }
        
        print("\nAll bundle contents (listing .storekit files via enumerator):")
        let enumerator = FileManager.default.enumerator(atPath: bundle.bundlePath)
        var foundViaEnum = 0
        while let file = enumerator?.nextObject() as? String {
            if file.hasSuffix(".storekit") {
                print("  📄 Found via enumeration: \(file)")
                foundViaEnum += 1
            }
        }
        XCTAssertEqual(foundViaEnum, storekitFiles.count, "Enumerator count should match direct lookup count for .storekit files.")
    }
}
