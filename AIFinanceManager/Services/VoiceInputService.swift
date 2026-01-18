//
//  VoiceInputService.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation
import Speech
import AVFoundation
import AVFAudio
import Combine

enum VoiceInputError: LocalizedError {
    case speechRecognitionNotAvailable
    case speechRecognitionDenied
    case speechRecognitionRestricted
    case audioEngineError(String)
    case recognitionError(String)
    
    var errorDescription: String? {
        switch self {
        case .speechRecognitionNotAvailable:
            return "Распознавание речи недоступно на этом устройстве"
        case .speechRecognitionDenied:
            return "Доступ к распознаванию речи запрещен. Разрешите доступ в Настройках"
        case .speechRecognitionRestricted:
            return "Доступ к распознаванию речи ограничен"
        case .audioEngineError(let message):
            return "Ошибка аудио: \(message)"
        case .recognitionError(let message):
            return "Ошибка распознавания: \(message)"
        }
    }
}

@MainActor
class VoiceInputService: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var errorMessage: String?
    
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer: SFSpeechRecognizer?
    private var finalTranscription: String = ""
    private var isStopping: Bool = false // Флаг для предотвращения множественных вызовов stop
    
    override init() {
        // Инициализируем распознаватель для русского языка
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
        recognizer?.delegate = nil // Будет установлен после super.init()
        self.speechRecognizer = recognizer
        super.init()
        // Устанавливаем delegate после super.init()
        self.speechRecognizer?.delegate = self
    }
    
    // Проверка доступности распознавания речи
    var isSpeechRecognitionAvailable: Bool {
        guard let recognizer = speechRecognizer else { return false }
        return recognizer.isAvailable
    }
    
    // Запрос разрешений
    func requestAuthorization() async -> Bool {
        // Запрос разрешения на микрофон (iOS 17+)
        let micStatus: Bool
        if #available(iOS 17.0, *) {
            micStatus = await AVAudioApplication.requestRecordPermission()
        } else {
            micStatus = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        guard micStatus else {
            errorMessage = "Доступ к микрофону запрещен. Разрешите доступ в Настройках"
            return false
        }
        
        // Запрос разрешения на распознавание речи
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        switch speechStatus {
        case .authorized:
            return true
        case .denied:
            errorMessage = VoiceInputError.speechRecognitionDenied.errorDescription
            return false
        case .restricted:
            errorMessage = VoiceInputError.speechRecognitionRestricted.errorDescription
            return false
        case .notDetermined:
            errorMessage = "Разрешение на распознавание речи не получено"
            return false
        @unknown default:
            errorMessage = "Неизвестная ошибка разрешений"
            return false
        }
    }
    
    // Начать запись
    func startRecording() async throws {
        // Проверяем доступность
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw VoiceInputError.speechRecognitionNotAvailable
        }
        
        // Если уже записываем, не делаем ничего
        if isRecording {
            return
        }
        
        // Останавливаем предыдущую запись, если она есть
        await stopRecordingSync()
        
        // Сбрасываем состояние
        transcribedText = ""
        finalTranscription = ""
        errorMessage = nil
        isStopping = false
        
        // Настраиваем аудио сессию
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Используем .playAndRecord для лучшего качества
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw VoiceInputError.audioEngineError("Не удалось настроить аудио сессию: \(error.localizedDescription)")
        }
        
        // Создаем запрос на распознавание
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw VoiceInputError.recognitionError("Не удалось создать запрос на распознавание")
        }
        
        // Показываем partial results для UI, но используем только final для парсинга
        recognitionRequest.shouldReportPartialResults = true
        
        // Улучшаем распознавание: включаем контекстные подсказки
        if #available(iOS 13.0, *) {
            recognitionRequest.taskHint = .dictation
            // Включаем on-device recognition если доступно
            if recognizer.supportsOnDeviceRecognition {
                recognitionRequest.requiresOnDeviceRecognition = true
            }
        }
        
        // Настраиваем аудио engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw VoiceInputError.audioEngineError("Не удалось создать аудио engine")
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: VoiceInputConstants.audioBufferSize, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        // Запускаем аудио engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw VoiceInputError.audioEngineError("Не удалось запустить аудио engine: \(error.localizedDescription)")
        }
        
        // Запускаем распознавание
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                Task { @MainActor in
                    let transcription = result.bestTranscription.formattedString
                    self.transcribedText = transcription
                    
                    // Сохраняем финальную транскрипцию
                    if result.isFinal {
                        self.finalTranscription = transcription
                    }
                }
            }
            
            if let error = error {
                Task { @MainActor in
                    if !self.isRecording {
                        // Игнорируем ошибки после остановки
                        return
                    }
                    self.errorMessage = VoiceInputError.recognitionError(error.localizedDescription).errorDescription
                    self.stopRecording()
                }
            }
        }
        
        isRecording = true
    }
    
    // Остановить запись (асинхронная версия для UI)
    func stopRecording() {
        Task { @MainActor in
            await stopRecordingSync()
        }
    }
    
    // Синхронная остановка записи
    // @MainActor гарантирует thread-safety, так как все вызовы происходят на главном потоке
    private func stopRecordingSync() async {
        // Предотвращаем множественные вызовы
        guard !isStopping else { return }
        guard isRecording else { return }

        isStopping = true
        isRecording = false

        // Сохраняем ссылки на объекты перед очисткой
        let currentAudioEngine = audioEngine
        let currentRecognitionRequest = recognitionRequest
        let currentRecognitionTask = recognitionTask

        // Завершаем запрос на распознавание
        currentRecognitionRequest?.endAudio()

        // Даем время на финализацию результата
        try? await Task.sleep(nanoseconds: VoiceInputConstants.audioEngineStopDelayMs * 1_000_000)

        // Останавливаем аудио engine
        if let engine = currentAudioEngine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil

        recognitionRequest = nil

        // Отменяем задачу распознавания
        currentRecognitionTask?.cancel()
        recognitionTask = nil

        // Деактивируем аудио сессию
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Ошибка при деактивации аудио сессии: \(error)")
        }

        // Сбрасываем флаг остановки
        isStopping = false
    }
    
    // Получить финальный текст
    func getFinalText() -> String {
        // Используем финальную транскрипцию, если доступна, иначе текущую
        return finalTranscription.isEmpty ? transcribedText : finalTranscription
    }
}

// MARK: - SFSpeechRecognizerDelegate
extension VoiceInputService: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        Task { @MainActor in
            if !available && isRecording {
                errorMessage = "Распознавание речи стало недоступно"
                stopRecording()
            }
        }
    }
}
