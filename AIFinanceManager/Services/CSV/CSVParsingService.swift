//
//  CSVParsingService.swift
//  AIFinanceManager
//
//  Created on 2026-02-03
//  CSV Import Refactoring Phase 2
//

import Foundation

/// Service for parsing CSV files with optimizations for large files
/// Delegates to CSVImporter for core parsing logic
@MainActor
class CSVParsingService: CSVParsingServiceProtocol {

    // MARK: - CSVParsingServiceProtocol

    func parseFile(from url: URL) async throws -> CSVFile {
        // Delegate to existing CSVImporter which handles:
        // - Security-scoped resource access
        // - Temporary file management
        // - Multiple encoding detection (UTF-8, UTF-16, Windows CP1251)
        return try CSVImporter.parseCSV(from: url)
    }

    func parseContent(_ content: String) async throws -> CSVFile {
        // Parse content directly
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            throw CSVImportError.emptyFile
        }

        // Parse CSV with quote handling
        var parsedLines: [[String]] = []
        parsedLines.reserveCapacity(lines.count) // Pre-allocate for performance

        for line in lines {
            let fields = parseCSVLine(line)
            parsedLines.append(fields)
        }

        guard let headers = parsedLines.first else {
            throw CSVImportError.noHeaders
        }

        let expectedColumnCount = headers.count

        // Normalize rows - pad missing columns with empty values
        var rows = Array(parsedLines.dropFirst())
        rows = rows.map { normalizeRow($0, expectedColumnCount: expectedColumnCount) }

        let preview = Array(rows.prefix(5))

        return CSVFile(headers: headers, rows: rows, preview: preview)
    }

    // MARK: - Private Helpers

    /// Parses a single CSV line with quote handling
    /// Supports quoted fields with embedded commas and escaped quotes
    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        fields.reserveCapacity(10) // Average 10 columns per CSV

        var currentField = ""
        currentField.reserveCapacity(50) // Average field length

        var insideQuotes = false

        for char in line {
            if char == "\"" {
                if insideQuotes {
                    // Check for escaped quote (double quote)
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
                currentField.reserveCapacity(50)
            } else {
                currentField.append(char)
            }
        }

        // Add last field
        fields.append(currentField.trimmingCharacters(in: .whitespaces))

        return fields
    }

    /// Normalizes row to expected column count
    /// Pads missing columns with empty strings, truncates extra columns
    private func normalizeRow(_ row: [String], expectedColumnCount: Int) -> [String] {
        if row.count == expectedColumnCount {
            return row
        } else if row.count < expectedColumnCount {
            // Pad missing columns
            return row + Array(repeating: "", count: expectedColumnCount - row.count)
        } else {
            // Truncate extra columns
            return Array(row.prefix(expectedColumnCount))
        }
    }
}
