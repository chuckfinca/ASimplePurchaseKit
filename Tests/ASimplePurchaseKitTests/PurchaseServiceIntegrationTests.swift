//
//  PurchaseServiceIntegrationTests.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/13/25.
//

import XCTest
import Combine
import StoreKitTest
@testable import ASimplePurchaseKit

@MainActor
final class PurchaseServiceIntegrationTests: XCTestCase {

    var session: SKTestSession!
    var sut: PurchaseService!
    var config: PurchaseConfig!
    var cancellables: Set<AnyCancellable>!

    let monthlyProductID = "com.asimplepurchasekit.pro.monthly"
    let lifetimeProductID = "com.asimplepurchasekit.pro.lifetime"

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = true
        session.clearTransactions()

        config = PurchaseConfig(productIDs: [monthlyProductID, lifetimeProductID])
        sut = PurchaseService(config: config)

        cancellables = []

        // Wait for products to be fetched before running any test.
        let expectation = XCTestExpectation(description: "Wait for products to load")
        sut.$availableProducts
            .dropFirst()
            .sink { products in
            if !products.isEmpty {
                expectation.fulfill()
            }
        }
            .store(in: &cancellables)
        await fulfillment(of: [expectation], timeout: 5.0)
    }

    override func tearDown() async throws {
        session.clearTransactions()
        session = nil
        sut = nil
        config = nil
        cancellables = nil
    }

    func test_purchaseMonthlySubscription_succeeds() async throws {
        let expectation = XCTestExpectation(description: "Entitlement status should become active.")
        sut.$entitlementStatus
            .sink { status in
            if status.isActive {
                expectation.fulfill()
            }
        }
            .store(in: &cancellables)

        await sut.purchase(productID: monthlyProductID)

        await fulfillment(of: [expectation], timeout: 5.0)

        XCTAssertTrue(sut.entitlementStatus.isActive)
        XCTAssertNil(sut.lastError)
        
        let allTransactions = Transaction.all.first // <-- Correct way to get transactions
        XCTAssertNotNil(allTransactions) // Or more specific checks
    }

    func test_purchase_whenCancelledByUser_setsCancelledError() async {
        session.failTransactionsEnabled = true
        session.failureError = .paymentCancelled

        await sut.purchase(productID: monthlyProductID)

        XCTAssertFalse(sut.entitlementStatus.isActive)
        XCTAssertEqual(sut.lastError, .purchaseCancelled)
        
        let allTransactions = Transaction.all.first // <-- Correct way to get transactions
        XCTAssertNotNil(allTransactions)
    }
}
