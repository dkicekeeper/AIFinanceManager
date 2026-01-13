//
//  SubscriptionsCardView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct SubscriptionsCardView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    @State private var totalAmount: Decimal = 0
    @State private var isLoadingTotal: Bool = false
    
    private var subscriptions: [RecurringSeries] {
        viewModel.activeSubscriptions
    }
    
    private var baseCurrency: String {
        viewModel.appSettings.baseCurrency
    }
    
    @State private var floatingOffsets: [String: CGSize] = [:]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Подписки")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
//                Spacer()
//                
//                Image(systemName: "chevron.right")
//                    .font(.caption)
//                    .foregroundStyle(.primary)
            }
            
            if subscriptions.isEmpty {
                Text("Нет активных подписок")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            } else {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        if isLoadingTotal {
                            ProgressView()
                                .frame(height: 20)
                        } else {
                            Text(Formatting.formatCurrency(
                                NSDecimalNumber(decimal: totalAmount).doubleValue,
                                currency: baseCurrency
                            ))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        }
                        
                        Text("Активных \(subscriptions.count)")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    
                    Spacer()
                    
                    // Плавающие иконки подписок
                    if !subscriptions.isEmpty {
                        floatingIconsView
                    }
                }
            }
        }
        .padding(16)
//        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
//        .overlay {
//            // Граница для глубины
//            RoundedRectangle(cornerRadius: 20)
//                .stroke(
//                    LinearGradient(
//                        gradient: Gradient(colors: [
//                            Color.white.opacity(0.3),
//                            Color.white.opacity(0.1)
//                        ]),
//                        startPoint: .topLeading,
//                        endPoint: .bottomTrailing
//                    ),
//                    lineWidth: 1
//                )
//        }
//        .overlay(Color.white.opacity(0.001))
//        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        .glassEffect(in: .rect(cornerRadius: AppRadius.lg))
        .task {
            await calculateTotal()
        }
        .onChange(of: subscriptions.count) { _, _ in
            Task {
                await calculateTotal()
            }
        }
        .onChange(of: baseCurrency) { _, _ in
            Task {
                await calculateTotal()
            }
        }
    }

    private func calculateTotal() async {
        guard !subscriptions.isEmpty else {
            await MainActor.run {
                totalAmount = 0
                isLoadingTotal = false
            }
            return
        }
        
        await MainActor.run {
            isLoadingTotal = true
        }
        
        // Загружаем курсы для всех валют
        let currencies = Set(subscriptions.map { $0.currency })
        for currency in currencies {
            if currency != baseCurrency {
                _ = await CurrencyConverter.getExchangeRate(for: currency)
            }
        }
        _ = await CurrencyConverter.getExchangeRate(for: baseCurrency)
        
        // Конвертируем суммы всех подписок в базовую валюту
        var total: Decimal = 0
        
        for subscription in subscriptions {
            let amountDouble = NSDecimalNumber(decimal: subscription.amount).doubleValue
            let convertedAmount: Double
            
            if subscription.currency == baseCurrency {
                convertedAmount = amountDouble
            } else {
                // Сначала пробуем синхронную конвертацию (курсы должны быть в кэше)
                if let converted = CurrencyConverter.convertSync(
                    amount: amountDouble,
                    from: subscription.currency,
                    to: baseCurrency
                ) {
                    convertedAmount = converted
                } else {
                    // Если синхронная конвертация не сработала, используем асинхронную
                    if let asyncConverted = await CurrencyConverter.convert(
                        amount: amountDouble,
                        from: subscription.currency,
                        to: baseCurrency
                    ) {
                        convertedAmount = asyncConverted
                    } else {
                        // Если конвертация невозможна, используем исходную сумму
                        print("⚠️ Не удалось конвертировать \(amountDouble) \(subscription.currency) в \(baseCurrency) для подписки \(subscription.description)")
                        convertedAmount = amountDouble
                    }
                }
            }
            
            total += Decimal(convertedAmount)
        }
        
        await MainActor.run {
            totalAmount = total
            isLoadingTotal = false
        }
    }
    
    private var floatingIconsView: some View {
        ZStack {
            ForEach(Array(subscriptions.prefix(20).enumerated()), id: \.element.id) { index, subscription in
                subscriptionIconView(subscription: subscription, index: index)
                    .offset(floatingOffsets[subscription.id] ?? .zero)
            }
        }
        .frame(width: 80, height: 50)
        .onAppear {
            startFloatingAnimations()
        }
        .onChange(of: subscriptions.count) { _, _ in
            startFloatingAnimations()
        }
    }
    
    private func subscriptionIconView(subscription: RecurringSeries, index: Int) -> some View {
        Group {
            if let brandLogo = subscription.brandLogo {
                brandLogo.image(size: 32)
            } else if let brandId = subscription.brandId, !brandId.isEmpty {
                if brandId.hasPrefix("sf:") {
                    let iconName = String(brandId.dropFirst(3))
                    Image(systemName: iconName)
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                } else if brandId.hasPrefix("icon:") {
                    let iconName = String(brandId.dropFirst(5))
                    Image(systemName: iconName)
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                } else {
                    // Используем BrandLogoView для логотипов из logo.dev
                    BrandLogoView(brandName: brandId, size: 32)
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                }
            } else {
                Image(systemName: "creditcard")
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 32)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
        }
        .overlay(
            Circle()
                .stroke(Color(.systemBackground), lineWidth: 2)
        )
        .offset(x: CGFloat(index % 3) * 12 - 12, y: CGFloat(index / 3) * 12 - 12)
    }
    
    private func startFloatingAnimations() {
        // Генерируем случайные смещения для каждой подписки
        for subscription in subscriptions.prefix(20) {
            let subscriptionId = subscription.id
            let randomX = Double.random(in: -20...20)
            let randomY = Double.random(in: -20...20)
            let duration = Double.random(in: 2.5...4.0)
            
            // Устанавливаем начальное смещение
            floatingOffsets[subscriptionId] = CGSize(width: randomX, height: randomY)
            
            // Создаем анимацию
            withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                let newX = Double.random(in: -20...20)
                let newY = Double.random(in: -20...20)
                floatingOffsets[subscriptionId] = CGSize(width: newX, height: newY)
            }
        }
    }
}

#Preview {
    SubscriptionsCardView(viewModel: TransactionsViewModel())
}
