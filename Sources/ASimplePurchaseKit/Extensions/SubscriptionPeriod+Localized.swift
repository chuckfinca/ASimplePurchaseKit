//
//  SubscriptionPeriod+Localized.swift
//  ASimplePurchaseKitProject
//
//  Created by Charles Feinn on 6/24/25.
//

import StoreKit

public extension Product.SubscriptionPeriod {

    /// Provides a user-friendly, localized description of the subscription period.
    /// For example, a period of 1 month will be "1 month", 3 months "3 months", 1 year "1 year".
    /// This uses `DateComponentsFormatter` for localization according to the user's locale.
    var localizedDescription: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .weekOfMonth, .month, .year]
        formatter.unitsStyle = .full // e.g., "1 week", "2 months", "1 year"
        formatter.maximumUnitCount = 1 // Shows only the largest unit, e.g. "1 month" not "4 weeks"

        var components = DateComponents()
        switch self.unit {
        case .day:
            components.day = self.value
        case .week:
            if self.value == 1 {
                components.weekOfMonth = self.value
            } else {
                components.day = self.value * 7 // e.g. "14 days"
            }
        case .month:
            components.month = self.value
        case .year:
            components.year = self.value
        @unknown default:
            // Fallback for unknown units
            return "\(self.value) \(self.unitDescription)" // Use a helper for unit string
        }
        
        // If formatter fails (e.g., components are zero, which shouldn't happen here), provide a fallback.
        return formatter.string(from: components) ?? "\(self.value) \(self.unitDescription)"
    }

    /// A simple description of the unit, primarily for fallback.
    private var unitDescription: String {
        switch self.unit {
        case .day: return self.value == 1 ? "day" : "days"
        case .week: return self.value == 1 ? "week" : "weeks"
        case .month: return self.value == 1 ? "month" : "months"
        case .year: return self.value == 1 ? "year" : "years"
        @unknown default: return "\(self.unit)"
        }
    }
}
