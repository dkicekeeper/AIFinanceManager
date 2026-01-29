//
//  LogoSearchView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct LogoSearchView: View {
    @Binding var selectedBrandName: String?
    @Environment(\.dismiss) var dismiss
    
    @State private var searchText: String = ""
    @State private var searchResults: [LogoSearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if isLoading {
                    Spacer()
                    ProgressView("Поиск...")
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: AppIconSize.xxxl))
                            .foregroundColor(AppColors.warning)
                        Text(error)
                            .font(AppTypography.bodyPrimary)
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .cardContentPadding()
                    Spacer()
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    Spacer()
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: AppIconSize.xxxl))
                            .foregroundColor(AppColors.textSecondary)
                        Text("Введите название бренда для поиска")
                            .font(AppTypography.bodyPrimary)
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .cardContentPadding()
                    Spacer()
                } else {
                    List {
                        ForEach(searchResults) { result in
                            LogoSearchResultRow(
                                result: result,
                                isSelected: selectedBrandName == (result.domain ?? result.name),
                                onSelect: {
                                    // Сохраняем domain если есть, иначе name
                                    selectedBrandName = result.domain ?? result.name
                                    dismiss()
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Поиск логотипа")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Введите название бренда")
            .onSubmit(of: .search) {
                performSearch()
            }
            .onChange(of: searchText) { _, newValue in
                // Автоматический поиск при вводе (с небольшой задержкой)
                if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 секунды
                        if searchText == newValue {
                            performSearch()
                        }
                    }
                } else {
                    searchResults = []
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
    
    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            errorMessage = nil
            return
        }
        
        guard LogoDevConfig.isAvailable else {
            errorMessage = "Сервис логотипов недоступен. Проверьте настройки."
            searchResults = []
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            // Пробуем несколько вариантов поиска: название, название.com, название.net и т.д.
            let searchVariants = generateSearchVariants(for: query)
            var foundResults: [LogoSearchResult] = []
            
            for variant in searchVariants {
                guard let searchURL = LogoDevConfig.searchURL(for: variant) else {
                    continue
                }
                
                #if DEBUG
                print("LogoSearchView: Searching for '\(variant)' at \(searchURL.absoluteString)")
                #endif
                
                var request = URLRequest(url: searchURL)
                request.httpMethod = "GET"
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                
                // Добавляем токен в заголовок Authorization или в query параметр
                if let token = LogoDevConfig.token {
                    // Попробуем сначала через Authorization заголовок
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    
                    // Также добавляем в query параметр на случай, если API требует его там
                    if var urlComponents = URLComponents(url: searchURL, resolvingAgainstBaseURL: false) {
                        var queryItems = urlComponents.queryItems ?? []
                        queryItems.append(URLQueryItem(name: "token", value: token))
                        urlComponents.queryItems = queryItems
                        if let newURL = urlComponents.url {
                            request.url = newURL
                        }
                    }
                }
                
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continue
                    }
                    
                    #if DEBUG
                    print("LogoSearchView: Response status for '\(variant)': \(httpResponse.statusCode)")
                    #endif
                    
                    if httpResponse.statusCode == 200 {
                        // Парсим JSON ответ
                        let decoder = JSONDecoder()
                        let searchResponse = try decoder.decode(LogoSearchResponse.self, from: data)
                        
                        let results = searchResponse.allResults
                        if !results.isEmpty {
                            foundResults.append(contentsOf: results)
                            // Продолжаем поиск по всем вариантам, чтобы собрать все результаты
                        }
                    }
                } catch {
                    // Продолжаем со следующим вариантом
                    #if DEBUG
                    print("LogoSearchView: Error for variant '\(variant)': \(error.localizedDescription)")
                    #endif
                    continue
                }
            }
            
            await MainActor.run {
                if foundResults.isEmpty {
                    // Если результатов нет, создаем фиктивный результат с введенным названием
                    // Попробуем добавить .com к названию для прямого доступа к логотипу
                    let fallbackResult = LogoSearchResult(
                        id: UUID().uuidString,
                        name: query,
                        domain: query.contains(".") ? nil : "\(query.lowercased()).com",
                        logo: nil
                    )
                    searchResults = [fallbackResult]
                } else {
                    // Убираем дубликаты по domain или name
                    var uniqueResults: [LogoSearchResult] = []
                    var seenDomains = Set<String>()
                    var seenNames = Set<String>()
                    
                    for result in foundResults {
                        let key = result.domain ?? result.name
                        if !seenDomains.contains(key) && !seenNames.contains(result.name) {
                            uniqueResults.append(result)
                            if let domain = result.domain {
                                seenDomains.insert(domain)
                            }
                            seenNames.insert(result.name)
                        }
                    }
                    
                    searchResults = uniqueResults
                }
                isLoading = false
            }
        }
    }
    
    /// Генерирует варианты поиска: название, название.com, название.net и т.д.
    private func generateSearchVariants(for query: String) -> [String] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var variants: [String] = [normalized]
        
        // Если уже есть домен, не добавляем варианты
        if normalized.contains(".") {
            return variants
        }
        
        // Добавляем варианты с популярными доменами
        let domains = ["com", "net", "org", "io", "co", "app"]
        for domain in domains {
            variants.append("\(normalized).\(domain)")
        }
        
        return variants
    }
}

struct LogoSearchResultRow: View {
    let result: LogoSearchResult
    let isSelected: Bool
    let onSelect: () -> Void
    
    // Используем domain если есть, иначе name для получения логотипа
    private var logoIdentifier: String {
        result.domain ?? result.name
    }
    
    // Отображаемое название
    private var displayName: String {
        if let domain = result.domain, domain != result.name {
            return "\(result.name) (\(domain))"
        }
        return result.name
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: AppSpacing.md) {
                // Показываем логотип через AsyncImage
                if let url = LogoDevConfig.logoURL(for: logoIdentifier) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(width: AppIconSize.avatar, height: AppIconSize.avatar)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: AppIconSize.avatar, height: AppIconSize.avatar)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                        case .failure(_):
                            Image(systemName: "photo")
                                .font(.system(size: AppIconSize.lg))
                                .foregroundColor(AppColors.textSecondary)
                                .frame(width: AppIconSize.avatar, height: AppIconSize.avatar)
                        @unknown default:
                            Image(systemName: "photo")
                                .font(.system(size: AppIconSize.lg))
                                .foregroundColor(AppColors.textSecondary)
                                .frame(width: AppIconSize.avatar, height: AppIconSize.avatar)
                        }
                    }
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: AppIconSize.lg))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: AppIconSize.avatar, height: AppIconSize.avatar)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(result.name)
                        .font(AppTypography.bodyPrimary)
                        .foregroundColor(AppColors.textPrimary)

                    if let domain = result.domain, domain != result.name {
                        Text(domain)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(AppColors.accent)
                }
            }
            .padding(.vertical, AppSpacing.xs)
        }
    }
}

#Preview {
    LogoSearchView(selectedBrandName: .constant(nil))
}
