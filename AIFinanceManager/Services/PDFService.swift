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
        // Сначала пытаемся открыть PDF документ
        guard let pdfDocument = PDFDocument(url: url) else {
            print("Error: Could not open PDF document from URL: \(url)")
            throw PDFError.invalidDocument
        }
        
        var fullText = ""
        let pageCount = pdfDocument.pageCount
        
        print("PDF has \(pageCount) pages")
        
        // Извлекаем текст со всех страниц
        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else {
                print("Warning: Could not get page \(pageIndex)")
                continue
            }
            
            // Метод 1: Прямое извлечение текста (для текстовых PDF)
            if let pageText = page.string, !pageText.isEmpty {
                fullText += pageText + " "
                print("Page \(pageIndex + 1): Extracted \(pageText.count) characters")
            } else {
                // Метод 2: Попытка извлечения через CGPDFPage (для некоторых PDF)
                if page.pageRef != nil {
                    // Это текстовый PDF, но текст не извлекается через string
                    // Попробуем альтернативный метод
                    print("Warning: Page \(pageIndex + 1) has no extractable text via string property")
                }
            }
        }
        
        let trimmedText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedText.isEmpty else {
            print("Error: No text could be extracted from PDF")
            throw PDFError.noTextFound
        }
        
        print("Successfully extracted \(trimmedText.count) characters from PDF")
        return trimmedText
    }
}

enum PDFError: LocalizedError {
    case invalidDocument
    case noTextFound
    case unsupportedFormat
    
    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return NSLocalizedString("Could not open PDF document. Please make sure the file is a valid PDF.", comment: "PDF error")
        case .noTextFound:
            return NSLocalizedString("Could not extract text from PDF. This PDF may be an image-based document (scanned) and requires OCR, which is not supported in this version.", comment: "PDF error")
        case .unsupportedFormat:
            return NSLocalizedString("Unsupported PDF format.", comment: "PDF error")
        }
    }
}
