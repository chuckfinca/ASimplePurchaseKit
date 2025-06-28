// Tests/PurchaseKitIntegrationTests/SPMStoreKitDiagnostics.swift

import XCTest
import StoreKit
import StoreKitTest

@MainActor
final class SPMStoreKitDiagnostics: XCTestCase {

    let allProductIDsInFile = [
        "com.asimplepurchasekit.pro.lifetime",
        "com.asimplepurchasekit.pro.monthly",
        "com.asimplepurchasekit.pro.yearly"
    ]
    let lifetimeProductID = "com.asimplepurchasekit.pro.lifetime"
    let nestedBundleName = "ASimplePurchaseKitProject_PurchaseKitIntegrationTests.bundle" // Adjust if SPM names it differently

    override func setUpWithError() throws {
        print("\n==================================================================")
        print("Starting Test: \(self.name)")
        print("==================================================================")
    }

    override func tearDownWithError() throws {
        print("==================================================================")
        print("Finished Test: \(self.name)")
        print("==================================================================\n")
    }

    /// Attempts to find the nested resource bundle created by SPM for test targets.
    private func getSPMTestResourceBundle_PSI(mainTestBundle: Bundle) -> Bundle? { // Renamed to avoid conflict if SPMStoreKitDiagnostics is run together
        let baseBundleName = "ASimplePurchaseKitProject_PurchaseKitIntegrationTests" // Base name without .bundle
        let nestedBundleNameWithExtension = baseBundleName + ".bundle"

        // Try direct URL first
        if let nestedBundleURL = mainTestBundle.url(forResource: baseBundleName, withExtension: "bundle") {
            if let bundle = Bundle(url: nestedBundleURL) {
                print("✅ [PSI] Successfully loaded nested resource bundle (direct): \(bundle.bundlePath)")
                return bundle
            } else {
                print("❌ [PSI] Found URL for '\(nestedBundleNameWithExtension)' but could not create Bundle instance from it: \(nestedBundleURL.path)")
            }
        } else {
            print("⚠️ [PSI] Could not find nested resource bundle '\(nestedBundleNameWithExtension)' directly in main test bundle: \(mainTestBundle.bundlePath). Attempting enumeration...")
        }

        // Fallback to enumeration (more robust)
        if let resourcePath = mainTestBundle.resourcePath,
            let enumerator = FileManager.default.enumerator(atPath: resourcePath) {
            for case let path as String in enumerator {
                if path.hasSuffix(".bundle") && path.contains(baseBundleName) { // Check if the path contains the base name
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

    private func getStoreKitURLForIntegrationTest(filename: String) -> URL? {
        let mainTestBundle = Bundle(for: PurchaseServiceIntegrationTests.self)
        guard let spmResourceBundle = getSPMTestResourceBundle_PSI(mainTestBundle: mainTestBundle) else {
            XCTFail("[PSI] CRITICAL: Could not get SPM resource bundle. StoreKit file '\(filename)' cannot be loaded.")
            return nil
        }

        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension

        print("ℹ️ [PSI] Attempting to load '\(filename)' from SPM bundle: \(spmResourceBundle.bundlePath), name: '\(name)', ext: '\(ext)'")

        // Files are at the ROOT of the spmResourceBundle
        guard let url = spmResourceBundle.url(forResource: name, withExtension: ext) else {
            XCTFail("[PSI] Failed to get URL for '\(filename)' (name: '\(name)', ext: '\(ext)') from root of SPM resource bundle: \(spmResourceBundle.bundlePath)")
            // For debugging, list contents of spmResourceBundle if url is nil
            if let contents = try? FileManager.default.contentsOfDirectory(at: spmResourceBundle.bundleURL, includingPropertiesForKeys: nil) {
                print("‼️ [PSI] Contents of \(spmResourceBundle.bundleURL.lastPathComponent):")
                for item in contents {
                    print("  - \(item.lastPathComponent)")
                }
            } else {
                print("‼️ [PSI] Could not list contents of \(spmResourceBundle.bundleURL.lastPathComponent)")
            }
            return nil
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("[PSI] URL for '\(filename)' obtained but file does not exist at: \(url.path)")
            return nil
        }
        print("✅ [PSI] Confirmed URL for '\(filename)': \(url.path)")
        return url
    }

    // MARK: - Test 1: Bundle and Resource Path Investigation
    func test_A1_DebugResourceLoadingAndPaths() throws {
        print("🔬 TEST: Debugging Resource Loading and Bundle Paths")
        print("--------------------------------------------------")

        let mainTestBundle = Bundle(for: SPMStoreKitDiagnostics.self)
        print("ℹ️ Main Test Bundle Path: \(mainTestBundle.bundlePath)")
        if let resourcePath = mainTestBundle.resourcePath {
            print("ℹ️ Main Test Bundle Resource Path: \(resourcePath)")
        } else {
            print("⚠️ Main Test Bundle Resource Path: nil")
        }
        if let bundleIdentifier = mainTestBundle.bundleIdentifier {
            print("ℹ️ Main Test Bundle Identifier: \(bundleIdentifier)")
        } else {
            print("⚠️ Main Test Bundle Identifier: nil")
        }
        print("---")

        // --- Check for Main Bundle (Host App) ---
        let hostAppBundle = Bundle.main
        print("ℹ️ Host App Bundle Path: \(hostAppBundle.bundlePath)")
        if let hostBundleIdentifier = hostAppBundle.bundleIdentifier {
            print("ℹ️ Host App Bundle Identifier: \(hostBundleIdentifier)")
            if let testBundleIdentifier = mainTestBundle.bundleIdentifier {
                if testBundleIdentifier.hasPrefix(hostBundleIdentifier + ".") {
                    print("✅ Test bundle ID seems to be a child of Host App bundle ID.")
                } else if hostBundleIdentifier == "com.apple.dt.xctest.tool" {
                    print("⚠️ Host App Bundle is xctest.tool. This is common for SPM tests. Info.plist's TestedHostBundleIdentifier: \(hostAppBundle.infoDictionary?["TestedHostBundleIdentifier"] ?? "Not specified")")
                }
                else {
                    print("❌ PROBLEM: Test bundle ID ('\(testBundleIdentifier)') is NOT a child of host app bundle ('\(hostBundleIdentifier)').")
                }
            }
        } else {
            print("⚠️ Host App Bundle Identifier: nil")
        }
        print("---")


        print("🔎 Attempting to locate nested SPM resource bundle '\(nestedBundleName)'...")
        guard let spmResourceBundle = getSPMTestResourceBundle_PSI(mainTestBundle: mainTestBundle) else {
            XCTFail("❌ CRITICAL: Could not locate or load the nested SPM resource bundle ('\(nestedBundleName)' or similar). StoreKit files will not be found.")
            return
        }
        print("✅ Using SPM Resource Bundle: \(spmResourceBundle.bundlePath)")
        if let spmResourceBundlePath = spmResourceBundle.resourcePath {
            print("ℹ️ SPM Resource Bundle's Resource Path: \(spmResourceBundlePath)")
        } else {
            print("⚠️ SPM Resource Bundle's Resource Path: nil")
        }
        print("---")

        var foundStoreKitFileViaSPMBundle = false
        let storeKitFilesToFind = ["Products.storekit", "TestLifetimeOnly.storekit", "TestSubscriptionOnly.storekit", "TestMinimalSubscription.storekit"]

        print("🔎 Attempting to locate .storekit files within the SPM Resource Bundle...")
        for fileName in storeKitFilesToFind {
            let name = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension

            // Now look at the ROOT of the spmResourceBundle
            // The Package.swift uses .copy("Resources/Products.storekit"), which copies *into* the target bundle.
            // So the "Resources" path segment from Package.swift is ALREADY part of how it got into spmResourceBundle.
            // Therefore, we might expect them at the root of spmResourceBundle if the .copy path was relative to the target's source root.
            // OR if .copy("Resources/Products.storekit") means it puts a "Resources" folder *inside* spmResourceBundle.

            // Attempt 1: In a "Resources" subdirectory INSIDE spmResourceBundle
            if let url = spmResourceBundle.url(forResource: name, withExtension: ext, subdirectory: "Resources") {
                if FileManager.default.fileExists(atPath: url.path) {
                    print("✅ FOUND (SPM Bundle Pattern 1): '\(fileName)' in '\(spmResourceBundle.bundleURL.lastPathComponent)/Resources/': \(url.path)")
                    foundStoreKitFileViaSPMBundle = true
                } else {
                    print("⚠️ NOMINALLY FOUND (SPM Bundle Pattern 1), BUT DOES NOT EXIST: '\(fileName)' in '\(spmResourceBundle.bundleURL.lastPathComponent)/Resources/' at: \(url.path)")
                }
            } else {
                print("❌ NOT FOUND (SPM Bundle Pattern 1): '\(fileName)' in '\(spmResourceBundle.bundleURL.lastPathComponent)/Resources/'.")
            }

            // Attempt 2: At the ROOT of spmResourceBundle
            if let url = spmResourceBundle.url(forResource: name, withExtension: ext) {
                if FileManager.default.fileExists(atPath: url.path) {
                    print("✅ FOUND (SPM Bundle Pattern 2): '\(fileName)' at root of '\(spmResourceBundle.bundleURL.lastPathComponent)': \(url.path)")
                    foundStoreKitFileViaSPMBundle = true
                } else {
                    print("⚠️ NOMINALLY FOUND (SPM Bundle Pattern 2), BUT DOES NOT EXIST: '\(fileName)' at root of '\(spmResourceBundle.bundleURL.lastPathComponent)' at: \(url.path)")
                }
            } else {
                print("❌ NOT FOUND (SPM Bundle Pattern 2): '\(fileName)' at root of '\(spmResourceBundle.bundleURL.lastPathComponent)'.")
            }
            print("---")
        }

        XCTAssertTrue(foundStoreKitFileViaSPMBundle, "At least one .storekit file should be locatable within the determined SPM resource bundle.")

        print("\n📄 Enumerating SPM Resource Bundle's resourcePath contents directly for '.storekit' files:")
        var enumeratedStoreKitFilesCountInSPMBundle = 0
        if let spmBundleResourcePath = spmResourceBundle.resourcePath,
            let enumerator = FileManager.default.enumerator(atPath: spmBundleResourcePath) {
            for case let path as String in enumerator {
                if path.hasSuffix(".storekit") {
                    print("  📄 Found via SPM bundle enumeration: \(spmBundleResourcePath)/\(path)")
                    enumeratedStoreKitFilesCountInSPMBundle += 1
                }
            }
            print("  ℹ️ Total .storekit files found by SPM bundle enumeration: \(enumeratedStoreKitFilesCountInSPMBundle)")
            XCTAssertGreaterThan(enumeratedStoreKitFilesCountInSPMBundle, 0, "Enumerator should find .storekit files in the SPM resource bundle.")
        } else {
            print("  ⚠️ Could not enumerate spmResourceBundle.resourcePath ('\(spmResourceBundle.resourcePath ?? "nil")').")
            if spmResourceBundle.resourcePath == nil {
                print("     This often means the bundle is 'flat' and its main bundlePath IS its resourcePath.")
                // Try enumerating bundlePath if resourcePath is nil
                if let enumerator = FileManager.default.enumerator(atPath: spmResourceBundle.bundlePath) {
                    print("  📄 Retrying enumeration on spmResourceBundle.bundlePath ('\(spmResourceBundle.bundlePath)')...")
                    enumeratedStoreKitFilesCountInSPMBundle = 0
                    for case let path as String in enumerator {
                        if path.hasSuffix(".storekit") {
                            print("    📄 Found via SPM bundlePath enumeration: \(spmResourceBundle.bundlePath)/\(path)")
                            enumeratedStoreKitFilesCountInSPMBundle += 1
                        }
                    }
                    print("    ℹ️ Total .storekit files found by SPM bundlePath enumeration: \(enumeratedStoreKitFilesCountInSPMBundle)")
                    XCTAssertGreaterThan(enumeratedStoreKitFilesCountInSPMBundle, 0, "Enumerator on bundlePath should find .storekit files if resourcePath was nil.")
                } else {
                    XCTFail("Could not enumerate spmResourceBundle.resourcePath OR spmResourceBundle.bundlePath.")
                }
            } else {
                XCTFail("Could not enumerate spmResourceBundle.resourcePath.")
            }
        }
        print("--------------------------------------------------")
    }

    // Helper to get a validated URL for a .storekit file from the SPM nested resource bundle
    private func getStoreKitURLInSPMBundle(filename: String) -> URL? {
        let mainTestBundle = Bundle(for: SPMStoreKitDiagnostics.self)
        guard let spmResourceBundle = getSPMTestResourceBundle_PSI(mainTestBundle: mainTestBundle) else {
            print("❌ Failed to get SPM resource bundle in getStoreKitURLInSPMBundle.")
            return nil
        }

        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension

        // Based on your enumeration: ...ASimplePurchaseKitProject_PurchaseKitIntegrationTests.bundle/Products.storekit
        // This means the files are at the ROOT of the spmResourceBundle.
        // The ".copy("Resources/Products.storekit")" in Package.swift means:
        // "Take Products.storekit from the 'Resources' FOLDER in my source tree
        // and copy IT to the root of the target's resource bundle."

        // Pattern 1: At the ROOT of spmResourceBundle (MOST LIKELY based on your logs)
        if let url = spmResourceBundle.url(forResource: name, withExtension: ext) {
            if FileManager.default.fileExists(atPath: url.path) {
                print("✅ Confirmed URL (SPM Bundle Root) for '\(filename)': \(url.path)")
                return url
            }
        }

        // Pattern 2: In a "Resources" subdirectory INSIDE spmResourceBundle (Less likely but worth checking)
        if let url = spmResourceBundle.url(forResource: name, withExtension: ext, subdirectory: "Resources") {
            if FileManager.default.fileExists(atPath: url.path) {
                print("✅ Confirmed URL (SPM Bundle/Resources) for '\(filename)': \(url.path)")
                return url
            }
        }

        print("❌ Failed to get confirmed URL for '\(filename)' in SPM resource bundle ('\(spmResourceBundle.bundleIdentifier ?? spmResourceBundle.bundlePath)'). Looked at root and in 'Resources' subdirectory.")
        return nil
    }

    // MARK: - Test 2: Programmatic SKTestSession and Product Fetch
    func test_A2_ProgrammaticSKTestSession_ProductFetch() async throws {
        print("🔬 TEST: Programmatic SKTestSession and Product Fetch")
        print("--------------------------------------------------")

        guard let url = getStoreKitURLInSPMBundle(filename: "Products.storekit") else {
            XCTFail("❌ CRITICAL: Could not get URL for 'Products.storekit' from SPM resource bundle. Check test_A1_DebugResourceLoadingAndPaths output.")
            return
        }
        print("ℹ️ Using Products.storekit at: \(url.path)")

        var session: SKTestSession!
        do {
            session = try SKTestSession(contentsOf: url)
            session.resetToDefaultState()
            session.clearTransactions()
            session.disableDialogs = true
            print("✅ SKTestSession initialized successfully from '\(url.lastPathComponent)'.")
        } catch {
            XCTFail("❌ SKTestSession initialization failed: \(error)")
            return
        }

        let delayMilliseconds: UInt64 = 2000
        print("ℹ️ Pausing for \(delayMilliseconds)ms for StoreKit to settle with SKTestSession...")
        try await Task.sleep(for: .milliseconds(delayMilliseconds))
        print("ℹ️ Pause complete.")

        print("🔎 Attempting Product.products(for: [\(allProductIDsInFile.joined(separator: ", "))])...")
        do {
            let products = try await Product.products(for: allProductIDsInFile)
            print("🛒 Fetched \(products.count) products using specific IDs from 'Products.storekit':")
            for product in products {
                print("  - ID: \(product.id), DisplayName: \(product.displayName), Price: \(product.displayPrice)")
            }

            if products.isEmpty && !allProductIDsInFile.isEmpty {
                print("⚠️ WARNING (P1/P3): No products fetched. This might be the StoreKit simulator bug if on affected iOS 17/18 versions or due to mixed-type .storekit (P3).")
            } else if products.count == 1 && products.first?.id == lifetimeProductID {
                print("✅ Fetched only lifetime product - typical P3 behavior for mixed 'Products.storekit' file on some simulators.")
            } else if products.count < allProductIDsInFile.count && products.count > 0 {
                print("⚠️ Fetched some but not all products. Count: \(products.count). Potential P1/P3 issue.")
            } else if products.count == allProductIDsInFile.count {
                print("✅ Successfully fetched all expected products from 'Products.storekit'.")
            }
            // Consider XCTAssertFalse(products.isEmpty, "Should fetch at least one product if P1/P3 are not active or for lifetime product")
            // This will still be subject to simulator issues.

        } catch {
            print("❌ ERROR fetching products with SKTestSession: \(error)")
            XCTFail("Error fetching products with SKTestSession: \(error.localizedDescription)")
        }
        print("--------------------------------------------------")
    }

    // MARK: - Test 3: Scheme/Plan-Based Product Fetch (No Programmatic Session)
    // (This test remains largely the same, its interpretation depends on whether a default .storekit file can be set for SPM test plans)
    func test_A3_SchemeOrPlanBased_ProductFetch() async throws {
        print("🔬 TEST: Scheme/Plan-Based Product Fetch (No Programmatic SKTestSession)")
        print("--------------------------------------------------")
        print("ℹ️ This test relies on Xcode's Test Plan or Scheme setting a default StoreKit Configuration.")
        print("ℹ️ For SPM packages, this often defaults to 'None'. If 0 products, check Test Plan's 'Configurations' tab for the test target.")

        let delayMilliseconds: UInt64 = 1500
        print("ℹ️ Pausing for \(delayMilliseconds)ms for StoreKit to initialize...")
        try await Task.sleep(for: .milliseconds(delayMilliseconds))
        print("ℹ️ Pause complete.")

        var productsFoundCount = 0
        print("🔎 Attempting Product.products(for: [\(allProductIDsInFile.joined(separator: ", "))]) (scheme-based)...")
        do {
            let products = try await Product.products(for: allProductIDsInFile)
            productsFoundCount = products.count
            print("🛒 Fetched \(products.count) products using specific IDs (scheme-based):")
            for product in products {
                print("  - ID: \(product.id), DisplayName: \(product.displayName), Price: \(product.displayPrice)")
            }
            if products.isEmpty {
                print("ℹ️ 0 products found with specific IDs (scheme-based). This is expected if no default .storekit file is set in the test plan/scheme for the 'PurchaseKitIntegrationTests' target.")
            }
        } catch {
            print("❌ ERROR fetching products with specific IDs (scheme-based): \(error)")
        }

        print("---")
        print("🔎 Attempting Product.products(for: []) (i.e., Product.all) (scheme-based)...")
        do {
            let allProducts = try await Product.products(for: []) // Product.all
            print("🛒 Fetched \(allProducts.count) products using Product.all (scheme-based):")
            for product in allProducts {
                print("  - ID: \(product.id), DisplayName: \(product.displayName), Price: \(product.displayPrice)")
            }
            if allProducts.isEmpty {
                print("ℹ️ 0 products found with Product.all (scheme-based). Expected if no default .storekit file is set.")
            }
        } catch {
            print("❌ ERROR fetching with Product.all (scheme-based): \(error)")
        }
        print("--------------------------------------------------")
    }

    // MARK: - Test 4: Basic Environment Variables
    // This "test" primarily logs environment variables for debugging purposes.
    // It does not contain assertions and won't fail unless the process itself crashes.
    // Its value is in providing context when diagnosing environmental issues with StoreKit.
    func test_A4_RelevantEnvironmentVariables() {
        print("🔬 TEST: Relevant Environment Variables")
        print("--------------------------------------------------")
        let env = ProcessInfo.processInfo.environment
        let relevantKeys = [
            "XCTestConfigurationFilePath",
            "XCODE_PRODUCT_BUILD_VERSION",
            "SDK_NAME",
            "PLATFORM_NAME",
            "STOREKIT_CONFIG",
            "TEST_HOST"
        ]

        for key in relevantKeys {
            if let value = env[key], !value.isEmpty {
                print("  \(key): '\(value)'")
            } else {
                print("  \(key): Not set or empty")
            }
        }
        print("--------------------------------------------------")
    }

    // MARK: - Test 5: Validate JSON Structure of a Found StoreKit File
    func test_A5_ValidateStoreKitFileJSONStructure() throws {
        print("🔬 TEST: Validate JSON Structure of 'Products.storekit'")
        print("--------------------------------------------------")

        guard let url = getStoreKitURLInSPMBundle(filename: "Products.storekit") else {
            XCTFail("❌ CRITICAL: Could not get URL for 'Products.storekit' from SPM resource bundle. Cannot validate JSON.")
            return
        }
        print("ℹ️ Validating JSON for: \(url.path)")

        do {
            let data = try Data(contentsOf: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                XCTFail("❌ Parsed JSON for '\(url.lastPathComponent)' was not a [String: Any] dictionary.")
                return
            }

            if let version = json["version"] as? [String: Int] {
                print("  ✅ StoreKit file version: \(version["major"] ?? 0).\(version["minor"] ?? 0)")
            } else { print("  ⚠️ StoreKit file version: Not found") }

            if let identifier = json["identifier"] as? String {
                print("  ✅ Configuration identifier: \(identifier)")
            } else { print("  ⚠️ Configuration identifier: Not found") }

            let topLevelProducts = (json["products"] as? [[String: Any]]) ?? []
            print("  📦 Top-level products in JSON: \(topLevelProducts.count)")
            for (idx, product) in topLevelProducts.enumerated() {
                let productID = product["productID"] as? String ?? "unknown_id_\(idx)"
                let type = product["type"] as? String ?? "unknown_type"
                print("    - \(productID) (type: \(type))")
            }
            XCTAssertEqual(topLevelProducts.first?["productID"] as? String, lifetimeProductID, "First product in Products.storekit JSON should be the lifetime product.")


            let groups = json["subscriptionGroups"] as? [[String: Any]] ?? []
            print("  📦 Subscription groups in JSON: \(groups.count)")
            var totalSubsInJSON = 0
            for group in groups {
                let groupName = group["name"] as? String ?? "unnamed_group"
                let subs = group["subscriptions"] as? [[String: Any]] ?? []
                totalSubsInJSON += subs.count
                print("    - Group '\(groupName)' with \(subs.count) subscriptions:")
                for (sIdx, sub) in subs.enumerated() {
                    let subID = sub["productID"] as? String ?? "unknown_sub_id_\(sIdx)"
                    print("      • \(subID)")
                }
            }
            XCTAssertEqual(totalSubsInJSON, 2, "Products.storekit JSON should define 2 subscriptions.")

            print("  ✅ JSON structure seems valid for 'Products.storekit'.")

        } catch {
            XCTFail("❌ Failed to read or parse JSON for '\(url.lastPathComponent)': \(error)")
        }
        print("--------------------------------------------------")
    }
}

// Helper extension (keep or move as needed)
extension Product {
    static var all: [Product] {
        get async throws {
            return try await products(for: [])
        }
    }
}
