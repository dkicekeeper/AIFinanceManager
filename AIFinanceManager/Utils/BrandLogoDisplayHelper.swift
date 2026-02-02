//
//  BrandLogoDisplayHelper.swift
//  AIFinanceManager
//
//  Created on 2026-02-02
//  Part of: Subscriptions & Recurring Transactions Full Rebuild
//  Purpose: Eliminate duplication of brandId/brandLogo logic (found in 6 places)
//

import Foundation

/// Helper for resolving brand logo display logic
/// Eliminates duplication of brandId prefix checking across multiple components
struct BrandLogoDisplayHelper {

    /// Defines the source of a brand logo for display
    enum LogoSource {
        /// SF Symbol system image (e.g., "star.fill")
        case systemImage(String)

        /// Custom icon from assets (e.g., "netflix")
        case customIcon(String)

        /// Brand logo fetched from logo.dev API
        case brandService(String)

        /// Bank logo from BankLogo model
        case bankLogo(BankLogo)
    }

    /// Resolve the logo source from available data
    /// - Parameters:
    ///   - brandLogo: Optional BankLogo model
    ///   - brandId: Optional brand identifier (may have "sf:" or "icon:" prefix)
    ///   - brandName: Optional brand name for logo.dev API
    /// - Returns: The resolved LogoSource
    static func resolveSource(
        brandLogo: BankLogo? = nil,
        brandId: String? = nil,
        brandName: String? = nil
    ) -> LogoSource {
        // Priority 1: Check brandId for prefixes
        if let brandId = brandId {
            if brandId.hasPrefix("sf:") {
                let iconName = String(brandId.dropFirst(3))
                return .systemImage(iconName)
            } else if brandId.hasPrefix("icon:") {
                let iconName = String(brandId.dropFirst(5))
                return .customIcon(iconName)
            }
            // If brandId exists but has no prefix, treat it as brandName for API
            return .brandService(brandId)
        }

        // Priority 2: Use bankLogo if available
        if let brandLogo = brandLogo {
            return .bankLogo(brandLogo)
        }

        // Priority 3: Use brandName for logo.dev API
        if let brandName = brandName, !brandName.isEmpty {
            return .brandService(brandName)
        }

        // Fallback: Default system image
        return .systemImage("star.fill")
    }

    /// Get the display name for a logo source (for debugging/logging)
    /// - Parameter source: The logo source
    /// - Returns: Human-readable description
    static func displayName(for source: LogoSource) -> String {
        switch source {
        case .systemImage(let name):
            return "System: \(name)"
        case .customIcon(let name):
            return "Custom: \(name)"
        case .brandService(let name):
            return "Brand: \(name)"
        case .bankLogo(let logo):
            return "Bank: \(logo.name)"
        }
    }
}
