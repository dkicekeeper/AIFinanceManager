//
//  AIFinanceManagerApp.swift
//  AIFinanceManager
//
//  Created by Daulet Kydrali on 06.01.2026.
//

import SwiftUI
import UIKit

@main
struct AIFinanceManagerApp: App {
    @StateObject private var timeFilterManager = TimeFilterManager()
    
    init() {
        // Глобальная настройка navigation bar для прозрачного фона
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(timeFilterManager)
        }
    }
}
