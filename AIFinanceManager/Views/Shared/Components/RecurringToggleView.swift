//
//  RecurringToggleView.swift
//  AIFinanceManager
//
//  Reusable recurring toggle with frequency picker
//

import SwiftUI

struct RecurringToggleView: View {
    @Binding var isRecurring: Bool
    @Binding var selectedFrequency: RecurringFrequency
    let toggleTitle: String
    let frequencyTitle: String
    
    init(
        isRecurring: Binding<Bool>,
        selectedFrequency: Binding<RecurringFrequency>,
        toggleTitle: String = String(localized: "transactionForm.makeRecurring"),
        frequencyTitle: String = String(localized: "transaction.frequency")
    ) {
        self._isRecurring = isRecurring
        self._selectedFrequency = selectedFrequency
        self.toggleTitle = toggleTitle
        self.frequencyTitle = frequencyTitle
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Toggle(toggleTitle, isOn: $isRecurring)
                .font(AppTypography.body)

            if isRecurring {
                SegmentedPickerView(
                    title: "",
                    selection: $selectedFrequency,
                    options: RecurringFrequency.allCases.map { frequency in
                        (label: frequency.displayName, value: frequency)
                    }
                )
                .font(AppTypography.body)
                .padding(.top, AppSpacing.sm)
            }
        }
        .padding(AppSpacing.lg)
//        .background(.primary .opacity(0.05))
    }
}

#Preview {
    @Previewable @State var isRecurring = false
    @Previewable @State var selectedFrequency: RecurringFrequency = .monthly
    
    return RecurringToggleView(
        isRecurring: $isRecurring,
        selectedFrequency: $selectedFrequency
    )
    .padding()
}
