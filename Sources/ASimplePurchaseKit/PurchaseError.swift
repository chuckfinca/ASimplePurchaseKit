// File: Sources/ASimplePurchaseKit/PurchaseError.swift
// (Assuming this is the path based on your tree structure)

import Foundation
import StoreKit

public enum PurchaseError: Error, LocalizedError, Equatable {
    case unknown
    case productsNotFound
    case purchasePending // This can also mean an existing operation is in progress
    case purchaseCancelled
    case purchaseFailed(SKError.Code) // StoreKit error during purchase
    case verificationFailed(VerificationResult<Transaction>.VerificationError)
    case userNotEntitled // General entitlement failure
    case missingEntitlement // Could not determine status, e.g. from checkCurrentEntitlements
    case productNotAvailableForPurchase(productID: String) // Specific error if product not in availableProducts
    case underlyingError(Error) // Wrapper for other errors encountered

    public var errorDescription: String? {
        switch self {
        case .unknown:
            return "An unknown error occurred."
        case .productsNotFound:
            return "The requested products could not be found."
        case .purchasePending:
            return "A purchase operation is already in progress or requires user action. Please wait."
        case .purchaseCancelled:
            return "You cancelled the purchase."
        case .purchaseFailed(let code):
            return "The purchase failed with StoreKit error: \(code.rawValue)."
        case .verificationFailed:
            return "The purchase could not be verified."
        case .userNotEntitled:
            return "You do not have an active entitlement."
        case .missingEntitlement:
            return "Could not determine entitlement status."
        case .productNotAvailableForPurchase(let productID):
            return "Product with ID '\(productID)' is not available for purchase at this time."
        case .underlyingError(let error):
            return "An underlying error occurred: \(error.localizedDescription)"
        }
    }
    
    public static func == (lhs: PurchaseError, rhs: PurchaseError) -> Bool {
        switch (lhs, rhs) {
        case (.unknown, .unknown): return true
        case (.productsNotFound, .productsNotFound): return true
        case (.purchasePending, .purchasePending): return true
        case (.purchaseCancelled, .purchaseCancelled): return true
        case (.purchaseFailed(let lCode), .purchaseFailed(let rCode)): return lCode == rCode
        case (.verificationFailed(let lError), .verificationFailed(let rError)):
            // VerificationError itself is not Equatable. Compare descriptions or types.
            return String(describing: lError) == String(describing: rError)
        case (.userNotEntitled, .userNotEntitled): return true
        case (.missingEntitlement, .missingEntitlement): return true
        case (.productNotAvailableForPurchase(let lID), .productNotAvailableForPurchase(let rID)): return lID == rID
        case (.underlyingError(let lError), .underlyingError(let rError)):
            // If both are NSErrors, compare domain, code.
            // Localized description can be too variable or localized for reliable test comparison.
            if let lnsError = lError as? NSError, let rnsError = rError as? NSError {
                return lnsError.domain == rnsError.domain &&
                       lnsError.code == rnsError.code
                // If you also need to compare userInfo for NSError, that would be more complex.
                // For test purposes, domain and code are often sufficient for identity.
            }
            // Fallback for other error types: compare their string descriptions.
            // Using String(describing:) can be more stable than localizedDescription for some error types.
            return String(describing: lError) == String(describing: rError)
        default: return false
        }
    }
}

// PurchaseFailure struct remains the same
public struct PurchaseFailure: Equatable, Sendable {
    public let error: PurchaseError
    public let productID: String?
    public let timestamp: Date
    public let operation: String

    public init(error: PurchaseError, productID: String? = nil, operation: String, timestamp: Date = Date()) {
        self.error = error
        self.productID = productID
        self.operation = operation
        self.timestamp = timestamp
    }
    
    public static func == (lhs: PurchaseFailure, rhs: PurchaseFailure) -> Bool {
        return lhs.error == rhs.error &&
               lhs.productID == rhs.productID &&
               lhs.operation == rhs.operation &&
               // For Date, ensure a tolerance if exact match is problematic in tests
               // For now, direct equality is fine if timestamps are set carefully.
               lhs.timestamp == rhs.timestamp
    }
}
