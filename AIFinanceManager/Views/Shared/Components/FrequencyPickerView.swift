//
//  FrequencyPickerView.swift
//  AIFinanceManager
//
//  Dedicated frequency picker for recurring transactions/subscriptions
//  Encapsulates RecurringFrequency selection logic
//

import SwiftUI

/// Frequency picker with multiple display styles
/// Encapsulates RecurringFrequency enum and provides consistent UI
struct FrequencyPickerView: View {
    @Binding var selection: RecurringFrequency
    let title: String
    let style: Style

    enum Style {
        /// Horizontal segmented control (default)
        case segmented

        /// Vertical list with radio buttons
        case list

        /// Compact dropdown menu
        case menu
    }

    init(
        selection: Binding<RecurringFrequency>,
        title: String = String(localized: "common.frequency"),
        style: Style = .segmented
    ) {
        self._selection = selection
        self.title = title
        self.style = style
    }

    var body: some View {
        switch style {
        case .segmented:
            segmentedStyle
        case .list:
            listStyle
        case .menu:
            menuStyle
        }
    }

    // MARK: - Style Variants

    private var segmentedStyle: some View {
        VStack(spacing: AppSpacing.sm) {
            if !title.isEmpty {
                HStack {
                    Text(title)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                }
            }

            SegmentedPickerView(
                title: "",
                selection: $selection,
                options: RecurringFrequency.allCases.map {
                    (label: $0.displayName, value: $0)
                }
            )
        }
    }

    private var listStyle: some View {
        VStack(spacing: 0) {
            ForEach(RecurringFrequency.allCases, id: \.self) { frequency in
                Button {
                    HapticManager.selection()
                    selection = frequency
                } label: {
                    HStack {
                        Text(frequency.displayName)
                            .foregroundStyle(AppColors.textPrimary)

                        Spacer()

                        if selection == frequency {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppColors.accent)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                    .padding(AppSpacing.md)
                }
                .buttonStyle(.plain)

                if frequency != RecurringFrequency.allCases.last {
                    Divider()
                        .padding(.leading, AppSpacing.md)
                }
            }
        }
    }

    private var menuStyle: some View {
        Picker(title, selection: $selection) {
            ForEach(RecurringFrequency.allCases, id: \.self) { frequency in
                Text(frequency.displayName).tag(frequency)
            }
        }
        .pickerStyle(.menu)
    }
}

// MARK: - Previews

#Preview("Segmented Style") {
    @Previewable @State var frequency: RecurringFrequency = .monthly

    return FrequencyPickerView(
        selection: $frequency,
        style: .segmented
    )
    .padding()
}

#Preview("List Style") {
    @Previewable @State var frequency: RecurringFrequency = .weekly

    return FrequencyPickerView(
        selection: $frequency,
        title: "Select Frequency",
        style: .list
    )
    .background(AppColors.cardBackground)
    .clipShape(.rect(cornerRadius: AppRadius.md))
    .padding()
}

#Preview("Menu Style") {
    @Previewable @State var frequency: RecurringFrequency = .daily

    return FrequencyPickerView(
        selection: $frequency,
        style: .menu
    )
    .padding()
}

#Preview("In Form Context") {
    @Previewable @State var freq: RecurringFrequency = .monthly

    return VStack(spacing: AppSpacing.xxl) {
        // Form section
        VStack(spacing: 0) {
            TextField("Description", text: .constant("Netflix"))
                .padding(AppSpacing.md)

            Divider()

            TextField("Amount", text: .constant("9.99"))
                .padding(AppSpacing.md)
        }
        .background(AppColors.cardBackground)
        .clipShape(.rect(cornerRadius: AppRadius.md))

        // Frequency picker
        VStack(spacing: 0) {
            FrequencyPickerView(
                selection: $freq,
                style: .segmented
            )
            .padding(AppSpacing.md)
        }
        .background(AppColors.cardBackground)
        .clipShape(.rect(cornerRadius: AppRadius.md))
    }
    .padding()
}

#Preview("All Styles Comparison") {
    @Previewable @State var frequency: RecurringFrequency = .monthly

    return ScrollView {
        VStack(alignment: .leading, spacing: AppSpacing.xxl) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Segmented Style")
                    .font(AppTypography.h4)

                FrequencyPickerView(
                    selection: $frequency,
                    style: .segmented
                )
            }

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("List Style")
                    .font(AppTypography.h4)

                FrequencyPickerView(
                    selection: $frequency,
                    style: .list
                )
                .background(AppColors.cardBackground)
                .clipShape(.rect(cornerRadius: AppRadius.md))
            }

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Menu Style")
                    .font(AppTypography.h4)

                FrequencyPickerView(
                    selection: $frequency,
                    style: .menu
                )
            }
        }
        .padding()
    }
}
