//
//  FormTextField.swift
//  AIFinanceManager
//
//  Enhanced text field with error states, help text, and validation
//  Replaces DescriptionTextField with more features
//

import SwiftUI

/// Enhanced text field for forms with error/help states and multiple styles
/// Supports single-line, multiline, and compact variants
struct FormTextField: View {
    @Binding var text: String
    let placeholder: String
    let style: Style
    let keyboardType: UIKeyboardType
    let errorMessage: String?
    let helpText: String?
    @FocusState private var isFocused: Bool

    enum Style {
        /// Standard single-line text field
        case standard

        /// Multiline text field with line limits
        case multiline(min: Int, max: Int)

        /// Compact variant with less padding
        case compact
    }

    init(
        text: Binding<String>,
        placeholder: String,
        style: Style = .standard,
        keyboardType: UIKeyboardType = .default,
        errorMessage: String? = nil,
        helpText: String? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.style = style
        self.keyboardType = keyboardType
        self.errorMessage = errorMessage
        self.helpText = helpText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            // Text field
            Group {
                switch style {
                case .standard:
                    standardField

                case .multiline(let min, let max):
                    multilineField(min: min, max: max)

                case .compact:
                    compactField
                }
            }
            .padding(paddingForStyle)
            .background(backgroundForState)
            .clipShape(.rect(cornerRadius: AppRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .stroke(borderForState, lineWidth: errorMessage != nil ? 1 : 0)
            )

            // Error message
            if let error = errorMessage {
                Label {
                    Text(error)
                        .font(AppTypography.caption)
                        .foregroundStyle(.red)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(AppTypography.caption)
                        .foregroundStyle(.red)
                }
            }

            // Help text (only show when no error)
            if let help = helpText, errorMessage == nil {
                Text(help)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    // MARK: - Field Variants

    private var standardField: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboardType)
            .focused($isFocused)
            .font(AppTypography.body)
    }

    private func multilineField(min: Int, max: Int) -> some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(min...max)
            .focused($isFocused)
            .font(AppTypography.body)
    }

    private var compactField: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboardType)
            .focused($isFocused)
            .font(AppTypography.bodySmall)
    }

    // MARK: - Styling Helpers

    private var paddingForStyle: CGFloat {
        switch style {
        case .standard, .multiline:
            return AppSpacing.md
        case .compact:
            return AppSpacing.sm
        }
    }

    private var backgroundForState: Color {
        if errorMessage != nil {
            return Color.red.opacity(0.05)
        } else if isFocused {
            return AppColors.accent.opacity(0.05)
        } else {
            return AppColors.surface
        }
    }

    private var borderForState: Color {
        if errorMessage != nil {
            return .red.opacity(0.3)
        } else {
            return .clear
        }
    }
}

// MARK: - Previews

#Preview("Standard Style") {
    @Previewable @State var text = ""

    return VStack(spacing: AppSpacing.lg) {
        FormTextField(
            text: $text,
            placeholder: "Enter your name"
        )

        FormTextField(
            text: $text,
            placeholder: "Email address",
            keyboardType: .emailAddress,
            helpText: "We'll never share your email"
        )
    }
    .padding()
}

#Preview("With Error") {
    @Previewable @State var text = "invalid"

    return FormTextField(
        text: $text,
        placeholder: "Amount",
        keyboardType: .decimalPad,
        errorMessage: "Please enter a valid amount"
    )
    .padding()
}

#Preview("Multiline") {
    @Previewable @State var text = ""

    return VStack(spacing: AppSpacing.lg) {
        FormTextField(
            text: $text,
            placeholder: "Description",
            style: .multiline(min: 3, max: 6)
        )

        FormTextField(
            text: $text,
            placeholder: "Notes",
            style: .multiline(min: 2, max: 4),
            helpText: "Add any additional notes here"
        )
    }
    .padding()
}

#Preview("Compact Style") {
    @Previewable @State var text = ""

    return FormTextField(
        text: $text,
        placeholder: "Compact field",
        style: .compact
    )
    .padding()
}

#Preview("All States") {
    @Previewable @State var normal = ""
    @Previewable @State var withHelp = ""
    @Previewable @State var withError = "bad input"

    return VStack(spacing: AppSpacing.xl) {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Normal")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            FormTextField(
                text: $normal,
                placeholder: "Normal state"
            )
        }

        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("With Help Text")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            FormTextField(
                text: $withHelp,
                placeholder: "Field with help",
                helpText: "This is some helpful information"
            )
        }

        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("With Error")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            FormTextField(
                text: $withError,
                placeholder: "Field with error",
                errorMessage: "This field has an error"
            )
        }
    }
    .padding()
}

#Preview("In Form Context") {
    @Previewable @State var name = ""
    @Previewable @State var amount = ""
    @Previewable @State var description = ""

    return ScrollView {
        VStack(spacing: AppSpacing.xxl) {
            FormSection(
                header: String(localized: "subscription.basicInfo"),
                style: .card
            ) {
                FormTextField(
                    text: $name,
                    placeholder: String(localized: "subscription.namePlaceholder")
                )

                Divider()
                    .padding(.leading, AppSpacing.md)

                FormTextField(
                    text: $amount,
                    placeholder: "0.00",
                    keyboardType: .decimalPad,
                    helpText: "Enter subscription amount"
                )

                Divider()
                    .padding(.leading, AppSpacing.md)

                FormTextField(
                    text: $description,
                    placeholder: "Description (optional)",
                    style: .multiline(min: 2, max: 4)
                )
            }
        }
        .padding()
    }
}
