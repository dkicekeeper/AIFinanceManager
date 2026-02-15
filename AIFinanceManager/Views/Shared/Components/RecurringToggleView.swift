//
//  RecurringToggleView.swift
//  AIFinanceManager
//
//  Reusable recurring menu picker for transactions
//  Updated to use MenuPickerRow with "Never" option
//

import SwiftUI

struct RecurringToggleView: View {
    @Binding var isRecurring: Bool
    @Binding var selectedFrequency: RecurringFrequency
    let title: String
    let icon: String

    // Internal state for menu picker
    @State private var recurringOption: RecurringOption

    init(
        isRecurring: Binding<Bool>,
        selectedFrequency: Binding<RecurringFrequency>,
        title: String = String(localized: "transactionForm.makeRecurring"),
        icon: String = "repeat"
    ) {
        self._isRecurring = isRecurring
        self._selectedFrequency = selectedFrequency
        self.title = title
        self.icon = icon

        // Initialize internal state based on isRecurring
        let initialOption: RecurringOption = isRecurring.wrappedValue
            ? .frequency(selectedFrequency.wrappedValue)
            : .never
        self._recurringOption = State(initialValue: initialOption)
    }

    var body: some View {
        MenuPickerRow(
//            icon: icon,
            title: title,
            selection: Binding(
                get: { recurringOption },
                set: { newValue in
                    recurringOption = newValue
                    switch newValue {
                    case .never:
                        isRecurring = false
                    case .frequency(let freq):
                        isRecurring = true
                        selectedFrequency = freq
                    }
                }
            )
        )
        .onChange(of: isRecurring) { oldValue, newValue in
            // Sync external isRecurring changes back to recurringOption
            if !newValue && recurringOption != .never {
                recurringOption = .never
            } else if newValue, case .never = recurringOption {
                recurringOption = .frequency(selectedFrequency)
            }
        }
    }
}

#Preview("Never Selected") {
    @Previewable @State var isRecurring = false
    @Previewable @State var selectedFrequency: RecurringFrequency = .monthly

    VStack(spacing: AppSpacing.lg) {
        Text("isRecurring: \(isRecurring ? "true" : "false")")
            .font(AppTypography.caption)

        FormSection(style: .card) {
            RecurringToggleView(
                isRecurring: $isRecurring,
                selectedFrequency: $selectedFrequency
            )
        }
    }
    .padding()
}

#Preview("Monthly Selected") {
    @Previewable @State var isRecurring = true
    @Previewable @State var selectedFrequency: RecurringFrequency = .monthly

    VStack(spacing: AppSpacing.lg) {
        Text("isRecurring: \(isRecurring ? "true" : "false"), frequency: \(selectedFrequency.displayName)")
            .font(AppTypography.caption)

        FormSection(style: .card) {
            RecurringToggleView(
                isRecurring: $isRecurring,
                selectedFrequency: $selectedFrequency
            )
        }
    }
    .padding()
}
