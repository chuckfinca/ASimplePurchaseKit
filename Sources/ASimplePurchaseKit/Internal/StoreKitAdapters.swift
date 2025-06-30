//
//  StoreKitAdapters.swift
//  ASimplePurchaseKit
//
//  Created by AI
//

import Foundation
import StoreKit

// MARK: - Adapters for StoreKit types to ProductProtocol

@usableFromInline
internal struct StoreKitPromotionalOfferAdapter: PromotionalOfferProtocol, Sendable {
    @usableFromInline
    let offer: Product.SubscriptionOffer

    @usableFromInline
    init(offer: Product.SubscriptionOffer) {
        self.offer = offer
    }

    public var id: String? {
        if #available(iOS 17.4, macOS 14.4, *) { // Check for availability of offer.id
            return offer.id
        }
        return nil // Or some other placeholder if needed for older versions
    }

    public var displayName: String {
        // TODO: Replace with offer.displayName once available in iOS 26
        return "Promo: \(offer.paymentMode) for \(offer.period.value) \(offer.period.unit)"
    }

    public var price: Decimal { offer.price }
    public var displayPrice: String { offer.displayPrice }
    public var paymentMode: Product.SubscriptionOffer.PaymentMode { offer.paymentMode }
    public var period: Product.SubscriptionPeriod { offer.period }
    public var type: Product.SubscriptionOffer.OfferType { offer.type }
}

@usableFromInline
internal struct StoreKitSubscriptionInfoAdapter: SubscriptionInfoProtocol, Sendable {
    @usableFromInline
    let info: Product.SubscriptionInfo

    @usableFromInline
    init(info: Product.SubscriptionInfo) {
        self.info = info
    }

    public var subscriptionGroupID: String { info.subscriptionGroupID }
    public var promotionalOffers: [PromotionalOfferProtocol] {
        info.promotionalOffers.map { StoreKitPromotionalOfferAdapter(offer: $0) }
    }
    public var subscriptionPeriod: Product.SubscriptionPeriod { info.subscriptionPeriod }
}

@usableFromInline
internal struct StoreKitProductAdapter: ProductProtocol, Sendable {

    private let _underlyingStoreKitProduct: Product

    public var underlyingStoreKitProduct: Product? {
        return _underlyingStoreKitProduct
    }

    @usableFromInline
    init(product: Product) {
        self._underlyingStoreKitProduct = product
    }

    public var id: String { _underlyingStoreKitProduct.id }
    public var type: Product.ProductType { _underlyingStoreKitProduct.type }
    public var displayName: String { _underlyingStoreKitProduct.displayName }
    public var description: String { _underlyingStoreKitProduct.description }
    public var displayPrice: String { _underlyingStoreKitProduct.displayPrice }
    public var price: Decimal { _underlyingStoreKitProduct.price }
    public var isFamilyShareable: Bool { _underlyingStoreKitProduct.isFamilyShareable }
    public var subscription: SubscriptionInfoProtocol? {
        _underlyingStoreKitProduct.subscription.map { StoreKitSubscriptionInfoAdapter(info: $0) }
    }
}
