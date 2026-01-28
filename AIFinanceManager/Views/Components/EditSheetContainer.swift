//
//  EditSheetContainer.swift
//  AIFinanceManager
//
//  Generic wrapper for modal edit-form sheets.
//  Extracts the repeated NavigationView → Form → toolbar(xmark / checkmark) shell
//  that was duplicated across AccountEditView, CategoryEditView, SubcategoryEditView,
//  DepositEditView, and SubscriptionEditView.
//

import SwiftUI

/// A reusable container that wraps Form content inside a NavigationView
/// with the standard modal edit-sheet chrome: title, cancel (xmark) and save (checkmark) toolbar buttons.
///
/// Usage:
/// ```swift
/// EditSheetContainer(
///     title: account == nil ? "New Account" : "Edit Account",
///     isSaveDisabled: name.isEmpty,
///     onSave: { /* save logic */ },
///     onCancel: onCancel
/// ) {
///     Section(header: Text("Name")) { ... }
///     Section(header: Text("Balance")) { ... }
/// }
/// ```
struct EditSheetContainer<Content: View>: View {
    /// Navigation title displayed at the top of the sheet
    let title: String
    /// When `true`, the save (checkmark) button is disabled
    let isSaveDisabled: Bool
    /// Called when the user taps the checkmark button
    let onSave: () -> Void
    /// Called when the user taps the xmark button
    let onCancel: () -> Void
    /// The Form sections content provided by the caller
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationView {
            Form {
                content()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        HapticManager.light()
                        onSave()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
    }
}
