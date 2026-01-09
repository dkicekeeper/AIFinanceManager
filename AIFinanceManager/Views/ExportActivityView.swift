//
//  ExportActivityView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI
import UIKit

struct ExportActivityView: UIViewControllerRepresentable {
    let viewModel: TransactionsViewModel
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let csvContent = CSVExporter.exportTransactions(viewModel.allTransactions, accounts: viewModel.accounts)
        
        // Создаем временный файл
        let fileName = "transactions_export_\(DateFormatter.exportFileNameFormatter.string(from: Date())).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            print("Ошибка создания файла: \(error)")
        }
        
        let activityVC = UIActivityViewController(
            activityItems: [tempURL],
            applicationActivities: nil
        )
        
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            // Удаляем временный файл после экспорта
            try? FileManager.default.removeItem(at: tempURL)
            dismiss()
        }
        
        return activityVC
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
