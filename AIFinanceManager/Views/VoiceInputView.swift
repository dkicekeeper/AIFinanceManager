//
//  VoiceInputView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

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
                    Text(voiceService.transcribedText.isEmpty ? "Говорите..." : voiceService.transcribedText)
                        .font(.title3)
                        .foregroundColor(voiceService.transcribedText.isEmpty ? .secondary : .primary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                .frame(maxHeight: 200)
                
                Spacer()
                
                // Кнопка записи/стоп
                Button(action: {
                    if voiceService.isRecording {
                        voiceService.stopRecording()
                        // Даем время на финализацию перед вызовом onComplete
                        Task {
                            try? await Task.sleep(nanoseconds: 350_000_000) // 350ms
                            let finalText = voiceService.getFinalText()
                            if !finalText.isEmpty {
                                onComplete(finalText)
                            }
                            await MainActor.run {
                                dismiss()
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
                Button("Отмена") {
                    voiceService.stopRecording()
                    dismiss()
                }
                .foregroundColor(.secondary)
                .padding(.bottom, 20)
            }
            .padding()
            .navigationTitle("Голосовой ввод")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Ошибка", isPresented: $showingPermissionAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text(permissionMessage.isEmpty ? "Не удалось начать запись" : permissionMessage)
            }
            .onAppear {
                // Автоматически запускаем запись при открытии
                Task {
                    // Небольшая задержка, чтобы убедиться, что view полностью появился
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    
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
            
            Text("Идет запись...")
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
