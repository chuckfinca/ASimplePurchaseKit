//
//  PurchaseError.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn on 6/10/25.
//

import Foundation
import StoreKit

public enum PurchaseError: Error, LocalizedError, Equatable {
    case unknown
    case productsNotFound
    case purchasePending
    case purchaseCancelled
    case purchaseFailed(SKError.Code)
    case verificationFailed(VerificationResult<Any>.VerificationError)
    case userNotEntitled
    case missingEntitlement
    
    public var errorDescription: String? {
        switch self {
        case .unknown:
            return "An unknown error occurred."
        case .productsNotFound:
            return "The requested products could not be found."
        case .purchasePending:
            return "A purchase is already in progress. Please wait."
        case .purchaseCancelled:
            return "You cancelled the purchase."
        case .purchaseFailed(let code):
            return "The purchase failed with error: \(code.rawValue)."
        case .verificationFailed:
            return "The purchase could not be verified."
        case .userNotEntitled:
            return "You do not have an active subscription."
        case .missingEntitlement:
            return "Could not determine subscription status."
        }
    }
}
