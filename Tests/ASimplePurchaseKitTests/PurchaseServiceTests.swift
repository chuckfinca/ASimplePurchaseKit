//
//  PurchaseServiceTests.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/10/25.
//

import XCTest
import Combine
import StoreKit
@testable import ASimplePurchaseKit

@MainActor
final class PurchaseServiceTests: XCTestCase {

    var sut: PurchaseService!
    var mockProvider: MockPurchaseProvider!
    var cancellables: Set<AnyCancellable>!

    let testProductIDs = ["com.example.pro.monthly"]

    override func setUp() async throws {

        cancellables = []
        mockProvider = MockPurchaseProvider()
        
        // Initialize the SUT with the mock provider
        sut = PurchaseService(
            productIDs: testProductIDs,
            productProvider: mockProvider,
            purchaser: mockProvider,
            receiptValidator: mockProvider,
            isUnitTesting: true
        )
    }

    override func tearDown() async throws {
        sut = nil
        mockProvider = nil
        cancellables = nil
    }

    // Test that the initializer calls the correct methods
    func test_initialization_fetchesProductsAndUpdatesEntitlements() async {
        let expectation = XCTestExpectation(description: "Wait for init tasks to complete.")
        
        // We just need to wait long enough for the async tasks in init to run.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertEqual(mockProvider.fetchProductsCallCount, 1)
        XCTAssertEqual(mockProvider.checkCurrentEntitlementsCallCount, 1)
    }
    
    // Test a failure case that is easy to mock
    func test_purchase_whenProductIsNotFound_setsProductsNotFoundError() async {
        // ARRANGE
        // The service's availableProducts array is empty by default.
        XCTAssertTrue(sut.availableProducts.isEmpty)
        
        // ACT
        await sut.purchase(productID: "some.unknown.id")
        
        // ASSERT
        XCTAssertEqual(sut.lastError, .productsNotFound)
        XCTAssertFalse(sut.isPurchasing)
        XCTAssertEqual(mockProvider.purchaseCallCount, 0, "The purchase method should not be called if the product isn't found.")
    }
    
    func test_restorePurchases_callsSyncAndUpdatesEntitlements() async {
        // ARRANGE
        mockProvider.entitlementResult = .success(.subscribed(expires: nil, isInGracePeriod: false))
        
        // ACT
        await sut.restorePurchases() // We can't mock AppStore.sync(), but we can test what happens after.
        
        // ASSERT
        // restorePurchases calls updateEntitlementStatus, which calls checkCurrentEntitlements
        XCTAssertEqual(mockProvider.checkCurrentEntitlementsCallCount, 2, "Should be called once on init and once on restore")
        XCTAssertEqual(sut.entitlementStatus, .subscribed(expires: nil, isInGracePeriod: false))
    }
}
