//
//  LiveSystemProviders.swift
//  ASimplePurchaseKitProject
//
//  Created by Charles Feinn on 6/27/25.
//

import Foundation
import StoreKit

/// The live implementation of `TransactionListenerProvider` that uses `Transaction.updates`.
@MainActor
internal class LiveTransactionListenerProvider: TransactionListenerProvider {
    func listenForTransactions(updateHandler: @escaping @Sendable (VerificationResult<Transaction>) async -> Void) -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                await updateHandler(result)
            }
        }
    }
}

/// The live implementation of `AppStoreSyncer` that calls `AppStore.sync()`.
@MainActor
internal class LiveAppStoreSyncer: AppStoreSyncer {
    func sync() async throws {
        try await AppStore.sync()
    }
}
