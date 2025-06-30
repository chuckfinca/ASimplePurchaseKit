//
//  PurchaseError.swift
//  ASimplePurchaseKit
//
//  Created by Charles Feinn.
//

import Foundation
import StoreKit

/// Represents errors that can occur during purchase operations.
///
/// This enum provides specific error cases for different purchase scenarios,
/// enabling proper error handling and user feedback.
///
/// ## Usage
/// ```swift
/// do {
///     try await purchaseService.purchase(productID: "premium_monthly")
/// } catch let error as PurchaseError {
///     switch error {
///     case .purchaseCancelled:
///         // Handle user cancellation
///     case .purchaseFailed(let code):
///         // Handle StoreKit failure
///     default:
///         // Handle other errors
///     }
/// }
/// ```
public enum PurchaseError: Error, LocalizedError, Equatable {
    /// An unknown error occurred during the purchase process.
    case unknown
    
    /// The requested products could not be found in the App Store.
    case productsNotFound
    
    /// A purchase operation is already in progress or requires user action.
    ///
    /// This can occur when:
    /// - Another purchase is currently being processed
    /// - A previous purchase requires user intervention
    case purchasePending
    
    /// The user cancelled the purchase.
    case purchaseCancelled
    
    /// The purchase failed with a StoreKit error.
    ///
    /// - Parameter code: The specific StoreKit error code that caused the failure.
    case purchaseFailed(SKError.Code)
    
    /// Transaction verification failed.
    ///
    /// This occurs when the App Store transaction cannot be verified as authentic.
    ///
    /// - Parameter error: The verification error from StoreKit.
    case verificationFailed(VerificationResult<Transaction>.VerificationError)
    
    /// The user does not have an active entitlement.
    ///
    /// This is a general entitlement failure indicating the user lacks
    /// the required subscription or purchase.
    case userNotEntitled
    
    /// Could not determine the user's entitlement status.
    ///
    /// This error occurs when the system cannot verify whether the user
    /// has valid entitlements, often due to network issues or StoreKit problems.
    case missingEntitlement
    
    /// The specified product is not available for purchase.
    ///
    /// This occurs when a product ID is requested that hasn't been fetched
    /// or is not available in the current App Store configuration.
    ///
    /// - Parameter productID: The ID of the product that is not available.
    case productNotAvailableForPurchase(productID: String)
    
    /// Wraps an underlying system error.
    ///
    /// This case is used when the purchase system encounters an error
    /// from another system component (network, StoreKit, etc.).
    ///
    /// - Parameter error: The underlying error that caused the failure.
    case underlyingError(Error)

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
            let lnsError = lError as NSError
            let rnsError = rError as NSError
            return lnsError.domain == rnsError.domain && lnsError.code == rnsError.code
        default: return false
        }
    }
}

/// Represents a purchase failure with contextual information.
///
/// This structure captures not only the error that occurred, but also
/// additional context such as the product ID, timestamp, and operation
/// that was being performed when the error occurred.
///
/// ## Usage
/// ```swift
/// if let failure = purchaseService.lastFailure {
///     print("Purchase failed: \(failure.error.localizedDescription)")
///     print("Operation: \(failure.operation)")
///     if let productID = failure.productID {
///         print("Product ID: \(productID)")
///     }
/// }
/// ```
public struct PurchaseFailure: Equatable, Sendable {
    /// The specific purchase error that occurred.
    public let error: PurchaseError
    
    /// The product ID associated with the failed operation, if applicable.
    public let productID: String?
    
    /// The timestamp when the failure occurred.
    public let timestamp: Date
    
    /// The name of the operation that was being performed when the failure occurred.
    ///
    /// Examples: "fetchProducts", "purchase", "restorePurchases"
    public let operation: String

    /// Creates a new purchase failure record.
    ///
    /// - Parameters:
    ///   - error: The purchase error that occurred.
    ///   - productID: The product ID associated with the failure, if applicable.
    ///   - operation: The operation that was being performed when the failure occurred.
    ///   - timestamp: The time when the failure occurred. Defaults to the current time.
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
            lhs.timestamp == rhs.timestamp
    }
}
