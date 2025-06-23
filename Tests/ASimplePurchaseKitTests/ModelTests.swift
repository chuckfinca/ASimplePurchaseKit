
import XCTest
import Combine
import StoreKit
@testable import ASimplePurchaseKit

@MainActor
final class ModelTests: XCTestCase {

// For PurchaseFailure
    func test_purchaseFailure_equality() {
        let date = Date()
        // Identical
        let failure1A = PurchaseFailure(error: .purchaseCancelled, productID: "test", operation: "purchase", timestamp: date)
        let failure1B = PurchaseFailure(error: .purchaseCancelled, productID: "test", operation: "purchase", timestamp: date)
        XCTAssertEqual(failure1A, failure1B)

        // Different error
        let failure2 = PurchaseFailure(error: .productsNotFound, productID: "test", operation: "purchase", timestamp: date)
        XCTAssertNotEqual(failure1A, failure2)

        // Different productID
        let failure3 = PurchaseFailure(error: .purchaseCancelled, productID: "test-diff", operation: "purchase", timestamp: date)
        XCTAssertNotEqual(failure1A, failure3)

        // Different operation
        let failure4 = PurchaseFailure(error: .purchaseCancelled, productID: "test", operation: "restore", timestamp: date)
        XCTAssertNotEqual(failure1A, failure4)

        // Different timestamp
        let failure5 = PurchaseFailure(error: .purchaseCancelled, productID: "test", operation: "purchase", timestamp: date.addingTimeInterval(1))
        XCTAssertNotEqual(failure1A, failure5) // Assuming exact timestamp comparison is intended

        // Test .underlyingError (basic comparison by localizedDescription)
        let nsError1 = NSError(domain: "domain", code: 1, userInfo: [NSLocalizedDescriptionKey: "desc1"])
        let nsError2 = NSError(domain: "domain", code: 1, userInfo: [NSLocalizedDescriptionKey: "desc1"])
        let nsError3 = NSError(domain: "domain", code: 2, userInfo: [NSLocalizedDescriptionKey: "desc2"])

        let failure6A = PurchaseFailure(error: .underlyingError(nsError1), operation: "op")
        let failure6B = PurchaseFailure(error: .underlyingError(nsError2), operation: "op") // Same desc
        let failure6C = PurchaseFailure(error: .underlyingError(nsError3), operation: "op") // Diff desc
        XCTAssertEqual(failure6A, failure6B)
        XCTAssertNotEqual(failure6A, failure6C)

        // Test .verificationFailed (comparison by string description)
        // This is hard to test without actual VerificationError instances, which are not public to create.
        // You might need to refine how PurchaseError.verificationFailed == is implemented or tested
        // if you need deep verification error equality. For now, the string description check is a pragmatic approach.
        // For the sake of a simple test, we assume the string descriptions would be different for different underlying errors.
        // class MockVerificationError: Error, LocalizedError { var errorDescription: String? }
        // let vError1 = VerificationResult<Transaction>.VerificationError(...) // Cannot construct
    }

// For EntitlementStatus
    func test_entitlementStatus_isActive() {
        XCTAssertTrue(EntitlementStatus.subscribed(expires: Date().addingTimeInterval(1000), isInGracePeriod: false).isActive)
        XCTAssertTrue(EntitlementStatus.subscribed(expires: Date().addingTimeInterval(1000), isInGracePeriod: true).isActive)
        XCTAssertTrue(EntitlementStatus.subscribed(expires: nil, isInGracePeriod: false).isActive) // Non-consumable

        XCTAssertFalse(EntitlementStatus.notSubscribed.isActive)
        XCTAssertFalse(EntitlementStatus.unknown.isActive)
    }
}
