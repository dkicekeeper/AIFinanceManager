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
    
    @State private var showingPermissionAlert = false
    @State private var permissionMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                Spacer()
                
                // Индикатор записи
                if voiceService.isRecording {
                    RecordingIndicatorView()
                }
                
                // Live транскрипция
                ScrollView {
                    Text(voiceService.transcribedText.isEmpty ? String(localized: "voice.speak") : voiceService.transcribedText)
                        .font(.title3)
                        .foregroundColor(voiceService.transcribedText.isEmpty ? .secondary : .primary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                .frame(maxHeight: VoiceInputConstants.transcriptionMaxHeight)
                
                Spacer()
                
                // Кнопка записи/стоп
                Button(action: {
                    if voiceService.isRecording {
                        voiceService.stopRecording()
                        // Даем время на финализацию перед вызовом onComplete
                        Task {
                            try? await Task.sleep(nanoseconds: VoiceInputConstants.finalizationDelayMs * 1_000_000)
                            let finalText = voiceService.getFinalText()
                            if !finalText.isEmpty {
                                await MainActor.run {
                                    onComplete(finalText)
                                    // onComplete closure в ContentView уже закрывает этот view через showingVoiceInput = false
                                    // поэтому не нужно вызывать dismiss() здесь
                                }
                            } else {
                                // Если текст пустой, закрываем view
                                await MainActor.run {
                                    dismiss()
                                }
                            }
                        }
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(voiceService.isRecording ? Color.red : Color.blue)
                            .frame(width: 80, height: 80)
                            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                        
                        Image(systemName: voiceService.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                    }
                }
                .padding(.bottom, 40)
                
                // Кнопка отмены
                Button(String(localized: "quickAdd.cancel")) {
                    voiceService.stopRecording()
                    dismiss()
                }
                .foregroundColor(.secondary)
                .padding(.bottom, 20)
            }
            .padding()
            .navigationTitle(String(localized: "voice.title"))
            .navigationBarTitleDisplayMode(.inline)
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
    VoiceInputView(voiceService: VoiceInputService()) { _ in }
}
