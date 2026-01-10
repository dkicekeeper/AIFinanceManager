//
//  PDFService.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation
import PDFKit
@preconcurrency import Vision
import UIKit

struct OCRResult {
    let fullText: String
    let pageTexts: [String] // Для дебага - текст каждой страницы
    let structuredRows: [[String]]? // Структурированные строки таблицы (если найдены)
}

/// Структура для хранения распознанного текста с координатами
struct TextObservation {
    let text: String
    let boundingBox: CGRect // Координаты в системе Vision (0-1)
    let confidence: Float
}

class PDFService {
    static let shared = PDFService()
    
    private init() {}
    
    func extractText(
        from url: URL,
        progressCallback: ((Int, Int) -> Void)? = nil
    ) async throws -> OCRResult {
        // Проверяем, что файл существует и доступен
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            print("Error: PDF file does not exist at path: \(url.path)")
            throw PDFError.invalidDocument
        }
        
        // Начинаем доступ к файлу, если это security-scoped resource
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Сначала пытаемся открыть PDF документ
        guard let pdfDocument = PDFDocument(url: url) else {
            print("Error: Could not open PDF document from URL: \(url)")
            print("File path: \(url.path)")
            print("File exists: \(fileManager.fileExists(atPath: url.path))")
            
            // Пытаемся прочитать данные напрямую
            if let data = try? Data(contentsOf: url) {
                print("File data size: \(data.count) bytes")
                if let pdfFromData = PDFDocument(data: data) {
                    // Если получилось открыть через Data, используем этот документ
                    return try await extractText(from: pdfFromData, progressCallback: progressCallback)
                }
            }
            
            throw PDFError.invalidDocument
        }
        
        return try await extractText(from: pdfDocument, progressCallback: progressCallback)
    }
    
    private func extractText(
        from pdfDocument: PDFDocument,
        progressCallback: ((Int, Int) -> Void)?
    ) async throws -> OCRResult {
        let pageCount = pdfDocument.pageCount
        var fullText = ""
        var pageTexts: [String] = []
        
        print("📄 PDF has \(pageCount) pages")
        
        // Сначала пытаемся извлечь текст через PDFKit (для текстовых PDF)
        var hasAnyText = false
        for pageIndex in 0..<pageCount {
            // Обновляем прогресс для текстовых PDF
            if let callback = progressCallback {
                await MainActor.run {
                    callback(pageIndex + 1, pageCount)
                }
            }
            
            guard let page = pdfDocument.page(at: pageIndex) else {
                print("⚠️ Warning: Could not get page \(pageIndex)")
                pageTexts.append("")
                continue
            }
            
            // Прямое извлечение текста (для текстовых PDF)
            if let pageText = page.string, !pageText.isEmpty {
                let trimmedPageText = pageText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if !trimmedPageText.isEmpty {
                    fullText += pageText + "\n\n"
                    pageTexts.append(trimmedPageText)
                    hasAnyText = true
                    print("✅ Page \(pageIndex + 1): Extracted \(pageText.count) characters via PDFKit")
                } else {
                    pageTexts.append("")
                }
            } else {
                pageTexts.append("")
                print("⚠️ Page \(pageIndex + 1): No text found via PDFKit (may be scanned image)")
            }
        }
        
        // Если найден текст, пытаемся извлечь структуру из PDFKit
        if hasAnyText {
            let trimmedText = fullText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            print("✅ Successfully extracted \(trimmedText.count) characters from PDF via PDFKit")
            
            // Пытаемся извлечь структуру из PDFKit (для текстовых PDF)
            // Для PDFKit текста структурируем по таблицам
            let structuredRows = extractStructureFromPDFText(fullText)
            
            // Финальный прогресс уже показан в цикле, просто возвращаем результат
            return OCRResult(fullText: trimmedText, pageTexts: pageTexts, structuredRows: structuredRows)
        }
        
        // Если текста нет, используем OCR через Vision с координатами
        print("No text found via PDFKit, using Vision OCR with structure recognition...")
        return try await performStructuredOCR(
            from: pdfDocument,
            progressCallback: progressCallback
        )
    }
    
    /// Выполняет OCR с извлечением структуры таблицы через координаты
    private func performStructuredOCR(
        from pdfDocument: PDFDocument,
        progressCallback: ((Int, Int) -> Void)?
    ) async throws -> OCRResult {
        let pageCount = pdfDocument.pageCount
        var fullText = ""
        var pageTexts: [String] = []
        var allObservations: [TextObservation] = []
        var allStructuredRows: [[String]] = []
        
        // Обрабатываем каждую страницу
        for pageIndex in 0..<pageCount {
            // Обновляем прогресс (на main thread)
            if let callback = progressCallback {
                await MainActor.run {
                    callback(pageIndex + 1, pageCount)
                }
            }
            
            guard let page = pdfDocument.page(at: pageIndex) else {
                print("Warning: Could not get page \(pageIndex) for OCR")
                pageTexts.append("")
                continue
            }
            
            // Рендерим страницу PDF в изображение
            let pageRect = page.bounds(for: .mediaBox)
            // Увеличиваем разрешение для лучшего качества OCR (2x)
            let scale: CGFloat = 2.0
            let scaledSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
            
            let renderer = UIGraphicsImageRenderer(size: scaledSize)
            
            let image = renderer.image { context in
                context.cgContext.saveGState()
                context.cgContext.translateBy(x: 0, y: scaledSize.height)
                context.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: context.cgContext)
                context.cgContext.restoreGState()
            }
            
            guard let cgImage = image.cgImage else {
                print("Error: Could not convert page \(pageIndex + 1) to CGImage")
                pageTexts.append("")
                continue
            }
            
            // Выполняем OCR с получением координат
            let (pageText, observations) = try await recognizeTextWithCoordinates(from: cgImage, pageSize: scaledSize)
            pageTexts.append(pageText)
            fullText += pageText + "\n\n"
            
            // Сохраняем наблюдения для структурирования
            allObservations.append(contentsOf: observations)
            
            // Пытаемся структурировать текст текущей страницы
            let pageStructuredRows = structureObservations(observations, pageSize: scaledSize)
            if !pageStructuredRows.isEmpty {
                allStructuredRows.append(contentsOf: pageStructuredRows)
                print("📊 Page \(pageIndex + 1)/\(pageCount): Found \(pageStructuredRows.count) structured rows")
            }
            
            print("Page \(pageIndex + 1)/\(pageCount): Recognized \(pageText.count) characters via OCR, \(observations.count) text blocks")
        }
        
        // Финальный прогресс
        if let callback = progressCallback {
            await MainActor.run {
                callback(pageCount, pageCount)
            }
        }
        
        let trimmedText = fullText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        guard !trimmedText.isEmpty else {
            print("Error: OCR did not extract any text")
            throw PDFError.noTextFound
        }
        
        print("✅ Successfully recognized \(trimmedText.count) characters from PDF via OCR")
        print("📊 Total structured rows found: \(allStructuredRows.count)")
        
        return OCRResult(
            fullText: trimmedText,
            pageTexts: pageTexts,
            structuredRows: allStructuredRows.isEmpty ? nil : allStructuredRows
        )
    }
    
    /// Извлекает структуру из PDFKit текста (для текстовых PDF)
    private func extractStructureFromPDFText(_ text: String) -> [[String]]? {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }.filter { !$0.isEmpty }
        
        // Ищем таблицы в PDFKit тексте (строки с разделителями "|")
        var structuredRows: [[String]] = []
        var inTable = false
        
        for line in lines {
            if line.contains("|") && !line.contains("|---") {
                // Это строка таблицы
                let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                if parts.count >= 3 { // Минимум 3 колонки для таблицы
                    structuredRows.append(parts)
                    inTable = true
                }
            } else if inTable && !line.contains("|") {
                // Конец таблицы
                inTable = false
            }
        }
        
        return structuredRows.isEmpty ? nil : structuredRows
    }
    
    /// Структурирует наблюдения текста в строки таблицы на основе координат
    private func structureObservations(_ observations: [TextObservation], pageSize: CGSize) -> [[String]] {
        guard !observations.isEmpty else { return [] }
        
        print("🔍 Structuring \(observations.count) text observations...")
        
        // Конвертируем координаты Vision в абсолютные координаты
        // Vision использует координаты 0-1, где (0,0) - нижний левый угол
        let absoluteObservations = observations.map { obs -> (text: String, x: CGFloat, y: CGFloat, width: CGFloat, box: CGRect) in
            let absRect = CGRect(
                x: obs.boundingBox.origin.x * pageSize.width,
                y: (1.0 - obs.boundingBox.origin.y - obs.boundingBox.height) * pageSize.height, // Инвертируем Y
                width: obs.boundingBox.width * pageSize.width,
                height: obs.boundingBox.height * pageSize.height
            )
            return (
                text: obs.text,
                x: absRect.midX,
                y: absRect.midY,
                width: absRect.width,
                box: absRect
            )
        }
        
        // Группируем по строкам (Y координаты)
        // Используем адаптивный порог для группировки строк
        // Сначала находим среднюю высоту текста для определения порога
        let avgHeight = absoluteObservations.map { $0.box.height }.reduce(0, +) / CGFloat(absoluteObservations.count)
        let rowTolerance = max(avgHeight * 0.5, pageSize.height * 0.02) // Адаптивный порог
        
        print("📏 Average text height: \(avgHeight), row tolerance: \(rowTolerance)")
        
        // Сортируем наблюдения сверху вниз (по Y)
        let sortedObs = absoluteObservations.sorted { $0.y > $1.y }
        
        // Группируем по строкам
        var rowGroups: [[(text: String, x: CGFloat, y: CGFloat, width: CGFloat, box: CGRect)]] = []
        
        for obs in sortedObs {
            // Ищем группу строк с близкими Y координатами
            if let rowIndex = rowGroups.firstIndex(where: { row in
                guard let firstObs = row.first else { return false }
                let yDiff = abs(firstObs.y - obs.y)
                return yDiff <= rowTolerance
            }) {
                rowGroups[rowIndex].append(obs)
            } else {
                // Создаем новую группу строк
                rowGroups.append([obs])
            }
        }
        
        print("📊 Grouped into \(rowGroups.count) rows")
        
        // Определяем колонки на основе X координат
        // Собираем все X координаты для определения позиций колонок
        var allXPositions: [CGFloat] = []
        for row in rowGroups {
            for obs in row {
                allXPositions.append(obs.x)
            }
        }
        
        // Сортируем и находим уникальные позиции колонок (кластеризуем близкие X)
        let sortedX = allXPositions.sorted()
        var columnPositions: [CGFloat] = []
        let columnTolerance = pageSize.width * 0.05 // 5% ширины страницы
        
        for x in sortedX {
            if columnPositions.isEmpty {
                columnPositions.append(x)
            } else {
                // Проверяем, не слишком ли близко к существующим колонкам
                let isClose = columnPositions.contains { abs($0 - x) <= columnTolerance }
                if !isClose {
                    columnPositions.append(x)
                }
            }
        }
        
        columnPositions.sort()
        print("📊 Detected \(columnPositions.count) column positions")
        
        // Сортируем элементы в каждой строке по X (слева направо)
        for i in 0..<rowGroups.count {
            rowGroups[i].sort { $0.x < $1.x }
        }
        
        // Формируем структурированные строки
        var structuredRows: [[String]] = []
        
        // Для более надежной работы с таблицами, используем упрощенный подход:
        // Просто группируем текст по строкам (Y) и сортируем по X внутри строки
        // Это даст нам структуру, близкую к исходной таблице
        
        for row in rowGroups {
            // Для каждой строки формируем массив колонок
            // Используем упрощенный подход: просто берем все элементы строки по порядку
            var rowCells: [String] = []
            
            // Более умная группировка: разбиваем элементы на колонки на основе промежутков между X координатами
            if row.count == 1 {
                // Если в строке только один элемент, это может быть продолжение предыдущей строки
                // Или заголовок - пропускаем для упрощения
                continue
            }
            
            // Группируем элементы по колонкам на основе промежутков между X
            var currentColumn: [String] = []
            var lastX: CGFloat? = nil
            let minColumnGap = pageSize.width * 0.08 // Минимальный промежуток для новой колонки (8% ширины)
            
            for obs in row {
                if let prevX = lastX {
                    let gap = obs.x - prevX
                    if gap > minColumnGap {
                        // Новый столбец - сохраняем предыдущий
                        if !currentColumn.isEmpty {
                            rowCells.append(currentColumn.joined(separator: " "))
                            currentColumn = []
                        }
                    }
                }
                
                currentColumn.append(obs.text)
                lastX = obs.x
            }
            
            // Добавляем последнюю колонку
            if !currentColumn.isEmpty {
                rowCells.append(currentColumn.joined(separator: " "))
            }
            
            // Проверяем, является ли строка транзакцией (содержит дату)
            let rowText = rowCells.joined(separator: " ")
            let hasDate = rowText.range(of: #"\d{2}\.\d{2}\.\d{4}"#, options: .regularExpression) != nil
            
            // Также проверяем, не является ли это заголовком таблицы
            let isHeader = rowText.uppercased().contains("ДАТА") && rowText.uppercased().contains("ОПЕРАЦИЯ")
            
            if !isHeader && hasDate && rowCells.count >= 3 {
                // Удаляем пустые колонки с конца
                while let last = rowCells.last, last.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                    rowCells.removeLast()
                }
                
                if !rowCells.isEmpty {
                    structuredRows.append(rowCells)
                }
            }
        }
        
        print("✅ Structured \(structuredRows.count) transaction rows from \(observations.count) observations")
        
        if !structuredRows.isEmpty {
            print("📊 First structured row example: \(structuredRows.first?.joined(separator: " | ") ?? "")")
        }
        
        return structuredRows
    }
    
    /// Распознает текст с получением координат для структурирования
    private func recognizeTextWithCoordinates(from cgImage: CGImage, pageSize: CGSize) async throws -> (text: String, observations: [TextObservation]) {
        return try await withCheckedThrowingContinuation { continuation in
            // Выполняем запрос на фоне (не блокируя main thread)
            DispatchQueue.global(qos: .userInitiated).async {
                var recognizedStrings: [String] = []
                var textObservations: [TextObservation] = []
                
                // Создаем новый request для каждого изображения с обработчиком в инициализаторе
                let request = VNRecognizeTextRequest { request, error in
                    if let error = error {
                        continuation.resume(throwing: PDFError.ocrError(error.localizedDescription))
                        return
                    }
                    
                    guard let observations = request.results as? [VNRecognizedTextObservation] else {
                        continuation.resume(returning: ("", []))
                        return
                    }
                    
                    // Сортируем наблюдения сверху вниз, слева направо для правильного порядка
                    let sortedObservations = observations.sorted { obs1, obs2 in
                        // Сначала по Y (сверху вниз), потом по X (слева направо)
                        let y1 = 1.0 - obs1.boundingBox.midY // Инвертируем Y для сортировки
                        let y2 = 1.0 - obs2.boundingBox.midY
                        
                        if abs(y1 - y2) > 0.02 { // Разные строки (2% высоты)
                            return y1 < y2
                        } else {
                            return obs1.boundingBox.midX < obs2.boundingBox.midX
                        }
                    }
                    
                    for observation in sortedObservations {
                        guard let topCandidate = observation.topCandidates(1).first else {
                            continue
                        }
                        
                        let text = topCandidate.string
                        recognizedStrings.append(text)
                        
                        // Сохраняем наблюдение с координатами
                        textObservations.append(TextObservation(
                            text: text,
                            boundingBox: observation.boundingBox,
                            confidence: topCandidate.confidence
                        ))
                    }
                    
                    let fullText = recognizedStrings.joined(separator: " ")
                    continuation.resume(returning: (fullText, textObservations))
                }
                
                // Настраиваем параметры OCR
                request.recognitionLanguages = ["ru-RU", "en-US"]
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: PDFError.ocrError(error.localizedDescription))
                }
            }
        }
    }
}

enum PDFError: LocalizedError {
    case invalidDocument
    case noTextFound
    case unsupportedFormat
    case ocrError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return NSLocalizedString("Не удалось открыть PDF документ. Убедитесь, что файл является валидным PDF.", comment: "PDF error")
        case .noTextFound:
            return NSLocalizedString("Не удалось извлечь текст из PDF. Возможно, документ поврежден или пуст.", comment: "PDF error")
        case .unsupportedFormat:
            return NSLocalizedString("Неподдерживаемый формат PDF.", comment: "PDF error")
        case .ocrError(let message):
            return NSLocalizedString("Ошибка при распознавании текста: \(message)", comment: "OCR error")
        }
    }
}
