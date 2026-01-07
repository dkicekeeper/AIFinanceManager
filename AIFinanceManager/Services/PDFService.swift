//
//  PDFService.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation
import PDFKit

class PDFService {
    static let shared = PDFService()
    
    private init() {}
    
    func extractText(from url: URL) async throws -> String {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw PDFError.invalidDocument
        }
        
        var fullText = ""
        let pageCount = pdfDocument.pageCount
        
        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }
            if let pageText = page.string {
                fullText += pageText + " "
            }
        }
        
        guard !fullText.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PDFError.noTextFound
        }
        
        return fullText
    }
}

enum PDFError: LocalizedError {
    case invalidDocument
    case noTextFound
    
    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return "Could not open PDF document"
        case .noTextFound:
            return "Could not extract text from PDF"
        }
    }
}
