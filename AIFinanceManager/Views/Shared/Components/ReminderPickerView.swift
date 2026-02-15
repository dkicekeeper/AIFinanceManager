//
//  ReminderPickerView.swift
//  AIFinanceManager
//
//  Reusable reminder picker using MenuPickerRow
//  Updated to use single-select menu with "No reminder" option
//

import SwiftUI

/// Wrapper around MenuPickerRow for reminder selection
/// Converts between Set<Int> (old API) and ReminderOption (new menu API)
struct ReminderPickerView: View {
    @Binding var selectedOffsets: Set<Int>
    let availableOffsets: [Int]
    let title: String
    let icon: String

    // Internal state for menu picker
    @State private var reminderOption: ReminderOption

    init(
        selectedOffsets: Binding<Set<Int>>,
        availableOffsets: [Int] = [1, 3, 7, 30],
        title: String = String(localized: "subscription.reminders"),
        icon: String = "bell"
    ) {
        self._selectedOffsets = selectedOffsets
        self.availableOffsets = availableOffsets
        self.title = title
        self.icon = icon

        // Initialize internal state based on selectedOffsets
        let initialOption: ReminderOption
        if selectedOffsets.wrappedValue.isEmpty {
            initialOption = .none
        } else if let firstOffset = selectedOffsets.wrappedValue.first {
            initialOption = .daysBefore(firstOffset)
        } else {
            initialOption = .none
        }
        self._reminderOption = State(initialValue: initialOption)
    }

    var body: some View {
        MenuPickerRow(
//            icon: icon,
            title: title,
            selection: Binding(
                get: { reminderOption },
                set: { newValue in
                    reminderOption = newValue
                    switch newValue {
                    case .none:
                        selectedOffsets.removeAll()
                    case .daysBefore(let offset):
                        selectedOffsets = [offset]
                    }
                }
            ),
            options: [
                (label: String(localized: "reminder.none"), value: .none)
            ] + availableOffsets.map { offset in
                (label: reminderText(for: offset), value: .daysBefore(offset))
            }
        )
        .onChange(of: selectedOffsets) { oldValue, newValue in
            // Sync external selectedOffsets changes back to reminderOption
            if newValue.isEmpty && reminderOption != .none {
                reminderOption = .none
            } else if let firstOffset = newValue.first, case .daysBefore(let current) = reminderOption, current != firstOffset {
                reminderOption = .daysBefore(firstOffset)
            }
        }
    }

    // MARK: - Helper Methods

    /// Generates localized reminder text for given offset
    private func reminderText(for offset: Int) -> String {
        switch offset {
        case 1:
            return String(localized: "reminder.dayBefore.one")
        case 3:
            return String(localized: "reminder.daysBefore.3")
        case 7:
            return String(localized: "reminder.daysBefore.7")
        case 30:
            return String(localized: "reminder.daysBefore.30")
        default:
            // Fallback for custom offsets
            return "За \(offset) дней"
        }
    }
}

// MARK: - ReminderOption Enum

/// Option for reminder selection: none or specific days before
enum ReminderOption: Hashable {
    case none
    case daysBefore(Int)

    var displayName: String {
        switch self {
        case .none:
            return String(localized: "reminder.none")
        case .daysBefore(let offset):
            switch offset {
            case 1:
                return String(localized: "reminder.dayBefore.one")
            case 3:
                return String(localized: "reminder.daysBefore.3")
            case 7:
                return String(localized: "reminder.daysBefore.7")
            case 30:
                return String(localized: "reminder.daysBefore.30")
            default:
                return "За \(offset) дней"
            }
        }
    }
}

// MARK: - Previews

#Preview("Никогда") {
    @Previewable @State var selectedOffsets: Set<Int> = []

    FormSection(style: .card) {
        ReminderPickerView(selectedOffsets: $selectedOffsets)
    }
    .padding()
}

#Preview("За 1 день") {
    @Previewable @State var selectedOffsets: Set<Int> = [1]

    FormSection(style: .card) {
        ReminderPickerView(selectedOffsets: $selectedOffsets)
    }
    .padding()
}

#Preview("За 7 дней") {
    @Previewable @State var selectedOffsets: Set<Int> = [7]

    FormSection(style: .card) {
        ReminderPickerView(selectedOffsets: $selectedOffsets)
    }
    .padding()
}

#Preview("В форме") {
    @Previewable @State var name = ""
    @Previewable @State var frequency: RecurringFrequency = .monthly
    @Previewable @State var offsets: Set<Int> = [3]

    ScrollView {
        VStack(spacing: AppSpacing.xxl) {
            FormSection(
                header: String(localized: "subscription.basicInfo"),
                style: .card
            ) {
                FormTextField(
                    text: $name,
                    placeholder: "Netflix"
                )
                .formDivider()

                MenuPickerRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: String(localized: "common.frequency"),
                    selection: $frequency
                )
                .formDivider()

                ReminderPickerView(selectedOffsets: $offsets)
            }
        }
        .padding()
    }
}
