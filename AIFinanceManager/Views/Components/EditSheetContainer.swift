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
    /// Use ScrollView instead of Form for white background (hero-style views)
    let useScrollView: Bool
    /// Called when the user taps the checkmark button
    let onSave: () -> Void
    /// Called when the user taps the xmark button
    let onCancel: () -> Void
    /// The Form sections content provided by the caller
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        isSaveDisabled: Bool,
        useScrollView: Bool = false,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.isSaveDisabled = isSaveDisabled
        self.useScrollView = useScrollView
        self.onSave = onSave
        self.onCancel = onCancel
        self.content = content
    }

    var body: some View {
        NavigationStack {
            if useScrollView {
                content()
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        toolbarContent
                    }
            } else {
                Form {
                    content()
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    toolbarContent
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
