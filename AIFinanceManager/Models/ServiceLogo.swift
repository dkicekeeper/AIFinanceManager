//
//  ServiceLogo.swift
//  AIFinanceManager
//
//  Popular service brands organized by category
//

import Foundation

enum ServiceLogo: String, CaseIterable, Identifiable {
    // MARK: - Streaming & Entertainment
    case youtube = "youtube.com"
    case netflix = "netflix.com"
    case spotify = "spotify.com"
    case appleMusic = "music.apple.com"
    case amazonPrime = "primevideo.com"
    case amazonMusic = "music.amazon.com"
    case disneyPlus = "disneyplus.com"
    case appleTVPlus = "tv.apple.com"
    case hulu = "hulu.com"
    case hboMax = "max.com"
    case paramountPlus = "paramountplus.com"
    case youtubeMusic = "music.youtube.com"
    case pandora = "pandora.com"
    case audible = "audible.com"

    // MARK: - Productivity & Cloud
    case notion = "notion.so"
    case icloud = "icloud.com"
    case googleDrive = "drive.google.com"
    case googleOne = "one.google.com"
    case dropbox = "dropbox.com"
    case adobeCloud = "adobe.com"
    case microsoft365 = "microsoft.com"
    case canva = "canva.com"
    case figma = "figma.com"
    case framer = "framer.com"
    case grammarly = "grammarly.com"
    case slack = "slack.com"
    case trello = "trello.com"
    case zoom = "zoom.us"
    case cleanshot = "cleanshot.com"
    case setapp = "setapp.com"

    // MARK: - Social & Communication
    case linkedin = "linkedin.com"
    case telegram = "telegram.org"
    case twitter = "x.com"
    case tinder = "tinder.com"
    case bumble = "bumble.com"
    case hinge = "hinge.co"

    // MARK: - Fitness & Health
    case calm = "calm.com"
    case headspace = "headspace.com"
    case strava = "strava.com"
    case appleFitnessPlus = "apple.com/apple-fitness-plus"
    case peloton = "onepeloton.com"
    case dailyBurn = "dailyburn.com"
    case waterMinder = "waterminder.com"
    case whoop = "whoop.com"

    // MARK: - Gaming
    case playstationPlus = "playstation.com"
    case xboxGamePass = "xbox.com"
    case nintendoOnline = "nintendo.com"
    case eaPlay = "ea.com"
    case appleArcade = "apple.com/apple-arcade"

    // MARK: - Developer Tools & AI
    case cursor = "cursor.sh"
    case claude = "claude.ai"
    case chatGPT = "chat.openai.com"
    case gemini = "gemini.google.com"
    case midjourney = "midjourney.com"
    case github = "github.com"
    case appleDeveloper = "developer.apple.com"

    // MARK: - Services
    case revolut = "revolut.com"
    case onePassword = "1password.com"
    case nordVPN = "nordvpn.com"
    case patreon = "patreon.com"
    case nytimes = "nytimes.com"
    case scribd = "scribd.com"
    case skillshare = "skillshare.com"
    case duolingo = "duolingo.com"
    case lifecell = "lifecell.ua"
    case vodafone = "vodafone.com"
    case fuboTV = "fubo.tv"
    case appleOne = "apple.com/apple-one"
    case appleCarePlus = "apple.com/support/products"
    case wwf = "wwf.org"
    case googlePlay = "play.google.com"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .youtube: return "YouTube"
        case .netflix: return "Netflix"
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        case .amazonPrime: return "Amazon Prime"
        case .amazonMusic: return "Amazon Music"
        case .disneyPlus: return "Disney+"
        case .appleTVPlus: return "Apple TV+"
        case .hulu: return "Hulu"
        case .hboMax: return "HBO Max"
        case .paramountPlus: return "Paramount+"
        case .youtubeMusic: return "YouTube Music"
        case .pandora: return "Pandora"
        case .audible: return "Audible"
        case .notion: return "Notion"
        case .icloud: return "iCloud"
        case .googleDrive: return "Google Drive"
        case .googleOne: return "Google One"
        case .dropbox: return "Dropbox"
        case .adobeCloud: return "Adobe Cloud"
        case .microsoft365: return "Microsoft 365"
        case .canva: return "Canva"
        case .figma: return "Figma"
        case .framer: return "Framer"
        case .grammarly: return "Grammarly"
        case .slack: return "Slack"
        case .trello: return "Trello"
        case .zoom: return "Zoom"
        case .cleanshot: return "CleanShot"
        case .setapp: return "Setapp"
        case .linkedin: return "LinkedIn"
        case .telegram: return "Telegram"
        case .twitter: return "X (Twitter)"
        case .tinder: return "Tinder"
        case .bumble: return "Bumble"
        case .hinge: return "Hinge"
        case .calm: return "Calm"
        case .headspace: return "Headspace"
        case .strava: return "Strava"
        case .appleFitnessPlus: return "Apple Fitness+"
        case .peloton: return "Peloton"
        case .dailyBurn: return "Daily Burn"
        case .waterMinder: return "Water Minder"
        case .whoop: return "WHOOP"
        case .playstationPlus: return "PlayStation Plus"
        case .xboxGamePass: return "Xbox Game Pass"
        case .nintendoOnline: return "Nintendo Online"
        case .eaPlay: return "EA Play"
        case .appleArcade: return "Apple Arcade"
        case .cursor: return "Cursor"
        case .claude: return "Claude"
        case .chatGPT: return "ChatGPT"
        case .gemini: return "Gemini"
        case .midjourney: return "Midjourney"
        case .github: return "GitHub"
        case .appleDeveloper: return "Apple Developer"
        case .revolut: return "Revolut"
        case .onePassword: return "1Password"
        case .nordVPN: return "NordVPN"
        case .patreon: return "Patreon"
        case .nytimes: return "The New York Times"
        case .scribd: return "Scribd"
        case .skillshare: return "Skillshare"
        case .duolingo: return "Duolingo"
        case .lifecell: return "Lifecell"
        case .vodafone: return "Vodafone"
        case .fuboTV: return "FuboTV"
        case .appleOne: return "Apple One"
        case .appleCarePlus: return "AppleCare+"
        case .wwf: return "WWF"
        case .googlePlay: return "Google Play"
        }
    }

    var category: ServiceCategory {
        switch self {
        case .youtube, .netflix, .spotify, .appleMusic, .amazonPrime,
             .amazonMusic, .disneyPlus, .appleTVPlus, .hulu, .hboMax,
             .paramountPlus, .youtubeMusic, .pandora, .audible:
            return .streaming

        case .notion, .icloud, .googleDrive, .googleOne, .dropbox,
             .adobeCloud, .microsoft365, .canva, .figma, .framer,
             .grammarly, .slack, .trello, .zoom, .cleanshot, .setapp:
            return .productivity

        case .linkedin, .telegram, .twitter, .tinder, .bumble, .hinge:
            return .social

        case .calm, .headspace, .strava, .appleFitnessPlus, .peloton,
             .dailyBurn, .waterMinder, .whoop:
            return .fitness

        case .playstationPlus, .xboxGamePass, .nintendoOnline, .eaPlay, .appleArcade:
            return .gaming

        case .cursor, .claude, .chatGPT, .gemini, .midjourney, .github, .appleDeveloper:
            return .devTools

        case .revolut, .onePassword, .nordVPN, .patreon, .nytimes,
             .scribd, .skillshare, .duolingo, .lifecell, .vodafone,
             .fuboTV, .appleOne, .appleCarePlus, .wwf, .googlePlay:
            return .services
        }
    }
}

enum ServiceCategory: String, CaseIterable {
    case streaming
    case productivity
    case social
    case fitness
    case gaming
    case devTools
    case services

    var localizedTitle: String {
        switch self {
        case .streaming:
            return String(localized: "iconPicker.streaming")
        case .productivity:
            return String(localized: "iconPicker.productivity")
        case .social:
            return String(localized: "iconPicker.social")
        case .fitness:
            return String(localized: "iconPicker.fitness")
        case .gaming:
            return String(localized: "iconPicker.gaming")
        case .devTools:
            return String(localized: "iconPicker.devTools")
        case .services:
            return String(localized: "iconPicker.services")
        }
    }

    func services() -> [ServiceLogo] {
        ServiceLogo.allCases.filter { $0.category == self }
    }
}
