//
//  PurchaseConfig.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/10/25.
//

import Foundation

public struct PurchaseConfig {
    /// A list of product identifiers to be fetched from the App Store.
    /// These should match the Product IDs you set up in App Store Connect
    /// and in your Xcode `.storekit` test file.
    public let productIDs: [String]
    public let isUnitTesting: Bool
    public let enableLogging: Bool // NEW

    public init(productIDs: [String], isUnitTesting: Bool = false, enableLogging: Bool = true) {
        self.productIDs = productIDs
        self.isUnitTesting = isUnitTesting
        self.enableLogging = enableLogging
    }
}