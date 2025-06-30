//
//  PurchaseConfig.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/10/25.
//

import Foundation

/// Configuration structure for initializing PurchaseService.
///
/// Use this struct to configure which products should be available for purchase
/// and to control logging behavior.
///
/// ## Example
/// ```swift
/// let config = PurchaseConfig(
///     productIDs: ["premium_monthly", "premium_yearly"],
///     enableLogging: true
/// )
/// let purchaseService = PurchaseService(config: config)
/// ```
public struct PurchaseConfig {
    /// A list of product identifiers to be fetched from the App Store.
    ///
    /// These should match the Product IDs you set up in App Store Connect
    /// and in your Xcode `.storekit` test file.
    ///
    /// - Important: Product IDs are case-sensitive and must exactly match
    ///   those configured in App Store Connect.
    public let productIDs: [String]
    
    /// Controls whether detailed logging is enabled for purchase operations.
    ///
    /// When `true`, the PurchaseService will output detailed logs for debugging.
    /// Set to `false` in production to reduce log verbosity.
    ///
    /// - Note: Debug-level logs are automatically disabled in production
    ///   regardless of this setting.
    public let enableLogging: Bool

    /// Creates a new purchase configuration.
    ///
    /// - Parameters:
    ///   - productIDs: Array of product identifiers to fetch from the App Store.
    ///     These must match the Product IDs configured in App Store Connect.
    ///   - enableLogging: Whether to enable detailed logging. Defaults to `true`.
    public init(productIDs: [String], enableLogging: Bool = true) {
        self.productIDs = productIDs
        self.enableLogging = enableLogging
    }
}
