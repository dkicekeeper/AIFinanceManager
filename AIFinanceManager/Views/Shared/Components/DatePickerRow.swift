//
//  DatePickerRow.swift
//  AIFinanceManager
//
//  Simplified date picker row - inline style only
//  For button-based selection, use DateButtonsView directly
//

import SwiftUI

/// Date picker row with inline style
/// For button-based selection (Yesterday/Today/Calendar), use DateButtonsView directly
struct DatePickerRow: View {
    let title: String
    @Binding var selection: Date
    let displayedComponents: DatePickerComponents

    init(
        title: String = String(localized: "common.startDate"),
        selection: Binding<Date>,
        displayedComponents: DatePickerComponents = .date
    ) {
        self.title = title
        self._selection = selection
        self.displayedComponents = displayedComponents
    }

    var body: some View {
        DatePicker(
            title,
            selection: $selection,
            displayedComponents: displayedComponents
        )
        .padding(AppSpacing.md)
    }
}

// MARK: - Previews

#Preview("Basic Usage") {
    @Previewable @State var date = Date()

    FormSection(
        header: "Subscription Details",
        style: .card
    ) {
        TextField("Name", text: .constant("Netflix"))
            .padding(AppSpacing.md)

        Divider()
            .padding(.leading, AppSpacing.md)

        DatePickerRow(
            title: String(localized: "common.startDate"),
            selection: $date
        )
    }
    .padding()
}

#Preview("Date & Time") {
    @Previewable @State var datetime = Date()

    FormSection(
        header: "Appointment",
        style: .card
    ) {
        DatePickerRow(
            title: "Date & Time",
            selection: $datetime,
            displayedComponents: [.date, .hourAndMinute]
        )
    }
    .padding()
}

#Preview("In Form Context") {
    @Previewable @State var name = ""
    @Previewable @State var amount = ""
    @Previewable @State var startDate = Date()

    ScrollView {
        VStack(spacing: AppSpacing.xxl) {
            FormSection(
                header: String(localized: "subscription.basicInfo"),
                style: .card
            ) {
                FormTextField(
                    text: $name,
                    placeholder: String(localized: "subscription.namePlaceholder")
                )
                .formDivider()

                FormTextField(
                    text: $amount,
                    placeholder: "0.00",
                    keyboardType: .decimalPad
                )
                .formDivider()

                DatePickerRow(
                    title: String(localized: "common.startDate"),
                    selection: $startDate
                )
            }
        }
        .padding()
    }
}
