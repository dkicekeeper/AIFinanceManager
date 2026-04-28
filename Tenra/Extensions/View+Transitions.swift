//
//  View+Transitions.swift
//  Tenra
//
//  Shared helper for opt-in `.matchedTransitionSource(id:in:)` — used by row/chip
//  components that may or may not be embedded in a view that drives a zoom
//  transition. Pass nil for either id or namespace to skip the modifier.
//

import SwiftUI

extension View {
    @ViewBuilder
    func matchedTransitionSourceIfPresent(id: String?, namespace: Namespace.ID?) -> some View {
        if let id, let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}
