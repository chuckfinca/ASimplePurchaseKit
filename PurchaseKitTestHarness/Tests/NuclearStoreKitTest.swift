//
//  NuclearStoreKitTest.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/15/25.
//

import XCTest
import StoreKit

final class NuclearStoreKitTest: XCTestCase {
    
    func test_absoluteMinimal_noConfigAtAll() async throws {
        print("\n🔥 NUCLEAR TEST: Absolute Minimal")
        print("=" * 60)
        
        // NO SKTestSession
        // NO scheme configuration
        // Just raw StoreKit
        
        print("Bundle IDs:")
        print("  Main: \(Bundle.main.bundleIdentifier ?? "nil")")
        print("  Test: \(Bundle(for: type(of: self)).bundleIdentifier ?? "nil")")
        
        // Wait
        print("\nWaiting 3 seconds...")
        try await Task.sleep(for: .seconds(3))
        
        // Try to fetch ANY products at all
        print("\nAttempting Product.products(for: [])...")
        do {
            let products = try await Product.products(for: [])
            print("Result: \(products.count) products")
            
            if products.isEmpty {
                print("\n❌ STILL NO PRODUCTS")
                
                // Try Product.all extension
                print("\nTrying Product.all...")
                let all = try await Product.all
                print("Result: \(all.count) products")
                
                // Try with explicit IDs
                print("\nTrying explicit IDs...")
                let explicit = try await Product.products(for: [
                    "com.asimplepurchasekit.pro.lifetime",
                    "com.asimplepurchasekit.pro.monthly",
                    "com.asimplepurchasekit.pro.yearly"
                ])
                print("Result: \(explicit.count) products")
                
                // Try variations
                print("\nTrying ID variations...")
                let variations = [
                    ["pro.lifetime", "pro.monthly", "pro.yearly"],
                    ["lifetime", "monthly", "yearly"],
                    ["com.example.product"],
                    ["test.product"]
                ]
                
                for (index, ids) in variations.enumerated() {
                    let result = try await Product.products(for: ids)
                    print("  Variation \(index + 1): \(result.count) products")
                }
                
            } else {
                print("\n✅ SUCCESS! Found products:")
                for product in products {
                    print("  - \(product.id)")
                }
            }
        } catch {
            print("❌ ERROR: \(error)")
        }
        
        print("\n" + "=" * 60)
    }
    
    func test_checkStoreKitAvailability() {
        print("\n🔍 STOREKIT AVAILABILITY CHECK")
        print("=" * 60)
        
        // Check if we're in a test environment
        let env = ProcessInfo.processInfo.environment
        
        print("Environment checks:")
        print("  XCTest present: \(NSClassFromString("XCTest") != nil)")
        print("  Test config: \(env["XCTestConfigurationFilePath"] != nil)")
        print("  UI test: \(env["XCTestBundlePath"] != nil)")
        
        // Check for StoreKit-related environment variables
        print("\nStoreKit environment:")
        for (key, value) in env where key.contains("STORE") || key.contains("SK") {
            print("  \(key): \(value)")
        }
        
        // Check if StoreKit classes are available
        print("\nStoreKit classes:")
        print("  Product: \(NSClassFromString("StoreKit.Product") != nil)")
        print("  Transaction: \(NSClassFromString("StoreKit.Transaction") != nil)")
        print("  SKTestSession: \(NSClassFromString("StoreKitTest.SKTestSession") != nil)")
        
        print("\n" + "=" * 60)
    }
}
