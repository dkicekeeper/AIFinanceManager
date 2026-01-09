//
//  CategoryEmoji.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation

enum CategoryEmoji {
    static func iconName(for category: String, type: TransactionType, customCategories: [CustomCategory] = []) -> String {
        // Для операций перевода всегда возвращаем arrow.left.arrow.right
        if type == .internalTransfer {
            return "arrow.left.arrow.right"
        }
        
        // Сначала проверяем пользовательские категории
        if let custom = customCategories.first(where: { $0.name.lowercased() == category.lowercased() && $0.type == type }) {
            return custom.iconName
        }
        
        // Затем дефолтные (поддержка английских и русских названий)
        let key = category.lowercased()
        let map: [String: String] = [
            // Английские
            "income": "dollar.circle.fill",
            "food": "hamburger.fill",
            "transport": "car.fill",
            "shopping": "bag.fill",
            "entertainment": "sparkles",
            "bills": "lightbulb.fill",
            "health": "cross.case.fill",
            "education": "graduationcap.fill",
            "other": "banknote.fill",
            "salary": "briefcase.fill",
            "delivery": "box.fill",
            "gifts": "gift.fill",
            "travel": "airplane.fill",
            "groceries": "cart.fill",
            "coffee": "cup.and.saucer.fill",
            "subscriptions": "tv.fill",
            "transfer": "arrow.left.arrow.right",
            // Русские
            "доход": "dollar.circle.fill",
            "доходы": "dollar.circle.fill",
            "еда": "hamburger.fill",
            "продукты": "cart.fill",
            "транспорт": "car.fill",
            "покупки": "bag.fill",
            "развлечения": "sparkles",
            "счета": "lightbulb.fill",
            "здоровье": "cross.case.fill",
            "образование": "graduationcap.fill",
            "другое": "banknote.fill",
            "зарплата": "briefcase.fill",
            "доставка": "box.fill",
            "подарки": "gift.fill",
            "путешествия": "airplane.fill",
            "кофе": "cup.and.saucer.fill",
            "подписки": "tv.fill",
            "перевод": "arrow.left.arrow.right",
            "такси": "car.fill",
            "автобус": "bus.fill",
            "метро": "tram.fill",
            "ресторан": "fork.knife",
            "кафе": "cup.and.saucer.fill",
            "обед": "fork.knife",
            "ужин": "fork.knife",
            "магазин": "cart.fill",
            "супермаркет": "cart.fill",
            "аптека": "pills.fill",
            "больница": "cross.case.fill",
            "врач": "cross.case.fill",
            "лечение": "cross.case.fill",
            "школа": "graduationcap.fill",
            "университет": "graduationcap.fill",
            "курсы": "graduationcap.fill",
            "кино": "film.fill",
            "театр": "theatermasks.fill",
            "концерт": "music.note",
            "спорт": "sportscourt.fill",
            "фитнес": "dumbbell.fill",
            "одежда": "tshirt.fill",
            "обувь": "shoe.fill",
            "техника": "iphone",
            "компьютер": "laptopcomputer",
            "телефон": "iphone",
            "интернет": "globe",
            "связь": "phone.fill",
            "коммунальные": "lightbulb.fill",
            "электричество": "bolt.fill",
            "газ": "flame.fill",
            "вода": "drop.fill",
            "квартплата": "house.fill",
            "аренда": "house.fill",
            "ипотека": "building.columns.fill",
            "кредит": "creditcard.fill",
            "страховка": "shield.fill",
            "налоги": "chart.bar.fill",
            "пенсия": "person.fill",
            "пособие": "dollar.circle.fill",
            "дивиденды": "chart.line.uptrend.xyaxis",
            "инвестиции": "chart.bar.fill",
            "бизнес": "briefcase.fill",
            "услуги": "wrench.and.screwdriver.fill",
            "ремонт": "hammer.fill",
            "красота": "paintbrush.fill",
            "парикмахер": "scissors",
            "салон": "paintbrush.fill",
            "книги": "book.fill",
            "игры": "gamecontroller.fill",
            "музыка": "music.note",
            "стриминг": "tv.fill",
            "подписка": "tv.fill",
            "бензин": "fuelpump.fill",
            "парковка": "parking.circle.fill",
            "мойка": "shower.fill",
            "ремонт авто": "wrench.and.screwdriver.fill",
            "страховка авто": "car.fill",
            "проезд": "bus.fill",
            "билет": "ticket.fill",
            "отель": "building.2.fill",
            "отпуск": "airplane.fill",
            "туризм": "map.fill",
            "виза": "key.fill",
            "багаж": "suitcase.fill"
        ]
        
        // Проверяем точное совпадение
        if let value = map[key] { return value }
        
        // Проверяем частичное совпадение (если название содержит ключевое слово)
        for (keyword, iconName) in map {
            if key.contains(keyword) || keyword.contains(key) {
                return iconName
            }
        }
        
        return type == .income ? "dollar.circle.fill" : "banknote.fill"
    }
    
    // Обратная совместимость - для миграции старых данных
    static func emoji(for category: String, type: TransactionType, customCategories: [CustomCategory] = []) -> String {
        return iconName(for: category, type: type, customCategories: customCategories)
    }
    
    // Конвертация эмодзи в SF Symbol для миграции
    static func iconNameFromEmoji(_ emoji: String) -> String? {
        let emojiToIconMap: [String: String] = [
            "💵": "dollar.circle.fill",
            "🍔": "hamburger.fill",
            "🚕": "car.fill",
            "🛍️": "bag.fill",
            "🎉": "sparkles",
            "💡": "lightbulb.fill",
            "🏥": "cross.case.fill",
            "🎓": "graduationcap.fill",
            "💰": "banknote.fill",
            "💼": "briefcase.fill",
            "📦": "box.fill",
            "🎁": "gift.fill",
            "✈️": "airplane.fill",
            "🛒": "cart.fill",
            "☕️": "cup.and.saucer.fill",
            "📺": "tv.fill",
            "↔️": "arrow.left.arrow.right",
            "🚌": "bus.fill",
            "🚇": "tram.fill",
            "🍽️": "fork.knife",
            "💊": "pills.fill",
            "🎬": "film.fill",
            "🎭": "theatermasks.fill",
            "🎵": "music.note",
            "⚽️": "sportscourt.fill",
            "🏋️": "dumbbell.fill",
            "👕": "tshirt.fill",
            "👟": "shoe.fill",
            "📱": "iphone",
            "💻": "laptopcomputer",
            "🌐": "globe",
            "📞": "phone.fill",
            "⚡️": "bolt.fill",
            "🔥": "flame.fill",
            "💧": "drop.fill",
            "🏠": "house.fill",
            "🏦": "building.columns.fill",
            "💳": "creditcard.fill",
            "🛡️": "shield.fill",
            "📊": "chart.bar.fill",
            "👴": "person.fill",
            "📈": "chart.line.uptrend.xyaxis",
            "🔧": "wrench.and.screwdriver.fill",
            "🔨": "hammer.fill",
            "💅": "paintbrush.fill",
            "✂️": "scissors",
            "📚": "book.fill",
            "🎮": "gamecontroller.fill",
            "⛽️": "fuelpump.fill",
            "🅿️": "parking.circle.fill",
            "🚿": "shower.fill",
            "🚗": "car.fill",
            "🎫": "ticket.fill",
            "🏨": "building.2.fill",
            "🗺️": "map.fill",
            "🛂": "key.fill",
            "🧳": "suitcase.fill"
        ]
        return emojiToIconMap[emoji]
    }
}
