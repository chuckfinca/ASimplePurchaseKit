# ASimplePurchaseKit

A lightweight, modern, and testable Swift package for handling in-app purchases using StoreKit 2. Designed with SwiftUI in mind, ASimplePurchaseKit simplifies fetching products, making purchases (including with promotional offers), checking entitlement status, and managing transaction history with a clean, async/await-based API.

## ✨ Features

- **Modern API**: Built exclusively on the new StoreKit 2 async/await APIs.
- **SwiftUI Ready**: The main `PurchaseService` is an `ObservableObject`, making it trivial to bind your UI to purchase states.
- **Highly Testable**: Built with protocols and dependency injection, allowing you to easily mock the purchase flow in your unit tests.
- **Automatic Transaction Handling**: Listens for `Transaction.updates` to automatically handle renewals, refunds, and purchases made outside the app.
- **Simple Entitlement Checking**: A clear `EntitlementStatus` enum (`.subscribed`, `.notSubscribed`, `.unknown`) serves as the single source of truth for user access.
- **Comprehensive Support**: Handles auto-renewable subscriptions, non-consumables (lifetime purchases), and consumables.
- **Promotional Offer Support**: Fetch and purchase with StoreKit promotional offers (e.g., introductory offers).
- **Transaction History**: Retrieve all verified transactions for the user.
- **Utilities**: Includes helpers like localized subscription period descriptions.
- **Zero External Dependencies**: Pure Swift and StoreKit.

## 📋 Requirements

- iOS 16.4+ (due to some modern StoreKit features and Swift Concurrency usage)
- macOS 13.3+

## 📦 Installation

You can add ASimplePurchaseKit to your Xcode project using the Swift Package Manager.

1.  In Xcode, open your project and navigate to **File > Add Packages...**
2.  Paste the repository URL into the search bar:
    ```
    https://github.com/chuckfinca/ASimplePurchaseKit.git
    ```
3.  Select the `ASimplePurchaseKit` package and add it to your app target.

*(Replace with your actual GitHub repository URL)*

## 🚀 Usage

### 1. Configure the Service

First, you'll need a `.storekit` configuration file in your project for testing. Define your product identifiers there and in App Store Connect.

In your app's entry point or a central location, initialize the `PurchaseService`. It's an `ObservableObject`, so you can inject it into your SwiftUI environment.

```swift
import SwiftUI
import ASimplePurchaseKit

@main
struct YourApp: App {
    // Create the config with your product IDs
    private static let purchaseConfig = PurchaseConfig(
        productIDs: ["com.yourapp.pro.monthly", "com.yourapp.pro.yearly", "com.yourapp.feature.lifetime", "com.yourapp.coins.100"],
        enableLogging: true // Enable detailed logging from the library
    )
    
    // Initialize the service and hold it in a @StateObject
    @StateObject private var purchaseService = PurchaseService(config: purchaseConfig)
    
    // Optionally, set a delegate (see "Delegate for Logging & Events" below)
    // private var appDelegate = MyAppPurchaseDelegate() // Conforms to PurchaseServiceDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(purchaseService) // Make it available to all views
                // .onAppear { purchaseService.delegate = appDelegate } // Set delegate
        }
    }
}
```

### 2. Display Products and Make a Purchase

In your paywall view, access the service from the environment and display the fetched products.

```swift
import SwiftUI
import ASimplePurchaseKit
import StoreKit // For Product.SubscriptionPeriod if using its extensions

struct PaywallView: View {
    @EnvironmentObject var purchaseService: PurchaseService
    @State private var selectedOfferID: String? = nil // For promotional offers

    var body: some View {
        VStack(spacing: 20) {
            Text("Go Pro!")
                .font(.largeTitle)

            // Loop through the available products
            ForEach(purchaseService.availableProducts) { product in
                ProductListingView(product: product, purchaseService: purchaseService, selectedOfferID: $selectedOfferID)
            }
            
            // Show a progress indicator based on purchaseState
            // This demonstrates how to react to the PurchaseState enum
            switch purchaseService.purchaseState {
            case .idle:
                EmptyView() // Or other UI elements like a "Restore Purchases" button
            case .fetchingProducts:
                ProgressView("Loading products...")
            case .purchasing(let purchasingProductID):
                VStack {
                    ProgressView()
                    Text("Purchasing \(purchaseService.availableProducts.first(where: {$0.id == purchasingProductID})?.displayName ?? purchasingProductID)...")
                }
            case .restoring:
                ProgressView("Restoring purchases...")
            case .checkingEntitlement:
                ProgressView("Verifying access...")
            }
            
            // Optionally, display errors
            if let failure = purchaseService.lastFailure {
                Text("Error during \(failure.operation): \(failure.error.localizedDescription)")
                    .foregroundColor(.red)
                    .padding()
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        // Example: Fetch products when view appears if not done automatically or if needed
        .onAppear {
            if purchaseService.availableProducts.isEmpty && purchaseService.purchaseState == .idle {
                Task {
                    await purchaseService.fetchProducts()
                }
            }
        }
    }
}

// A view to display a single product and its offers
struct ProductListingView: View {
    let product: ProductProtocol
    @ObservedObject var purchaseService: PurchaseService // Pass directly or use @EnvironmentObject
    @Binding var selectedOfferID: String? // To highlight selected offer

    var body: some View {
        VStack(alignment: .leading) {
            Text(product.displayName)
                .font(.headline)
            Text(product.description)
                .font(.caption)
                .foregroundColor(.gray)
            
            // Display promotional offers if it's a subscription
            if product.type == .autoRenewable {
                let offers = purchaseService.eligiblePromotionalOffers(for: product)
                if !offers.isEmpty {
                    Text("Available Offers:").font(.subheadline).padding(.top, 5)
                    ForEach(offers, id: \.id) { offer in // Assuming offer.id is unique enough for ForEach
                        Button(action: {
                            self.selectedOfferID = offer.id 
                            Task {
                                await handlePurchase(productID: product.id, offerID: offer.id)
                            }
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(offer.displayName)
                                    // Use the localizedDescription for the period
                                    Text("\(offer.paymentMode.description) for \(offer.period.localizedDescription) at \(offer.displayPrice)")
                                        .font(.caption)
                                }
                                Spacer()
                                if selectedOfferID == offer.id && purchaseService.purchaseState == .purchasing(productID: product.id) {
                                    ProgressView()
                                }
                            }
                            .padding()
                            .background( (selectedOfferID == offer.id ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1)) )
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Standard purchase button (without specific offer, or for non-subscriptions/consumables)
            Button(action: {
                self.selectedOfferID = nil // Clear specific offer selection
                Task {
                    await handlePurchase(productID: product.id, offerID: nil)
                }
            }) {
                HStack {
                    Text("Buy for \(product.displayPrice)")
                        .font(.headline)
                    Spacer()
                     if selectedOfferID == nil && purchaseService.purchaseState == .purchasing(productID: product.id) {
                        ProgressView()
                    }
                }
            }
            .padding()
            .background(Color.green.opacity(0.2))
            .cornerRadius(10)
            .padding(.top, product.type == .autoRenewable && !purchaseService.eligiblePromotionalOffers(for: product).isEmpty ? 5 : 0)

        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }

    private func handlePurchase(productID: String, offerID: String?) async {
        do {
            // The purchase function returns a verified transaction.
            let transaction = try await purchaseService.purchase(productID: productID, offerID: offerID)

            // The purchase was successful.
            // The library automatically updates entitlementStatus for subscriptions and non-consumables.
            // For consumables, you would now grant the content to the user (e.g., add coins).
            print("Purchase successful, transaction ID: \(transaction.id)")

            // IMPORTANT: You must finish the transaction once the content is granted.
            await transaction.finish()
            
        } catch {
            // The purchase failed. The `lastFailure` property on purchaseService will also be set.
            print("Purchase failed: \(error.localizedDescription)")
        }
    }
}

// Helper for Product.SubscriptionOffer.PaymentMode description
extension Product.SubscriptionOffer.PaymentMode {
    var description: String {
        switch self {
        case .payAsYouGo: return "Pay As You Go"
        case .payUpFront: return "Pay Up Front"
        case .freeTrial: return "Free Trial"
        @unknown default: return "Unknown"
        }
    }
}
```

#### Important: Handling the Transaction
After a successful purchase, the `purchase(productID:offerID:)` method returns a verified `StoreKit.Transaction`. Your app is then responsible for finishing this transaction by calling `await transaction.finish()`.

- **For Subscriptions and Non-Consumables:** The library automatically updates the `entitlementStatus`. You simply need to call `finish()` on the transaction.
- **For Consumables:** This pattern is critical. You must first grant the content to the user (e.g., add coins to their balance) and *then* call `finish()`. Finishing the transaction removes it from the payment queue, preventing the user from being granted the same content again on the next app launch.

### 3. Check Entitlement Status

Use the `entitlementStatus` property to control access to premium features. The `.isActive` property is a convenient shortcut.

```swift
import SwiftUI
import ASimplePurchaseKit

struct ContentView: View {
    @EnvironmentObject var purchaseService: PurchaseService

    var body: some View {
        // You might want to wait until entitlementStatus is known
        if purchaseService.purchaseState == .checkingEntitlement && purchaseService.entitlementStatus == .unknown {
            ProgressView("Checking access...")
        } else if purchaseService.entitlementStatus.isActive {
            // Show premium content if the user is subscribed
            PremiumFeaturesView()
        } else {
            // Otherwise, show the paywall
            PaywallView()
        }
    }
}

struct PremiumFeaturesView: View {
    var body: some View {
        Text("Welcome to Premium Content!")
            .font(.largeTitle)
    }
}
```

### 4. Restore Purchases

Provide a button for users to restore their previous purchases. `ASimplePurchaseKit` will sync with the App Store, and the transaction listener will automatically update the entitlement status.

```swift
Button("Restore Purchases") {
    Task {
        await purchaseService.restorePurchases()
    }
}
// Observe purchaseService.purchaseState == .restoring to show a ProgressView
```

### 5. Transaction History & Subscription Details

You can retrieve all verified transactions for the user or get details for a specific subscription:
 
```swift
// Get all transactions
Task {
    let transactions = await purchaseService.getAllTransactions()
    // Process transactions (e.g., for display, record keeping)
    for tx in transactions {
        print("Transaction ID: \(tx.id), Product ID: \(tx.productID), Date: \(tx.purchaseDate)")
    }
}

// Get details for a specific subscription
Task {
    if let subDetails = await purchaseService.getSubscriptionDetails(for: "com.yourapp.pro.monthly") {
        print("Monthly subscription state: \(subDetails.state)")
        
        // Safely unwrap the verified renewal info
        switch subDetails.renewalInfo {
        case .verified(let renewalInfo):
            print("Will auto-renew: \(renewalInfo.willAutoRenew)")
            if let expirationDate = renewalInfo.expirationDate {
                print("Expires on: \(expirationDate)")
            }
        case .unverified(let renewalInfo, _):
            // Handle unverified data if necessary, maybe show a warning
            print("Renewal info is unverified but will auto-renew: \(renewalInfo.willAutoRenew)")
        }

    } else {
        print("No active subscription details found for com.yourapp.pro.monthly")
    }
}
```

### 6. Checking Payment Capability

Before attempting a purchase, you can check if the user is generally allowed to make payments (e.g., not restricted by parental controls).

```swift
if purchaseService.canMakePayments() {
    // Proceed with showing purchase options
} else {
    // Inform user they cannot make payments
    Text("Payments are disabled on this device (e.g., due to parental controls).")
}
```

### 7. Using Subscription Period Descriptions

When displaying subscription period information (e.g., from a promotional offer or product details):

```swift
import StoreKit // Required for Product.SubscriptionPeriod extension

// Assuming 'offer' is a PromotionalOfferProtocol or 'product.subscription' is a SubscriptionInfoProtocol
// let period: Product.SubscriptionPeriod = offer.period 
// Text("Duration: \(period.localizedDescription)") // e.g., "1 month", "7 days"
```

### 8. Delegate for Logging & Events 

You can set a delegate on `PurchaseService` to receive logs and important events.

```swift
class MyAppPurchaseDelegate: PurchaseServiceDelegate, @unchecked Sendable { // Ensure Sendable if used across actors
    func purchaseService(didLog event: String, level: LogLevel, context: [String : String]?) {
        // Send to your own logging system
        // Example: MyAnalytics.log("ASimplePurchaseKit: [\(level)] \(event)", properties: context)
        print("Delegate Log: [\(level)] \(event) - Context: \(context ?? [:])")
    }
}

// In your app setup (e.g., within YourApp struct):
// let myDelegate = MyAppPurchaseDelegate()
// _purchaseService.wrappedValue.delegate = myDelegate // If using @StateObject
// or in onAppear of your root view.
```

## 🧪 Testing

The library is designed to be easily testable. You can initialize `PurchaseService` with mock providers (available in the `UnitTests` target if you import it as `@testable`) to simulate any StoreKit scenario without needing the network or a `.storekit` file for your *unit tests*.

This approach, known as dependency injection, allows you to take full control over the service's external interactions.

```swift
import XCTest
@testable import ASimplePurchaseKit // Use @testable to access internal types and mocks
import Combine

@MainActor
final class MyViewModelTests: XCTestCase {

    var purchaseService: PurchaseService!
    var mockProvider: MockPurchaseProvider!
    var mockSyncer: MockAppStoreSyncer!
    var cancellables: Set<AnyCancellable>!

    // Use setUp to initialize state for each test
    override func setUp() {
        super.setUp()
        cancellables = []
        mockProvider = MockPurchaseProvider()
        mockSyncer = MockAppStoreSyncer()
        
        purchaseService = PurchaseService(
            productIDs: ["com.test.product"],
            productProvider: mockProvider,
            purchaser: mockProvider,
            receiptValidator: mockProvider,
            // Inject the mock system providers
            transactionListenerProvider: MockTransactionListenerProvider(), // Can be a plain instance if not used in test
            appStoreSyncer: mockSyncer,
            enableLogging: false
        )
    }

    // Use tearDown to clean up after each test
    override func tearDown() {
        purchaseService = nil
        mockProvider = nil
        mockSyncer = nil
        cancellables = nil
        super.tearDown()
    }

    func test_restorePurchases_whenSuccessful_updatesEntitlement() async throws {
        // ARRANGE
        let expectation = XCTestExpectation(description: "Entitlement status changes to active after restore")
        
        // The .store(in:) method correctly handles the subscription's lifecycle.
        purchaseService.$entitlementStatus
            .dropFirst() // Ignore initial status
            .sink { status in
                if status.isActive {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables) // Store the subscription to keep it alive
        
        // ACT: Configure the mock providers to simulate a successful restore
        // 1. The syncer will succeed
        mockSyncer.syncShouldThrowError = nil 
        // 2. The subsequent entitlement check will find a lifetime purchase
        mockProvider.entitlementResult = .success(.subscribed(expires: nil, isInGracePeriod: false))
        
        // 3. Call the method on the SUT
        await purchaseService.restorePurchases()
        
        // ASSERT
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertEqual(mockSyncer.syncCallCount, 1, "AppStore.sync() should have been called once.")
        XCTAssertEqual(mockProvider.checkCurrentEntitlementsCallCount, 1)
        XCTAssertTrue(purchaseService.entitlementStatus.isActive)
        XCTAssertNil(purchaseService.lastFailure)
        
        // No need to manually cancel, tearDown handles it.
    }
}
```

## 🏗️ Architecture

- **PurchaseService**: The main public class and `ObservableObject` that your app interacts with.
- **PurchaseConfig**: A simple struct to configure the service with your product IDs and logging preference.
- **EntitlementStatus**: A public enum that represents the user's access level.
- **PurchaseError**: A public enum for specific, user-facing errors.
- **PurchaseFailure**: A struct providing context for errors (error, productID, operation, timestamp).
- **PurchaseState**: An enum indicating the current operation of the `PurchaseService`.
- **PurchaseProtocols**: A set of protocols (`ProductProvider`, `Purchaser`, `ReceiptValidator`, `ProductProtocol`, `PromotionalOfferProtocol`, etc.) that define the core purchase-related actions and data types.
- **LivePurchaseProvider**: The internal, concrete implementation of the protocols that communicates with StoreKit. Your app never touches this directly.
- **StoreKitAdapters**: Internal types that adapt `StoreKit.Product` and related types to the library's protocols.
- **Extensions**: Utility extensions (e.g., `Product.SubscriptionPeriod.localizedDescription`).

## License

This project is licensed under the MIT License. See the LICENSE file for details.
