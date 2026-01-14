//
//  BrandLogoView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

/// SwiftUI компонент для отображения логотипа бренда с загрузкой из logo.dev
struct BrandLogoView: View {
    let brandName: String?
    let size: CGFloat
    
    @State private var logoURL: URL?
    
    init(brandName: String?, size: CGFloat = 32) {
        self.brandName = brandName
        self.size = size
    }
    
    var body: some View {
        Group {
            if let url = logoURL {
                // Используем AsyncImage для прямой загрузки из logo.dev
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: size, height: size)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: size, height: size)
                            .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
                    case .failure(_):
                        // Fallback: SF Symbol
                        fallbackIcon
                    @unknown default:
                        fallbackIcon
                    }
                }
            } else {
                // Fallback: SF Symbol (если нет URL)
                fallbackIcon
            }
        }
        .onAppear {
            updateURL()
        }
        .onChange(of: brandName) { _, _ in
            updateURL()
        }
    }
    
    private var fallbackIcon: some View {
        Image(systemName: "creditcard")
            .font(.system(size: size * 0.6))
            .foregroundColor(.secondary)
            .frame(width: size, height: size)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
    
    private func updateURL() {
        guard let brandName = brandName,
              !brandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              LogoDevConfig.isAvailable else {
            logoURL = nil
            return
        }
        
        let url = LogoDevConfig.logoURL(for: brandName)
        #if DEBUG
        if let url = url {
            print("BrandLogoView: Setting URL for '\(brandName)': \(url.absoluteString)")
        } else {
            print("BrandLogoView: Failed to generate URL for '\(brandName)'")
        }
        #endif
        logoURL = url
    }
}

#Preview {
    VStack(spacing: 20) {
        BrandLogoView(brandName: "Netflix", size: 40)
        BrandLogoView(brandName: "Spotify", size: 32)
        BrandLogoView(brandName: nil, size: 32)
    }
    .padding()
}
