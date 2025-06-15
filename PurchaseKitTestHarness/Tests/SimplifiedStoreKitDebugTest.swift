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
        
        // NO SKTestSession creation - rely entirely on scheme config
        
        // Give StoreKit time to initialize
        for delay in [500, 1000, 2000, 3000] {
            print("\n⏱️  Waiting \(delay)ms...")
            try await Task.sleep(for: .milliseconds(UInt64(delay)))
            
            let products = try await Product.products(for: [])
            print("   Products found: \(products.count)")
            
            if !products.isEmpty {
                print("   ✅ Success! Products loaded after \(delay)ms")
                for product in products {
                    print("      • \(product.id)")
                }
                return
            }
        }
        
        XCTFail("❌ No products found even after waiting")
    }
    
    func test_programmaticSession_only() async throws {
        print("\n🧪 TEST 2: Using ONLY programmatic SKTestSession")
        print("=" * 70)
        
        // Find the .storekit file
        let bundle = Bundle(for: type(of: self))
        
        // Try multiple possible locations
        let possiblePaths = [
            bundle.url(forResource: "Products", withExtension: "storekit"),
            bundle.url(forResource: "Products", withExtension: "storekit", subdirectory: "Tests"),
            bundle.url(forResource: "Products", withExtension: "storekit", subdirectory: "PurchaseKitTestHarness/Tests"),
        ]
        
        var configURL: URL? = nil
        for path in possiblePaths {
            if let path = path {
                print("   Checking: \(path.lastPathComponent) at \(path.path)")
                if FileManager.default.fileExists(atPath: path.path) {
                    configURL = path
                    print("   ✅ Found!")
                    break
                }
            }
        }
        
        guard let url = configURL else {
            // List all resources in bundle for debugging
            print("\n📦 All resources in test bundle:")
            if let resourceURLs = bundle.urls(forResourcesWithExtension: nil, subdirectory: nil) {
                for resourceURL in resourceURLs {
                    print("   • \(resourceURL.lastPathComponent)")
                }
            }
            XCTFail("❌ Could not find Products.storekit in test bundle")
            return
        }
        
        // Create session with the found URL
        let session = try SKTestSession(contentsOf: url)
        
        // Minimal configuration
        session.clearTransactions()
        
        // Test with increasing delays
        for delay in [500, 1000, 2000, 3000] {
            print("\n⏱️  Waiting \(delay)ms after session creation...")
            try await Task.sleep(for: .milliseconds(UInt64(delay)))
            
            // Try fetching products
            let products = try await Product.products(for: [
                "com.asimplepurchasekit.pro.lifetime",
                "com.asimplepurchasekit.pro.monthly",
                "com.asimplepurchasekit.pro.yearly"
            ])
            
            print("   Products found: \(products.count)")
            
            if !products.isEmpty {
                print("   ✅ Success! Products loaded after \(delay)ms")
                return
            }
        }
        
        XCTFail("❌ No products found even after waiting")
    }
    
    func test_validateBundleResources() throws {
        print("\n🔍 VALIDATING BUNDLE RESOURCES")
        print("=" * 70)
        
        let bundle = Bundle(for: type(of: self))
        
        print("Test bundle path: \(bundle.bundlePath)")
        print("\nSearching for .storekit files...")
        
        // Method 1: Direct resource lookup
        if let urls = bundle.urls(forResourcesWithExtension: "storekit", subdirectory: nil) {
            print("\nFound \(urls.count) .storekit files:")
            for url in urls {
                print("  • \(url.lastPathComponent) at: \(url.path)")
                
                // Validate the file can be read
                if let data = try? Data(contentsOf: url),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("    ✅ Valid JSON with \((json["products"] as? [Any])?.count ?? 0) products")
                }
            }
        }
        
        // Method 2: File system enumeration
        print("\nAll bundle contents:")
        let enumerator = FileManager.default.enumerator(atPath: bundle.bundlePath)
        while let file = enumerator?.nextObject() as? String {
            if file.hasSuffix(".storekit") {
                print("  📄 Found via enumeration: \(file)")
            }
        }
    }
}
