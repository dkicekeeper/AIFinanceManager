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
    var iconName: String
    var colorHex: String
    var type: TransactionType
    
    init(id: String = UUID().uuidString, name: String, iconName: String? = nil, colorHex: String, type: TransactionType) {
        self.id = id
        self.name = name
        self.iconName = iconName ?? CategoryIcon.iconName(for: name, type: type)
        self.colorHex = colorHex
        self.type = type
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, iconName, colorHex, type
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        type = try container.decode(TransactionType.self, forKey: .type)
        
        if let newIconName = try? container.decode(String.self, forKey: .iconName) {
            iconName = newIconName
        } else {
            iconName = CategoryIcon.iconName(for: name, type: type)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(iconName, forKey: .iconName)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(type, forKey: .type)
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
