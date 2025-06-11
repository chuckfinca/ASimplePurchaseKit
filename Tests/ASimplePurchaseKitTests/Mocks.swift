//
//  Mocks.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/10/25.
//

import Foundation
import XCTest
import StoreKit
@testable import ASimplePurchaseKit // Use @testable to access internal types

@MainActor
class MockPurchaseProvider: ProductProvider, Purchaser, ReceiptValidator {

    // MARK: - Controllable Test Properties
    
    // Controls what fetchProducts() returns
    var productsResult: Result<[Product], Error> = .success([])
    
    // Controls what purchase() returns
    var purchaseResult: Result<Transaction, Error> = .failure(PurchaseError.unknown)
    
    // Controls what validate() and checkCurrentEntitlements() return
    var entitlementResult: Result<EntitlementStatus, Error> = .success(.notSubscribed)

    // MARK: - Call Counts for Assertions
    
    var fetchProductsCallCount = 0
    var purchaseCallCount = 0
    var validateCallCount = 0
    var checkCurrentEntitlementsCallCount = 0

    // MARK: - Protocol Implementations
    
    func fetchProducts(for ids: [String]) async throws -> [Product] {
        fetchProductsCallCount += 1
        return try productsResult.get()
    }

    func purchase(_ product: Product) async throws -> Transaction {
        purchaseCallCount += 1
        return try purchaseResult.get()
    }

    func validate(transaction: Transaction) async throws -> EntitlementStatus {
        validateCallCount += 1
        return try entitlementResult.get()
    }

    func checkCurrentEntitlements() async throws -> EntitlementStatus {
        checkCurrentEntitlementsCallCount += 1
        return try entitlementResult.get()
    }

    // MARK: - Test Helper
    
    func reset() {
        productsResult = .success([])
        purchaseResult = .failure(PurchaseError.unknown)
        entitlementResult = .success(.notSubscribed)
        
        fetchProductsCallCount = 0
        purchaseCallCount = 0
        validateCallCount = 0
        checkCurrentEntitlementsCallCount = 0
    }
}
