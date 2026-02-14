//
//  DatePickerRow.swift
//  AIFinanceManager
//
//  Standardized date selection row with multiple display styles
//  Provides inline, compact, and sheet variants
//

import SwiftUI

/// Date picker row with multiple presentation styles
/// - `.inline`: Standard iOS DatePicker (expanded in form)
/// - `.compact`: Shows date, opens sheet on tap
/// - `.buttons`: Uses DateButtonsView (Yesterday/Today/Calendar)
struct DatePickerRow: View {
    let title: String
    @Binding var selection: Date
    let displayedComponents: DatePickerComponents
    let style: Style

    enum Style {
        /// Inline DatePicker (expands in form)
        case inline

        /// Compact row, opens sheet on tap
        case compact

        /// Button-based selection (Yesterday/Today/Calendar)
        case buttons
    }

    @State private var showingPicker = false

    init(
        title: String = String(localized: "common.startDate"),
        selection: Binding<Date>,
        displayedComponents: DatePickerComponents = .date,
        style: Style = .inline
    ) {
        self.title = title
        self._selection = selection
        self.displayedComponents = displayedComponents
        self.style = style
    }

    var body: some View {
        switch style {
        case .inline:
            inlineStyle

        case .compact:
            compactStyle

        case .buttons:
            buttonsStyle
        }
    }

    // MARK: - Style Variants

    private var inlineStyle: some View {
        DatePicker(
            title,
            selection: $selection,
            displayedComponents: displayedComponents
        )
        .padding(AppSpacing.md)
    }

    private var compactStyle: some View {
        Button {
            HapticManager.light()
            showingPicker = true
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Text(selection, style: .date)
                    .foregroundStyle(AppColors.textSecondary)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(AppSpacing.md)
        }
        .sheet(isPresented: $showingPicker) {
            DatePickerSheet(
                title: title,
                selection: $selection,
                displayedComponents: displayedComponents
            )
        }
    }

    private var buttonsStyle: some View {
        DateButtonsView(
            selectedDate: $selection,
            onSave: { _ in }
        )
    }
}

// MARK: - Date Picker Sheet

private struct DatePickerSheet: View {
    let title: String
    @Binding var selection: Date
    let displayedComponents: DatePickerComponents
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    title,
                    selection: $selection,
                    displayedComponents: displayedComponents
                )
                .datePickerStyle(.graphical)
                .padding()

                Spacer()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.select")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Inline Style") {
    @Previewable @State var date = Date()

    return FormSection(
        header: "Subscription Details",
        style: .card
    ) {
        TextField("Name", text: .constant("Netflix"))
            .padding(AppSpacing.md)

        Divider()
            .padding(.leading, AppSpacing.md)

        DatePickerRow(
            title: String(localized: "common.startDate"),
            selection: $date,
            style: .inline
        )
    }
    .padding()
}

#Preview("Compact Style") {
    @Previewable @State var date = Date()

    return FormSection(
        header: "Select Date",
        style: .card
    ) {
        TextField("Event Name", text: .constant("Meeting"))
            .padding(AppSpacing.md)

        Divider()
            .padding(.leading, AppSpacing.md)

        DatePickerRow(
            title: "Event Date",
            selection: $date,
            style: .compact
        )

        Divider()
            .padding(.leading, AppSpacing.md)

        TextField("Location", text: .constant("Office"))
            .padding(AppSpacing.md)
    }
    .padding()
}

#Preview("Buttons Style") {
    @Previewable @State var date = Date()

    return VStack(spacing: AppSpacing.lg) {
        Text("Selected: \(date, style: .date)")
            .font(AppTypography.bodySmall)

        DatePickerRow(
            selection: $date,
            style: .buttons
        )
    }
    .padding()
}

#Preview("All Styles") {
    @Previewable @State var date1 = Date()
    @Previewable @State var date2 = Date()
    @Previewable @State var date3 = Date()

    return ScrollView {
        VStack(alignment: .leading, spacing: AppSpacing.xxl) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Inline Style")
                    .font(AppTypography.h4)

                FormSection(style: .card) {
                    DatePickerRow(
                        title: "Due Date",
                        selection: $date1,
                        style: .inline
                    )
                }
            }

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Compact Style")
                    .font(AppTypography.h4)

                FormSection(style: .card) {
                    DatePickerRow(
                        title: "Start Date",
                        selection: $date2,
                        style: .compact
                    )
                }
            }

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Buttons Style")
                    .font(AppTypography.h4)

                DatePickerRow(
                    selection: $date3,
                    style: .buttons
                )
            }
        }
        .padding()
    }
}

#Preview("Date & Time") {
    @Previewable @State var datetime = Date()

    return FormSection(
        header: "Appointment",
        style: .card
    ) {
        DatePickerRow(
            title: "Date & Time",
            selection: $datetime,
            displayedComponents: [.date, .hourAndMinute],
            style: .inline
        )
    }
    .padding()
}
