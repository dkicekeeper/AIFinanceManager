//
//  EmptyAccountsPrompt.swift
//  AIFinanceManager
//
//  Reusable empty accounts state with add action
//

import SwiftUI

/// Displays empty state for accounts section with call-to-action
/// Reusable component - can be used in ContentView and AccountsManagementView
struct EmptyAccountsPrompt: View {
    // MARK: - Properties
    let onAddAccount: () -> Void

    // MARK: - Body
    var body: some View {
        Button(action: {
            HapticManager.light()
            onAddAccount()
        }) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                HStack {
                    Text(String(localized: LocalizationKeys.Navigation.accountsTitle))
                        .font(AppTypography.h3)
                        .foregroundStyle(.primary)
                }

                EmptyStateView(
                    title: String(localized: LocalizationKeys.EmptyState.noAccounts),
                    style: .compact
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCardStyle(radius: AppRadius.pill)
        }
        .buttonStyle(.bounce)
        .screenPadding()
    }
}

// MARK: - Preview
#Preview {
    EmptyAccountsPrompt(onAddAccount: {})
}
