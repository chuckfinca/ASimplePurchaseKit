//
//  PurchaseProtocols.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/10/25.
//

import Foundation
import StoreKit

// Protocol for fetching product information
@MainActor
public protocol ProductProvider {
    func fetchProducts(for ids: [String]) async throws -> [Product]
}

// Protocol for handling the purchase flow
@MainActor
public protocol Purchaser {
    func purchase(_ product: Product) async throws -> Transaction
}

// Protocol for validating receipts/transactions
@MainActor
public protocol ReceiptValidator {
    /// Verifies a transaction and returns the current entitlement status.
    func validate(transaction: Transaction) async throws -> EntitlementStatus
    
    /// Checks all current entitlements to determine the user's status.
    func checkCurrentEntitlements() async throws -> EntitlementStatus
}
