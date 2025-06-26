//
//  EntitlementStatus.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/10/25.
//

import Foundation

public enum EntitlementStatus: Equatable, Sendable {
    case unknown
    case notSubscribed
    case subscribed(expires: Date?, isInGracePeriod: Bool)

    public var isActive: Bool {
        if case .subscribed = self {
            return true
        }
        return false
    }
}
