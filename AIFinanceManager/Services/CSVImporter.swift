//
//  CSVImporter.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation

struct CSVFile {
    let headers: [String]
    let rows: [[String]]
    let preview: [[String]]
    
    var rowCount: Int {
        rows.count
    }
}

class CSVImporter {
    static func parseCSV(from url: URL) throws -> CSVFile {
        print("📂 Парсинг CSV из URL: \(url.path)")
        print("📂 Файл существует: \(FileManager.default.fileExists(atPath: url.path))")
        
        // Проверяем, является ли URL временным файлом (уже скопированным DocumentPicker)
        let isTemporaryFile = url.path.contains(FileManager.default.temporaryDirectory.path)
        var fileURL = url
        
        // Если это не временный файл, пытаемся получить доступ к security-scoped ресурсу
        if !isTemporaryFile {
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            if !isAccessing {
                print("⚠️ Не удалось получить доступ к security-scoped ресурсу")
            }
            
            // Копируем файл во временную директорию для надежного доступа
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
            try? FileManager.default.removeItem(at: tempURL)
            
            do {
                try FileManager.default.copyItem(at: url, to: tempURL)
                fileURL = tempURL
                print("✅ Файл скопирован во временную директорию: \(tempURL.path)")
            } catch {
                print("❌ Ошибка копирования файла: \(error)")
                // Пробуем использовать оригинальный URL
            }
        } else {
            print("✅ Используется временный файл: \(url.path)")
        }
        
        // Читаем содержимое файла
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            // Пробуем другие кодировки
            if let contentUTF16 = try? String(contentsOf: fileURL, encoding: .utf16) {
                print("✅ Файл прочитан как UTF-16")
                return try parseCSVContent(contentUTF16)
            }
            if let contentWindowsCP1251 = try? String(contentsOf: fileURL, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsCyrillic.rawValue)))) {
                print("✅ Файл прочитан как Windows CP1251")
                return try parseCSVContent(contentWindowsCP1251)
            }
            print("❌ Не удалось прочитать файл с любой кодировкой")
            throw CSVImportError.invalidEncoding
        }
        
        print("✅ Файл прочитан, размер: \(content.count) символов")
        return try parseCSVContent(content)
    }
    
    private static func parseCSVContent(_ content: String) throws -> CSVFile {
        
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        print("📊 Найдено строк: \(lines.count)")
        
        guard !lines.isEmpty else {
            throw CSVImportError.emptyFile
        }
        
        // Парсим CSV с учетом кавычек
        let parsedLines = lines.map { parseCSVLine($0) }
        print("📊 Распарсено строк: \(parsedLines.count)")
        
        guard let headers = parsedLines.first else {
            throw CSVImportError.noHeaders
        }
        
        print("📋 Заголовки: \(headers)")
        
        let rows = Array(parsedLines.dropFirst())
        let preview = Array(rows.prefix(5))
        
        print("✅ CSV успешно распарсен: \(headers.count) колонок, \(rows.count) строк данных")
        
        return CSVFile(headers: headers, rows: rows, preview: preview)
    }
    
    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var insideQuotes = false
        
        for char in line {
            if char == "\"" {
                if insideQuotes {
                    // Проверяем, не двойная ли это кавычка
                    if currentField.last == "\"" {
                        currentField.removeLast()
                        currentField.append("\"")
                    } else {
                        insideQuotes = false
                    }
                } else {
                    insideQuotes = true
                }
            } else if char == "," && !insideQuotes {
                fields.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
            } else {
                currentField.append(char)
            }
        }
        
        // Добавляем последнее поле
        fields.append(currentField.trimmingCharacters(in: .whitespaces))
        
        return fields
    }
}

enum CSVImportError: LocalizedError {
    case fileAccessDenied
    case invalidEncoding
    case emptyFile
    case noHeaders
    case invalidFormat
    
    var errorDescription: String? {
        switch self {
        case .fileAccessDenied:
            return "Нет доступа к файлу"
        case .invalidEncoding:
            return "Неверная кодировка файла (требуется UTF-8)"
        case .emptyFile:
            return "Файл пуст"
        case .noHeaders:
            return "В файле отсутствуют заголовки"
        case .invalidFormat:
            return "Неверный формат CSV"
        }
    }
}
