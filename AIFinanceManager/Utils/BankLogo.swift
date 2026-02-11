//
//  BankLogo.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI
import UIKit

enum BankLogo: String, Codable, CaseIterable, Identifiable {
    case none = "none"
    case alatauCityBank = "alataucitybank"
    case halykBank = "halyk_bank"
    case kaspi = "kaspi"
    case homeCredit = "Home_Credit"
    case eurasian = "Eurasian"
    case forte = "Forte"
    case otbasy = "Otbasy"
    case rbk = "rbk"
    case centerCredit = "Center_Credit"
    case freedom = "Freedom"
    case jusan = "Jusan"
    case tengri = "tengri"
    case brk = "BRK"
    case kazPost = "kaz_post"
    case altyn = "Altyn"
    case nurBank = "Nur_Bank"
    case bereke = "Bereke"
    case asiaCredit = "AsiaCredit"
    case enpf = "ENPF"
    case kzi = "kzi"
    case shinhan = "shinhan"
    case kbo = "KBO"
    case atf = "ATF"
    case placeholder = "Placeholder"
    case koronaPay = "koronapay"
    case visaPlus = "VisaPlus"
    case tbank = "tbank"
    case uzum = "Uzum"
    case onlinebank = "onlinebank"
    case alfaBank = "alfa_bank"
    case sber = "sber"
    case citi = "citi"
    case vtb = "VTB"
    case ebr = "EBR"
    case bankOfChina = "Bank_of_China"
    case zaman = "Zaman"
    case naoPdg = "NAO_PDG"
    case kcsd = "KCSD"
    case kase = "KASE"
    case hilal = "Hilal"
    case moscowBank = "Moscow_Bank"
    case icbc = "ICBC"
    case comitetKaznacheistva = "Comitet_Kaznacheistva"
    case nbrk = "NBRK"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .none: return "Без логотипа"
        case .alatauCityBank: return "Alatau City Bank"
        case .halykBank: return "Halyk Bank"
        case .kaspi: return "Kaspi"
        case .homeCredit: return "Home Credit Bank"
        case .eurasian: return "Eurasian Bank"
        case .forte: return "Forte Bank"
        case .otbasy: return "Otbasy Bank"
        case .rbk: return "Bank RBK"
        case .centerCredit: return "Bank Center Credit"
        case .freedom: return "Freedom Bank"
        case .jusan: return "Jusan Bank"
        case .tengri: return "Tengri Bank"
        case .brk: return "BRK Bank"
        case .kazPost: return "Qazpost Bank"
        case .altyn: return "Altyn Bank"
        case .nurBank: return "Nur Bank"
        case .bereke: return "Bereke Bank"
        case .asiaCredit: return "Asia Credit Bank"
        case .enpf: return "ENPF"
        case .kzi: return "KZI Bank"
        case .shinhan: return "Shinhan Bank"
        case .kbo: return "KBO"
        case .atf: return "ATF Bank"
        case .placeholder: return "Placeholder"
        case .koronaPay: return "Korona Pay"
        case .visaPlus: return "Visa Plus"
        case .tbank: return "T Bank"
        case .uzum: return "Uzum Bank"
        case .onlinebank: return "Onlinebank"
        case .alfaBank: return "Alfa Bank"
        case .sber: return "Sber Bank"
        case .citi: return "City Bank"
        case .vtb: return "VTB Bank"
        case .ebr: return "EBR"
        case .bankOfChina: return "Bank of China"
        case .zaman: return "Zaman"
        case .naoPdg: return "NAO PDG"
        case .kcsd: return "KCSD"
        case .kase: return "KASE"
        case .hilal: return "Hilal Bank"
        case .moscowBank: return "Moscow Bank"
        case .icbc: return "ICBC"
        case .comitetKaznacheistva: return "Комитет Казначейства"
        case .nbrk: return "NBRK"
        }
    }
    
    @ViewBuilder
    func image(size: CGFloat = 24) -> some View {
        let cornerRadius = size * 0.2 // 20% от размера для corner radius
        
        if self == .none {
            Image(systemName: "building.2")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            // Пытаемся загрузить изображение из Assets
            if let uiImage = UIImage(named: rawValue) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                // Fallback на системную иконку, если изображение не найдено
                Image(systemName: "building.2")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .foregroundStyle(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        }
    }
}
