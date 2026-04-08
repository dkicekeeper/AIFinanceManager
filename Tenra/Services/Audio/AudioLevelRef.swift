//
//  AudioLevelRef.swift
//  Tenra
//
//  Thread-safe mutable amplitude state shared between audio tap and UI.
//

import os

/// Shared mutable amplitude state updated by the audio tap (main thread)
/// and read by the UI renderer every frame — bypasses SwiftUI update cycle.
/// Uses os_unfair_lock for thread-safe access between threads.
final class AudioLevelRef: @unchecked Sendable {
    private var _value: Float = 0.3
    // nonisolated(unsafe): lock accessed from multiple threads;
    // guarded by os_unfair_lock itself — no Swift concurrency protection needed.
    nonisolated(unsafe) private var lock = os_unfair_lock()

    /// Normalized mic amplitude 0–1. Thread-safe read/write.
    var value: Float {
        get {
            os_unfair_lock_lock(&lock)
            let v = _value
            os_unfair_lock_unlock(&lock)
            return v
        }
        set {
            os_unfair_lock_lock(&lock)
            _value = newValue
            os_unfair_lock_unlock(&lock)
        }
    }
}
