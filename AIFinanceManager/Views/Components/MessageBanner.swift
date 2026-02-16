//
//  MessageBanner.swift
//  AIFinanceManager
//
//  Created on 2026-02-16
//  Phase 15: Universal Message Banner Component
//

import SwiftUI

/// Universal message banner component supporting multiple message types
/// Consolidates ErrorMessageView and SuccessMessageView patterns
struct MessageBanner: View {
    let message: String
    let type: MessageType

    @State private var isVisible = false
    @State private var iconScale: CGFloat = 0.5

    enum MessageType {
        case success
        case error
        case warning
        case info

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.triangle"
            case .warning: return "exclamationmark.circle"
            case .info: return "info.circle"
            }
        }

        var tintColor: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            case .warning: return .orange
            case .info: return .blue
            }
        }
    }

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                bannerContent
                    .clipShape(.rect(cornerRadius: AppRadius.pill))
                    .glassEffect(.regular
                        .tint(type.tintColor.opacity(0.15))
                        .interactive())
            } else {
                bannerContent
                    .background(
                        type.tintColor.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: AppRadius.pill)
                    )
            }
        }
        .shadow(color: type.tintColor.opacity(0.3), radius: 8, x: 0, y: 4)
        .scaleEffect(isVisible ? 1 : 0.85)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : -20)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0)) {
                isVisible = true
            }

            withAnimation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0).delay(0.1)) {
                iconScale = 1.0
            }

            HapticManager.notification(type: type.hapticType)
        }
    }

    private var bannerContent: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: type.icon)
                .font(.system(size: AppIconSize.md))
                .foregroundStyle(type.tintColor)
                .scaleEffect(iconScale)
                .animation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0), value: iconScale)

            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.md)
    }
}

// MARK: - Haptic Feedback Extension

private extension MessageBanner.MessageType {
    var hapticType: UINotificationFeedbackGenerator.FeedbackType {
        switch self {
        case .success: return .success
        case .error: return .error
        case .warning: return .warning
        case .info: return .success
        }
    }
}

// MARK: - Convenience Initializers

extension MessageBanner {
    /// Success message banner (green checkmark)
    static func success(_ message: String) -> MessageBanner {
        MessageBanner(message: message, type: .success)
    }

    /// Error message banner (red triangle)
    static func error(_ message: String) -> MessageBanner {
        MessageBanner(message: message, type: .error)
    }

    /// Warning message banner (orange circle)
    static func warning(_ message: String) -> MessageBanner {
        MessageBanner(message: message, type: .warning)
    }

    /// Info message banner (blue circle)
    static func info(_ message: String) -> MessageBanner {
        MessageBanner(message: message, type: .info)
    }
}

// MARK: - Preview

#Preview("All Message Types") {
    VStack(spacing: AppSpacing.lg) {
        MessageBanner.success("Transaction saved successfully")
        MessageBanner.error("Failed to load data")
        MessageBanner.warning("Low balance detected")
        MessageBanner.info("Sync completed")
    }
    .padding()
}

#Preview("Animated Demo") {
    struct AnimatedDemoView: View {
        @State private var showSuccess = false
        @State private var showError = false
        @State private var showWarning = false
        @State private var showInfo = false

        var body: some View {
            VStack(spacing: AppSpacing.xl) {
                if showSuccess {
                    MessageBanner.success("Payment completed!")
                }

                if showError {
                    MessageBanner.error("Network connection failed")
                }

                if showWarning {
                    MessageBanner.warning("Balance is running low")
                }

                if showInfo {
                    MessageBanner.info("New features available")
                }

                Spacer()

                VStack(spacing: AppSpacing.md) {
                    Button("Show Success") {
                        withAnimation {
                            showSuccess.toggle()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button("Show Error") {
                        withAnimation {
                            showError.toggle()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    Button("Show Warning") {
                        withAnimation {
                            showWarning.toggle()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Button("Show Info") {
                        withAnimation {
                            showInfo.toggle()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    Button("Reset All") {
                        withAnimation {
                            showSuccess = false
                            showError = false
                            showWarning = false
                            showInfo = false
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
    }

    return AnimatedDemoView()
}
