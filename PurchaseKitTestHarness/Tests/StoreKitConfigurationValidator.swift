import XCTest
import StoreKit
import StoreKitTest

@MainActor
final class StoreKitConfigurationValidator: XCTestCase {
    
    func test_validateStoreKitConfiguration() async throws {
        print("\n🔍 STOREKIT CONFIGURATION VALIDATOR")
        print("=" * 70)
        
        // Step 1: Check if we can load the .storekit file
        let testBundle = Bundle(for: type(of: self))
        guard let url = testBundle.url(forResource: "Products", withExtension: "storekit") else {
            XCTFail("❌ Could not find Products.storekit in test bundle")
            return
        }
        print("✅ Found Products.storekit at: \(url.path)")
        
        // Step 2: Validate the JSON structure
        do {
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            // Check version
            if let version = json?["version"] as? [String: Int] {
                print("✅ StoreKit file version: \(version["major"] ?? 0).\(version["minor"] ?? 0)")
            }
            
            // Check identifier
            if let identifier = json?["identifier"] as? String {
                print("✅ Configuration identifier: \(identifier)")
            }
            
            // Validate products
            let products = json?["products"] as? [[String: Any]] ?? []
            print("\n📦 Products found in configuration: \(products.count)")
            for product in products {
                let productID = product["productID"] as? String ?? "unknown"
                let type = product["type"] as? String ?? "unknown"
                print("  - \(productID) (type: \(type))")
            }
            
            // Validate subscription groups
            let groups = json?["subscriptionGroups"] as? [[String: Any]] ?? []
            print("\n📦 Subscription groups: \(groups.count)")
            for group in groups {
                let groupName = group["name"] as? String ?? "unnamed"
                let subs = group["subscriptions"] as? [[String: Any]] ?? []
                print("  - Group '\(groupName)' with \(subs.count) subscriptions")
                for sub in subs {
                    let subID = sub["productID"] as? String ?? "unknown"
                    print("    • \(subID)")
                }
            }
            
        } catch {
            XCTFail("❌ Failed to parse Products.storekit: \(error)")
        }
        
        print("\n" + "=" * 70)
    }
    
    func test_minimalStoreKitFetch_withoutSession() async throws {
        print("\n🧪 TEST: Fetching without SKTestSession (relies on scheme config)")
        print("=" * 70)
        
        // Don't create any SKTestSession - rely purely on scheme configuration
        
        // Wait a bit for StoreKit to initialize
        try await Task.sleep(for: .milliseconds(1000))
        
        // Try different approaches to fetch products
        print("\n1️⃣ Trying Product.products(for: specific IDs)...")
        let specificIDs = [
            "com.asimplepurchasekit.pro.lifetime",
            "com.asimplepurchasekit.pro.monthly",
            "com.asimplepurchasekit.pro.yearly"
        ]
        
        do {
            let products = try await Product.products(for: specificIDs)
            print("   Found \(products.count) products")
            for product in products {
                print("   • \(product.id): \(product.displayName)")
            }
        } catch {
            print("   ❌ Error: \(error)")
        }
        
        print("\n2️⃣ Trying Product.products(for: []) to get ALL products...")
        do {
            let allProducts = try await Product.products(for: [])
            print("   Found \(allProducts.count) products total")
        } catch {
            print("   ❌ Error: \(error)")
        }
        
        print("\n" + "=" * 70)
    }
    
    func test_storeKitFetch_withProgrammaticSession() async throws {
        print("\n🧪 TEST: Fetching WITH programmatic SKTestSession")
        print("=" * 70)
        
        let testBundle = Bundle(for: type(of: self))
        guard let url = testBundle.url(forResource: "Products", withExtension: "storekit") else {
            XCTFail("Could not find Products.storekit")
            return
        }
        
        // Create session
        let session = try SKTestSession(contentsOf: url)
        
        // Try different configurations
        print("\n🔧 Testing different session configurations...")
        
        // Configuration 1: Minimal
        print("\n[Config 1] Minimal setup")
        session.resetToDefaultState()
        session.clearTransactions()
        
        try await Task.sleep(for: .milliseconds(500))
        var products = try await Product.products(for: ["com.asimplepurchasekit.pro.lifetime"])
        print("  Products found: \(products.count)")
        
        // Configuration 2: With storefront
        print("\n[Config 2] With storefront")
        session.storefront = "USA"
        
        try await Task.sleep(for: .milliseconds(500))
        products = try await Product.products(for: ["com.asimplepurchasekit.pro.lifetime"])
        print("  Products found: \(products.count)")
        
        // Configuration 3: Full setup (like your tests)
        print("\n[Config 3] Full setup")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.storefront = "USA"
        
        try await Task.sleep(for: .milliseconds(1500))
        products = try await Product.products(for: [])
        print("  Products found: \(products.count)")
        
        print("\n" + "=" * 70)
    }
}

// Extension to repeat strings (for visual separators)
extension String {
    static func *(lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}
