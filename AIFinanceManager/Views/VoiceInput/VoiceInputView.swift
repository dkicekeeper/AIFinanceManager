//
//  VoiceInputView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI
import UIKit

struct VoiceInputView: View {
    @ObservedObject var voiceService: VoiceInputService
    @Environment(\.dismiss) var dismiss
    let onComplete: (String) -> Void
    let parser: VoiceInputParser

    @State private var showingPermissionAlert = false
    @State private var permissionMessage = ""
    @State private var recognizedEntities: [RecognizedEntity] = []
    @State private var showingErrorAlert = false
    @State private var errorAlertMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Spacer()
                
                // Live транскрипция с подсветкой сущностей (по центру)
                ScrollView {
                    VStack {
                        Spacer()
                        
                        if voiceService.transcribedText.isEmpty {
                            Text(String(localized: "voice.speak"))
                                .font(AppTypography.h4)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, AppSpacing.lg)
                        } else {
                            HighlightedText(
                                text: voiceService.transcribedText,
                                entities: recognizedEntities,
                                font: AppTypography.h4
                            )
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.lg)
                        }
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: VoiceInputConstants.transcriptionMaxHeight)

                // VAD Toggle (показываем только когда НЕ записываем)
                if !voiceService.isRecording {
                    VStack(spacing: AppSpacing.sm) {
                        Toggle(String(localized: "voice.vadToggle"), isOn: $voiceService.isVADEnabled)
                            .font(AppTypography.caption)
                            .padding(.horizontal, AppSpacing.lg)

                        Text(String(localized: "voice.vadDescription"))
                            .font(AppTypography.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.lg)
                    }
                    .padding(.vertical, AppSpacing.md)
                }

                // Индикатор записи (Siri-like wave animation) - чуть выше bottom toolbar
                if voiceService.isRecording {
                    SiriWaveRecordingView()
                        .padding(.bottom, AppSpacing.xl)
                }

                // Bottom toolbar с кнопкой стоп
                if voiceService.isRecording {
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            voiceService.stopRecording()
                            // Даем время на финализацию перед вызовом onComplete
                            Task {
                                try? await Task.sleep(nanoseconds: VoiceInputConstants.finalizationDelayMs * 1_000_000)

                                await MainActor.run {
                                    // Проверяем наличие ошибки
                                    if let errorMsg = voiceService.errorMessage, !errorMsg.isEmpty {
                                        errorAlertMessage = errorMsg
                                        showingErrorAlert = true
                                        // Не закрываем view при ошибке - показываем alert
                                        return
                                    }

                                    let finalText = voiceService.getFinalText()
                                    if !finalText.isEmpty {
                                        onComplete(finalText)
                                        // onComplete closure в ContentView уже закрывает этот view через showingVoiceInput = false
                                        // поэтому не нужно вызывать dismiss() здесь
                                    } else {
                                        // Если текст пустой, показываем сообщение
                                        errorAlertMessage = String(localized: "voice.emptyText")
                                        showingErrorAlert = true
                                    }
                                }
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(AppColors.destructive)
                                    .frame(width: AppSize.buttonXL, height: AppSize.buttonXL)
                                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)

                                Image(systemName: "stop.fill")
                                    .font(.system(size: AppIconSize.xl))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.bottom, AppSpacing.xl)
                    .background(Color(.systemBackground))
                }
            }
            .navigationTitle(String(localized: "voice.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        voiceService.stopRecording()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .alert(String(localized: "voice.error"), isPresented: $showingPermissionAlert) {
                Button(String(localized: "voice.ok")) {
                    dismiss()
                }
                // Добавляем кнопку "Открыть Настройки" если ошибка связана с разрешениями
                if permissionMessage.contains("Доступ") || permissionMessage.contains("разрешени") {
                    Button("Открыть Настройки") {
                        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                            if UIApplication.shared.canOpenURL(settingsUrl) {
                                UIApplication.shared.open(settingsUrl)
                            }
                        }
                        dismiss()
                    }
                }
            } message: {
                Text(permissionMessage.isEmpty ? String(localized: "voice.errorMessage") : permissionMessage)
            }
            .alert(String(localized: "voice.error"), isPresented: $showingErrorAlert) {
                Button(String(localized: "voice.ok")) {
                    // Закрываем view только после подтверждения ошибки
                    dismiss()
                }
            } message: {
                Text(errorAlertMessage.isEmpty ? String(localized: "voice.errorMessage") : errorAlertMessage)
            }
            .onChange(of: voiceService.errorMessage) { _, newError in
                // Обрабатываем ошибки из VoiceInputService
                // Проверяем, что это новая ошибка (не пустая) и мы еще не показывали alert
                if let error = newError, !error.isEmpty, !showingErrorAlert {
                    #if DEBUG
                    print("🔴 VoiceInputView: Error detected - \(error)")
                    #endif
                    errorAlertMessage = error
                    showingErrorAlert = true
                }
            }
            .onChange(of: voiceService.isRecording) { oldValue, newValue in
                // Если запись остановилась из-за ошибки, проверяем errorMessage
                if oldValue && !newValue {
                    // Запись только что остановилась
                    if let error = voiceService.errorMessage, !error.isEmpty {
                        #if DEBUG
                        print("🔴 VoiceInputView: Recording stopped with error - \(error)")
                        #endif
                        errorAlertMessage = error
                        showingErrorAlert = true
                    }
                }
            }
            .onAppear {
                // Автоматически запускаем запись при открытии
                Task {
                    // Небольшая задержка, чтобы убедиться, что view полностью появился
                    try? await Task.sleep(nanoseconds: VoiceInputConstants.autoStartDelayMs * 1_000_000)
                    
                    let authorized = await voiceService.requestAuthorization()
                    if authorized {
                        do {
                            try await voiceService.startRecording()
                        } catch {
                            permissionMessage = error.localizedDescription
                            showingPermissionAlert = true
                        }
                    } else {
                        showingPermissionAlert = true
                    }
                }
            }
            .onChange(of: voiceService.transcribedText) { _, newText in
                // Update recognized entities in real-time
                recognizedEntities = parser.parseEntitiesLive(from: newText)
            }
            .onDisappear {
                // Останавливаем запись только если она активна
                if voiceService.isRecording {
                    voiceService.stopRecording()
                }
            }
        }
    }
}

struct RecordingIndicatorView: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .opacity(isAnimating ? 0.3 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isAnimating)
            
            Text(String(localized: "voice.recording"))
                .font(.headline)
                .foregroundColor(.red)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

#Preview {
    @Previewable @State var isPresented = true

    VoiceInputView(
        voiceService: VoiceInputService(),
        onComplete: { _ in },
        parser: VoiceInputParser(
            categoriesViewModel: CategoriesViewModel(),
            accountsViewModel: AccountsViewModel(),
            transactionsViewModel: {
                let accountsVM = AccountsViewModel()
                return TransactionsViewModel(accountBalanceService: accountsVM)
            }()
        )
    )
}
