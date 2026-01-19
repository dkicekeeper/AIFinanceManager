//
//  WarningMessageView.swift
//  AIFinanceManager
//
//  Reusable warning message component
//

import SwiftUI

struct WarningMessageView: View {
    let message: String
    let color: Color
    
    init(message: String, color: Color = .orange) {
        self.message = message
        self.color = color
    }
    
    var body: some View {
        Text(message)
            .font(AppTypography.caption)
            .foregroundColor(color)
            .padding(.top, AppSpacing.xs)
            .padding(.horizontal, AppSpacing.lg)
    }
}

#Preview {
    VStack {
        WarningMessageView(message: "Please select an account")
        WarningMessageView(message: "Error occurred", color: .red)
    }
    .padding()
}
