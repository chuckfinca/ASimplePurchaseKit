// File: Tests/ASimplePurchaseKitTests/ModelTests.swift
// (Or wherever you decide to put these model-specific tests)

import XCTest
import StoreKit // For VerificationResult if needed, though not directly used in these examples
@testable import ASimplePurchaseKit

class ModelTests: XCTestCase {

    func test_entitlementStatus_isActive() {
        XCTAssertTrue(EntitlementStatus.subscribed(expires: Date().addingTimeInterval(1000), isInGracePeriod: false).isActive)
        XCTAssertTrue(EntitlementStatus.subscribed(expires: Date().addingTimeInterval(1000), isInGracePeriod: true).isActive)
        XCTAssertTrue(EntitlementStatus.subscribed(expires: nil, isInGracePeriod: false).isActive) // Non-consumable

        XCTAssertFalse(EntitlementStatus.notSubscribed.isActive)
        XCTAssertFalse(EntitlementStatus.unknown.isActive)
    }

    func test_purchaseFailure_equality() {
        let date1 = Date()
        // Use a slightly different date for timestamp checks to ensure it matters
        let date2 = date1.addingTimeInterval(10)


        // Identical
        let failure1A = PurchaseFailure(error: .purchaseCancelled, productID: "test", operation: "purchase", timestamp: date1)
        let failure1B = PurchaseFailure(error: .purchaseCancelled, productID: "test", operation: "purchase", timestamp: date1)
        XCTAssertEqual(failure1A, failure1B, "Identical PurchaseFailure instances should be equal.")

        // Different error
        let failure2 = PurchaseFailure(error: .productsNotFound, productID: "test", operation: "purchase", timestamp: date1)
        XCTAssertNotEqual(failure1A, failure2, "PurchaseFailures with different errors should not be equal.")

        // Different productID
        let failure3 = PurchaseFailure(error: .purchaseCancelled, productID: "test-diff", operation: "purchase", timestamp: date1)
        XCTAssertNotEqual(failure1A, failure3, "PurchaseFailures with different productIDs should not be equal.")

        // Different operation
        let failure4 = PurchaseFailure(error: .purchaseCancelled, productID: "test", operation: "restore", timestamp: date1)
        XCTAssertNotEqual(failure1A, failure4, "PurchaseFailures with different operations should not be equal.")

        // Different timestamp
        let failure5 = PurchaseFailure(error: .purchaseCancelled, productID: "test", operation: "purchase", timestamp: date2)
        XCTAssertNotEqual(failure1A, failure5, "PurchaseFailures with different timestamps should not be equal.")

        // Test .underlyingError with NSErrors
        let nsErrorContent1 = NSError(domain: "domain", code: 1, userInfo: [NSLocalizedDescriptionKey: "desc1"])
        let nsErrorContent2 = NSError(domain: "domain", code: 1, userInfo: [NSLocalizedDescriptionKey: "desc1"]) // Same content
        let nsErrorContent3 = NSError(domain: "domain", code: 2, userInfo: [NSLocalizedDescriptionKey: "desc2"]) // Different content
        let nsErrorContent4 = NSError(domain: "otherDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "desc1"]) // Different domain

        let failure6A = PurchaseFailure(error: .underlyingError(nsErrorContent1), operation: "op", timestamp: date1)
        let failure6B = PurchaseFailure(error: .underlyingError(nsErrorContent2), operation: "op", timestamp: date1) // Should be equal due to content
        let failure6C = PurchaseFailure(error: .underlyingError(nsErrorContent3), operation: "op", timestamp: date1) // Should not be equal
        let failure6D = PurchaseFailure(error: .underlyingError(nsErrorContent4), operation: "op", timestamp: date1) // Should not be equal to 6A

        XCTAssertEqual(failure6A, failure6B, "Failures with NSErrors having same domain, code, and desc should be equal via PurchaseError.Equatable.")
        XCTAssertNotEqual(failure6A, failure6C, "Failures with NSErrors having different content should not be equal.")
        XCTAssertNotEqual(failure6A, failure6D, "Failures with NSErrors having different domains should not be equal.")

        // Test .verificationFailed (equality based on string description of the VerificationError case)
        // This relies on different VerificationError cases producing different string descriptions.
        // Directly creating distinct VerificationResult.VerificationError instances is hard.
        // We test that our PurchaseError.Equatable for .verificationFailed distinguishes them if their descriptions differ.

        // Assuming .invalidSignature and .revokedCertificate produce different String(describing:)
        let purchaseErrorVF1 = PurchaseError.verificationFailed(.invalidSignature)
        let purchaseErrorVF2 = PurchaseError.verificationFailed(.invalidSignature) // Same underlying SK error
        let purchaseErrorVF3 = PurchaseError.verificationFailed(.revokedCertificate) // Different underlying SK error

        let vFailure1 = PurchaseFailure(error: purchaseErrorVF1, operation: "verify", timestamp: date1)
        let vFailure2 = PurchaseFailure(error: purchaseErrorVF2, operation: "verify", timestamp: date1)
        let vFailure3 = PurchaseFailure(error: purchaseErrorVF3, operation: "verify", timestamp: date1)

        XCTAssertEqual(vFailure1, vFailure2, "Verification failures with the same underlying StoreKit verification error type should be equal.")
        XCTAssertNotEqual(vFailure1, vFailure3, "Verification failures with different underlying StoreKit verification error types should not be equal.")
    }
}
