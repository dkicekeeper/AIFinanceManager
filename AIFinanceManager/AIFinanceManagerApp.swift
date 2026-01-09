//
//  AIFinanceManagerApp.swift
//  AIFinanceManager
//
//  Created by Daulet Kydrali on 06.01.2026.
//

import SwiftUI

@main
struct AIFinanceManagerApp: App {
    @StateObject private var timeFilterManager = TimeFilterManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(timeFilterManager)
        }
    }
}
