//
//  ImageBrightnessCalculator.swift
//  AIFinanceManager
//
//  Created on 2026
//  Performance optimization: Centralized brightness calculation
//

import UIKit

/// Утилита для вычисления яркости изображения
/// Используется для адаптивного выбора цвета текста на фоне обоев
enum ImageBrightnessCalculator {
    /// Вычисляет среднюю яркость изображения (0.0 = темное, 1.0 = светлое)
    ///
    /// Использует down-scaled версию (100x100) для быстрого анализа.
    /// Алгоритм основан на формуле относительной яркости (luminance):
    /// brightness = 0.299 * R + 0.587 * G + 0.114 * B
    ///
    /// - Parameter image: Изображение для анализа
    /// - Returns: Значение яркости от 0.0 (черное) до 1.0 (белое), или 0.5 при ошибке
    nonisolated static func calculate(from image: UIImage) -> CGFloat {
        guard let cgImage = image.cgImage else {
            return 0.5 // По умолчанию средняя яркость
        }

        // Используем уменьшенную версию для производительности
        // 100x100 = 10,000 пикселей достаточно для точной оценки
        let size = CGSize(width: 100, height: 100)

        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return 0.5
        }

        // Используем низкое качество интерполяции для скорости
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))

        guard let data = context.data else {
            return 0.5
        }

        let ptr = data.bindMemory(to: UInt8.self, capacity: Int(size.width * size.height * 4))
        var totalBrightness: CGFloat = 0
        let pixelCount = Int(size.width * size.height)

        // Вычисляем яркость каждого пикселя (используя формулу luminance)
        for i in 0..<pixelCount {
            let offset = i * 4
            let r = CGFloat(ptr[offset])
            let g = CGFloat(ptr[offset + 1])
            let b = CGFloat(ptr[offset + 2])

            // Формула относительной яркости (luminance)
            // Зеленый имеет больший вес, так как человеческий глаз более чувствителен к нему
            let brightness = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            totalBrightness += brightness
        }

        return totalBrightness / CGFloat(pixelCount)
    }

    /// Определяет, является ли изображение темным (яркость < 0.5)
    /// - Parameter image: Изображение для анализа
    /// - Returns: true если изображение темное, false если светлое
    nonisolated static func isDark(_ image: UIImage) -> Bool {
        return calculate(from: image) < 0.5
    }
}
