//
//  LogoService.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation
import UIKit

/// Сервис для загрузки и кеширования логотипов из logo.dev
final class LogoService {
    static let shared = LogoService()
    
    // Memory cache с ограничением в 200 изображений
    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCache = LogoDiskCache.shared
    
    private init() {
        // Настраиваем memory cache
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
        
        // Очищаем кеш при получении memory warning
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.memoryCache.removeAllObjects()
        }
    }
    
    /// Загружает логотип бренда
    /// - Parameter brandName: Название бренда
    /// - Returns: UIImage или nil при ошибке
    /// - Throws: Ошибки загрузки
    @MainActor
    func logoImage(brandName: String) async throws -> UIImage? {
        // Проверяем доступность сервиса
        guard LogoDevConfig.isAvailable else {
            return nil
        }
        
        let normalizedName = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            return nil
        }
        
        // 1. Проверяем memory cache
        if let cachedImage = memoryCache.object(forKey: normalizedName as NSString) {
            return cachedImage
        }
        
        // 2. Проверяем disk cache
        if let diskImage = diskCache.load(for: normalizedName) {
            // Сохраняем в memory cache
            memoryCache.setObject(diskImage, forKey: normalizedName as NSString)
            return diskImage
        }
        
        // 3. Загружаем с logo.dev
        guard let url = LogoDevConfig.logoURL(for: normalizedName) else {
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            // Проверяем HTTP статус
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               let image = UIImage(data: data) {
                // 4. Сохраняем в кеши
                memoryCache.setObject(image, forKey: normalizedName as NSString)
                diskCache.save(image, for: normalizedName)
                
                return image
            }
        } catch {
            // Логируем ошибку, но не падаем
            print("LogoService: Failed to load logo for '\(normalizedName)': \(error.localizedDescription)")
        }
        
        return nil
    }
    
    /// Предзагружает логотипы для списка брендов
    /// - Parameter brandNames: Массив названий брендов
    nonisolated func prefetch(brandNames: [String]) {
        guard LogoDevConfig.isAvailable else { return }
        
        Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                for brandName in brandNames {
                    group.addTask { @MainActor in
                        // Пытаемся загрузить (не важно, успешно или нет)
                        _ = try? await LogoService.shared.logoImage(brandName: brandName)
                    }
                }
            }
        }
    }
    
    /// Проверяет наличие логотипа в кеше (memory или disk)
    /// - Parameter brandName: Название бренда
    /// - Returns: true, если логотип есть в кеше
    @MainActor
    func isCached(brandName: String) -> Bool {
        let normalizedName = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Проверяем memory cache
        if memoryCache.object(forKey: normalizedName as NSString) != nil {
            return true
        }
        
        // Проверяем disk cache
        return diskCache.exists(for: normalizedName)
    }
}
