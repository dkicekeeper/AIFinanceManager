//
//  Subcategory.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation

struct Subcategory: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    
    init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
    }
}

struct CategorySubcategoryLink: Identifiable, Codable, Equatable {
    let id: String
    let categoryId: String
    let subcategoryId: String
    
    init(id: String = UUID().uuidString, categoryId: String, subcategoryId: String) {
        self.id = id
        self.categoryId = categoryId
        self.subcategoryId = subcategoryId
    }
}

struct TransactionSubcategoryLink: Identifiable, Codable, Equatable {
    let id: String
    let transactionId: String
    let subcategoryId: String
    
    init(id: String = UUID().uuidString, transactionId: String, subcategoryId: String) {
        self.id = id
        self.transactionId = transactionId
        self.subcategoryId = subcategoryId
    }
}
