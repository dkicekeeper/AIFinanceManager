//
//  ReminderPickerView.swift
//  AIFinanceManager
//
//  Reusable multi-select reminder picker component
//  Extracted from SubscriptionEditView for reusability
//

import SwiftUI

/// Multi-select reminder picker with preset offset options
/// Shows toggle list for reminder days before due date (1, 3, 7, 30 days)
struct ReminderPickerView: View {
    @Binding var selectedOffsets: Set<Int>
    let availableOffsets: [Int]
    let title: String

    init(
        selectedOffsets: Binding<Set<Int>>,
        availableOffsets: [Int] = [1, 3, 7, 30],
        title: String = String(localized: "subscription.reminders")
    ) {
        self._selectedOffsets = selectedOffsets
        self.availableOffsets = availableOffsets
        self.title = title
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                SectionHeaderView(title, style: .compact)
                Spacer()
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xs)

            // Reminder toggles
            VStack(spacing: 0) {
                ForEach(availableOffsets, id: \.self) { offset in
                    VStack(spacing: 0) {
                        Toggle(
                            reminderText(for: offset),
                            isOn: Binding(
                                get: { selectedOffsets.contains(offset) },
                                set: { isOn in
                                    if isOn {
                                        selectedOffsets.insert(offset)
                                    } else {
                                        selectedOffsets.remove(offset)
                                    }
                                }
                            )
                        )
                        .padding(AppSpacing.md)

                        // Divider (except for last item)
                        if offset != availableOffsets.last {
                            Divider()
                                .padding(.leading, AppSpacing.md)
                        }
                    }
                }
            }
            .background(AppColors.cardBackground)
            .clipShape(.rect(cornerRadius: AppRadius.md))
        }
    }

    // MARK: - Helper Methods

    /// Generates localized reminder text for given offset
    /// Returns: "1 day before", "3 days before", etc.
    private func reminderText(for offset: Int) -> String {
        if offset == 1 {
            return String(localized: "reminder.dayBefore.one")
        } else {
            return String(localized: "reminder.daysBefore.\(offset)")
        }
    }
}

// MARK: - Previews

#Preview("No Selection") {
    @Previewable @State var selectedOffsets: Set<Int> = []

    return ReminderPickerView(selectedOffsets: $selectedOffsets)
        .padding()
}

#Preview("With Selection") {
    @Previewable @State var selectedOffsets: Set<Int> = [1, 7]

    return ReminderPickerView(selectedOffsets: $selectedOffsets)
        .padding()
}

#Preview("Custom Offsets") {
    @Previewable @State var selectedOffsets: Set<Int> = [1]

    return ReminderPickerView(
        selectedOffsets: $selectedOffsets,
        availableOffsets: [1, 2, 5, 14],
        title: "Custom Reminders"
    )
    .padding()
}

#Preview("In Form Context") {
    @Previewable @State var offsets: Set<Int> = [3, 7]

    return ScrollView {
        VStack(spacing: AppSpacing.xxl) {
            // Form section above
            VStack(spacing: 0) {
                TextField("Subscription Name", text: .constant("Netflix"))
                    .padding(AppSpacing.md)

                Divider()

                TextField("Amount", text: .constant("9.99"))
                    .padding(AppSpacing.md)
            }
            .background(AppColors.cardBackground)
            .clipShape(.rect(cornerRadius: AppRadius.md))

            // Reminder picker
            ReminderPickerView(selectedOffsets: $offsets)
        }
        .padding()
    }
}
