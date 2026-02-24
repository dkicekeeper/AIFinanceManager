//
//  AmountInputFormatting.swift
//  AIFinanceManager
//
//  Shared static utilities for amount input components.
//  Single source of truth for string cleaning, display formatting,
//  and dynamic font-size calculation used by AmountInputView
//  and AnimatedAmountInput.
//

import SwiftUI

// MARK: - AmountInputFormatting

/// Static formatting utilities shared between amount input components.
///
/// Centralises formatter instances, string cleaning, display formatting,
/// and dynamic font-size calculation so both `AmountInputView` and
/// `AnimatedAmountInput` use identical mechanics.
enum AmountInputFormatting {

    // MARK: - Formatter

    /// Primary formatter: groups digits with spaces, up to 2 decimal places.
    /// Created once per app lifetime — safe to share across views.
    static let displayFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        f.groupingSeparator = " "
        f.usesGroupingSeparator = true
        f.decimalSeparator = "."
        return f
    }()

    // MARK: - Font Measurement

    /// Reference UIFont used exclusively for text-width measurement.
    /// Falls back to system bold if "Inter" PostScript name doesn't match.
    static let measureFont: UIFont =
        UIFont(name: "Inter", size: 56) ?? UIFont.systemFont(ofSize: 56, weight: .bold)

    static let measureAttributes: [NSAttributedString.Key: Any] = [.font: measureFont]

    // MARK: - String Cleaning

    /// Normalises the decimal separator and strips all non-numeric characters.
    /// Single source of truth — used for both keyboard input and clipboard paste.
    static func cleanAmountString(_ text: String) -> String {
        text
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
    }

    // MARK: - Display Formatting

    /// Converts a raw amount string into a user-facing display string.
    ///
    /// Rules:
    /// - Empty or zero input → `"0"`
    /// - Non-parseable input → cleaned raw string (preserves typing in progress)
    /// - Valid Decimal → formatted with `displayFormatter`; falls back to `formatLargeNumber`
    static func displayAmount(for text: String) -> String {
        let cleaned = cleanAmountString(text)

        if cleaned.isEmpty { return "0" }

        guard let decimal = Decimal(string: cleaned) else { return cleaned }

        let number = NSDecimalNumber(decimal: decimal)
        if number.compare(NSDecimalNumber.zero) == .orderedSame { return "0" }

        if let formatted = displayFormatter.string(from: number) { return formatted }
        return formatLargeNumber(decimal)
    }

    /// Formats a Decimal that `displayFormatter` could not handle,
    /// grouping the integer part with spaces.
    static func formatLargeNumber(_ decimal: Decimal) -> String {
        if let s = displayFormatter.string(from: NSDecimalNumber(decimal: decimal)) { return s }
        let string = String(describing: decimal)
        guard string.contains(".") else { return groupDigits(string) }
        let parts = string.components(separatedBy: ".")
        return "\(groupDigits(parts[0])).\(parts[1].prefix(2))"
    }

    /// Groups digits in an integer string with space separators every 3 digits.
    static func groupDigits(_ s: String) -> String {
        var result = ""
        for (i, char) in s.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { result = " " + result }
            result = String(char) + result
        }
        return result
    }

    // MARK: - Dynamic Font Sizing

    /// Calculates the optimal font size so `displayAmount` fits within `containerWidth`.
    ///
    /// Returns `baseFontSize` unchanged when:
    /// - `containerWidth` is zero (layout not yet determined)
    /// - `displayAmount` is `"0"` (placeholder — always fits)
    ///
    /// Otherwise scales down proportionally, clamped to a minimum of 24 pt.
    ///
    /// - Parameters:
    ///   - displayAmount: The formatted string currently shown.
    ///   - containerWidth: Available width of the container view.
    ///   - baseFontSize: Maximum (default) font size.
    /// - Returns: Font size in the range `[24, baseFontSize]`.
    static func calculateFontSize(
        for displayAmount: String,
        containerWidth: CGFloat,
        baseFontSize: CGFloat
    ) -> CGFloat {
        guard containerWidth > 0, displayAmount != "0" else { return baseFontSize }

        let maxWidth = containerWidth - (AppSpacing.lg * 2) - 20
        let textWidth = (displayAmount as NSString).size(withAttributes: measureAttributes).width

        guard textWidth > maxWidth, maxWidth > 0 else { return baseFontSize }

        let scale = maxWidth / textWidth
        return max(24, min(baseFontSize, baseFontSize * scale))
    }
}
