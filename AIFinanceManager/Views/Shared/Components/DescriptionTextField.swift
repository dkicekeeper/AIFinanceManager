//
//  DescriptionTextField.swift
//  AIFinanceManager
//
//  Reusable description text field component
//

import SwiftUI

struct DescriptionTextField: View {
    @Binding var text: String
    let placeholder: String
    let minLines: Int
    let maxLines: Int
    
    init(
        text: Binding<String>,
        placeholder: String = String(localized: "quickAdd.descriptionPlaceholder"),
        minLines: Int = 2,
        maxLines: Int = 6
    ) {
        self._text = text
        self.placeholder = placeholder
        self.minLines = minLines
        self.maxLines = maxLines
    }
    
    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .font(AppTypography.body)
            .lineLimit(minLines...maxLines)
            .padding(AppSpacing.lg)
            .background(.primary .opacity(0.03))
            .clipShape(.rect(cornerRadius: AppSpacing.md))
            .padding(AppSpacing.lg)
    }
}

#Preview {
    @Previewable @State var description = ""
    
    return DescriptionTextField(text: $description)
        .padding()
}
