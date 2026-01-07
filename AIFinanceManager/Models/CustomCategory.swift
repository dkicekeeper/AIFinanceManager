//
//  CustomCategory.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation
import SwiftUI

struct CustomCategory: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var emoji: String
    var colorHex: String
    var type: TransactionType
    
    init(id: String = UUID().uuidString, name: String, emoji: String, colorHex: String, type: TransactionType) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.type = type
    }
    
    var color: Color {
        var hexSanitized = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        return Color(red: r, green: g, blue: b)
    }
}
