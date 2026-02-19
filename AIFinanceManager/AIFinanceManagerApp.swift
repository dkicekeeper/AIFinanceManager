//
//  AIFinanceManagerApp.swift
//  AIFinanceManager
//
//  Created by Daulet Kydrali on 06.01.2026.
//

import SwiftUI

@main
struct AIFinanceManagerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var timeFilterManager = TimeFilterManager()
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(timeFilterManager)
                .environment(coordinator)
                .environment(coordinator.transactionStore)
        }
    }
}
