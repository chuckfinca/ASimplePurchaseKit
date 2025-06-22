//
//  BundleIDDiagnosticTest.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/15/25.
//

import XCTest

final class BundleIDDiagnosticTest: XCTestCase {
    
    func test_printBundleIdentifiers() {
        print("\n🔍 BUNDLE IDENTIFIER DIAGNOSTIC")
        print("=" * 50)
        
        // Main app bundle
        if let mainBundle = Bundle.main.bundleIdentifier {
            print("Main App Bundle ID: \(mainBundle)")
        } else {
            print("Main App Bundle ID: NOT FOUND")
        }
        
        // Test bundle
        let testBundle = Bundle(for: type(of: self))
        if let testBundleID = testBundle.bundleIdentifier {
            print("Test Bundle ID: \(testBundleID)")
        } else {
            print("Test Bundle ID: NOT FOUND")
        }
        
        // Check if test bundle ID is child of main bundle ID
        if let main = Bundle.main.bundleIdentifier,
           let test = testBundle.bundleIdentifier {
            if test.hasPrefix(main + ".") {
                print("✅ Test bundle ID is correctly a child of main bundle")
            } else {
                print("❌ PROBLEM: Test bundle ID is NOT a child of main bundle")
                print("   Fix: Test bundle ID should be: \(main).Tests")
            }
        }
        
        print("=" * 50)
    }
}
