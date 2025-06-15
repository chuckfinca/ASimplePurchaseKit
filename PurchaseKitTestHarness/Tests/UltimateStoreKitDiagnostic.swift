//
//  UltimateStoreKitDiagnostic.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/15/25.
//

import XCTest
import StoreKit
import StoreKitTest

@MainActor
final class UltimateStoreKitDiagnostic: XCTestCase {
    
    func test_completeSystemDiagnosis() async throws {
        print("\n🔬 ULTIMATE STOREKIT DIAGNOSTIC")
        print("=" * 80)
        
        // 1. Bundle Configuration
        print("\n1️⃣ BUNDLE CONFIGURATION:")
        let mainBundle = Bundle.main
        let testBundle = Bundle(for: type(of: self))
        
        print("   Main Bundle ID: '\(mainBundle.bundleIdentifier ?? "NIL")'")
        print("   Test Bundle ID: '\(testBundle.bundleIdentifier ?? "NIL")'")
        
        // Check for leading dots
        if let mainID = mainBundle.bundleIdentifier, mainID.hasPrefix(".") {
            print("   ❌ CRITICAL: Main bundle ID starts with dot!")
        }
        if let testID = testBundle.bundleIdentifier, testID.hasPrefix(".") {
            print("   ❌ CRITICAL: Test bundle ID starts with dot!")
        }
        
        // Check Info.plist directly
        print("\n   Info.plist values:")
        if let mainInfo = mainBundle.infoDictionary {
            print("   Main CFBundleIdentifier: '\(mainInfo["CFBundleIdentifier"] ?? "NIL")'")
        }
        if let testInfo = testBundle.infoDictionary {
            print("   Test CFBundleIdentifier: '\(testInfo["CFBundleIdentifier"] ?? "NIL")'")
        }
        
        // 2. Environment Variables
        print("\n2️⃣ ENVIRONMENT VARIABLES:")
        let env = ProcessInfo.processInfo.environment
        let relevantKeys = ["PRODUCT_BUNDLE_IDENTIFIER", "TEST_HOST", "BUNDLE_LOADER",
                           "bundleIdPrefix", "STOREKIT_CONFIG", "XCTestConfigurationFilePath"]
        
        for key in relevantKeys {
            if let value = env[key] {
                print("   \(key): '\(value)'")
            }
        }
        
        // 3. StoreKit Configuration File
        print("\n3️⃣ STOREKIT CONFIGURATION:")
        
        // Check multiple locations
        let locations = [
            testBundle.url(forResource: "Products", withExtension: "storekit"),
            mainBundle.url(forResource: "Products", withExtension: "storekit"),
            testBundle.url(forResource: "Products", withExtension: "storekit", subdirectory: "Tests"),
        ]
        
        var foundConfig = false
        for (index, url) in locations.enumerated() {
            if let url = url, FileManager.default.fileExists(atPath: url.path) {
                print("   ✅ Found at location \(index): \(url.lastPathComponent)")
                foundConfig = true
                
                // Validate contents
                if let data = try? Data(contentsOf: url),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let products = (json["products"] as? [[String: Any]] ?? [])
                    print("   ✅ Valid JSON with \(products.count) products")
                    
                    // List product IDs
                    for product in products {
                        if let id = product["productID"] as? String {
                            print("      • \(id)")
                        }
                    }
                }
                break
            }
        }
        
        if !foundConfig {
            print("   ❌ No Products.storekit file found!")
        }
        
        // 4. StoreKit Availability
        print("\n4️⃣ STOREKIT AVAILABILITY:")
        
        // Test 1: Can we create SKTestSession?
        if let configURL = testBundle.url(forResource: "Products", withExtension: "storekit") {
            do {
                let session = try SKTestSession(contentsOf: configURL)
                print("   ✅ SKTestSession can be created")
                session.clearTransactions()
            } catch {
                print("   ❌ Cannot create SKTestSession: \(error)")
            }
        }
        
        // Test 2: Direct Product fetch (no session)
        print("\n5️⃣ DIRECT PRODUCT FETCH (no SKTestSession):")
        try await Task.sleep(for: .seconds(1))
        
        do {
            let allProducts = try await Product.products(for: [])
            print("   Products found: \(allProducts.count)")
            
            if allProducts.isEmpty {
                print("   ❌ No products returned by Product.products(for: [])")
            } else {
                for product in allProducts {
                    print("   ✅ \(product.id): \(product.displayName)")
                }
            }
        } catch {
            print("   ❌ Error fetching products: \(error)")
        }
        
        // 6. Try with explicit product IDs
        print("\n6️⃣ FETCH WITH EXPLICIT IDs:")
        let explicitIDs = [
            "com.asimplepurchasekit.pro.lifetime",
            "com.asimplepurchasekit.pro.monthly",
            "com.asimplepurchasekit.pro.yearly"
        ]
        
        do {
            let products = try await Product.products(for: explicitIDs)
            print("   Products found: \(products.count)")
        } catch {
            print("   ❌ Error: \(error)")
        }
        
        // 7. System Information
        print("\n7️⃣ SYSTEM INFORMATION:")
        print("   Xcode: \(env["XCODE_PRODUCT_BUILD_VERSION"] ?? "Unknown")")
        print("   SDK: \(env["SDK_NAME"] ?? "Unknown")")
        print("   Platform: \(env["PLATFORM_NAME"] ?? "Unknown")")
        
        print("\n" + "=" * 80)
        print("DIAGNOSTIC COMPLETE")
        print("=" * 80)
        
        // Final verdict
        if let mainID = mainBundle.bundleIdentifier,
           let testID = testBundle.bundleIdentifier {
            if mainID.hasPrefix(".") || testID.hasPrefix(".") {
                print("\n🚨 VERDICT: Bundle IDs are malformed (start with dot)")
                print("   FIX: Hardcode bundle IDs in project.yml")
            } else if !testID.hasPrefix(mainID + ".") {
                print("\n🚨 VERDICT: Test bundle ID is not a child of main bundle ID")
                print("   FIX: Test bundle should be \(mainID).Tests")
            } else {
                print("\n🤔 VERDICT: Bundle IDs look correct, issue is elsewhere")
                print("   TRY: Remove all StoreKit configuration and start fresh")
            }
        }
    }
}
