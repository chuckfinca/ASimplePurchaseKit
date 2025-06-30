//
//  EntitlementStatus.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/10/25.
//

import Foundation

/// Represents the user's current entitlement status for purchases and subscriptions.
///
/// This enum tracks whether a user has active subscriptions and provides
/// details about subscription expiration and grace periods.
///
/// ## Usage
/// ```swift
/// switch purchaseService.entitlementStatus {
/// case .unknown:
///     // Status hasn't been determined yet
/// case .notSubscribed:
///     // User has no active subscriptions
/// case .subscribed(let expires, let isInGracePeriod):
///     // User has an active subscription
///     if isInGracePeriod {
///         // Show grace period UI
///     }
/// }
/// ```
public enum EntitlementStatus: Equatable, Sendable {
    /// The entitlement status cannot be determined.
    ///
    /// This is the initial state before any entitlement checks are performed,
    /// or when an error prevents status determination.
    case unknown
    
    /// The user has no active subscriptions or entitlements.
    case notSubscribed
    
    /// The user has an active subscription.
    ///
    /// - Parameters:
    ///   - expires: The expiration date of the subscription, if available.
    ///     `nil` for lifetime purchases or when expiration cannot be determined.
    ///   - isInGracePeriod: Whether the subscription is currently in a grace period.
    ///     Grace periods allow continued access even after payment issues.
    case subscribed(expires: Date?, isInGracePeriod: Bool)

    /// Whether the user currently has active entitlements.
    ///
    /// Returns `true` for the `.subscribed` case, regardless of grace period status.
    /// Returns `false` for `.unknown` and `.notSubscribed` cases.
    ///
    /// ## Usage
    /// ```swift
    /// if purchaseService.entitlementStatus.isActive {
    ///     // Show premium features
    /// } else {
    ///     // Show subscription prompt
    /// }
    /// ```
    public var isActive: Bool {
        if case .subscribed = self {
            return true
        }
        return false
    }
}
