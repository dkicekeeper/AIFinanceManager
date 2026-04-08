//
//  SiriWaveMetalView.swift
//  Tenra
//
//  MTKView renderer + UIViewRepresentable wrapper for the edge glow shader.
//

import SwiftUI
import MetalKit
import os

// MARK: - AudioLevelRef

/// Shared mutable amplitude state updated by the audio tap (main thread)
/// and read directly by the Metal renderer in draw(in:) — no SwiftUI cycle needed.
/// Uses os_unfair_lock for thread-safe access between main and render threads.
final class AudioLevelRef: @unchecked Sendable {
    private var _value: Float = 0.3
    // nonisolated(unsafe): lock accessed from both main thread and Metal render thread;
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

// MARK: - WaveUniforms (layout must match SiriWaveShader.metal exactly)

private struct WaveUniforms {
    var time:      Float
    var amplitude: Float
    var resW:      Float
    var resH:      Float
    var cornerR:   Float  // device screen corner radius in pixels
}

// MARK: - Pre-compiled Metal Pipeline Cache

/// Caches the compiled Metal pipeline so shader compilation happens once at app launch,
/// not on the first frame when the glow overlay appears.
/// Call `SiriWavePipelineCache.warmUp()` early (e.g. in AppCoordinator.init or .task)
/// to move compilation off the critical path.
final class SiriWavePipelineCache {
    static let shared = SiriWavePipelineCache()

    let device:       MTLDevice?
    let commandQueue: MTLCommandQueue?
    let pipeline:     MTLRenderPipelineState?
    let vertexBuffer: MTLBuffer?

    private init() {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            device = nil; commandQueue = nil; pipeline = nil; vertexBuffer = nil
            return
        }
        device = dev
        commandQueue = dev.makeCommandQueue()

        // Full-screen quad as a triangle strip: BL, BR, TL, TR in NDC space
        let verts: [SIMD2<Float>] = [
            .init(-1, -1), .init(1, -1),
            .init(-1,  1), .init(1,  1)
        ]
        vertexBuffer = dev.makeBuffer(
            bytes: verts,
            length: MemoryLayout<SIMD2<Float>>.stride * 4,
            options: .storageModeShared
        )

        // Compile shader — this is the expensive part (~50-200ms)
        guard
            let lib    = dev.makeDefaultLibrary(),
            let vertFn = lib.makeFunction(name: "waveVertex"),
            let fragFn = lib.makeFunction(name: "waveFragment")
        else { pipeline = nil; return }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction   = vertFn
        desc.fragmentFunction = fragFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Premultiplied alpha compositing (shader outputs color * alpha)
        let att = desc.colorAttachments[0]!
        att.isBlendingEnabled           = true
        att.sourceRGBBlendFactor        = .one
        att.destinationRGBBlendFactor   = .oneMinusSourceAlpha
        att.sourceAlphaBlendFactor      = .one
        att.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        pipeline = try? dev.makeRenderPipelineState(descriptor: desc)
    }

    /// Trigger lazy initialization. Call from background to avoid blocking main thread.
    static func warmUp() {
        _ = shared.pipeline
    }
}

// MARK: - Renderer

private final class SiriWaveRenderer: NSObject, MTKViewDelegate {

    // MARK: Metal state (shared from cache)

    private let device:         MTLDevice
    private let commandQueue:   MTLCommandQueue
    private let pipeline:       MTLRenderPipelineState
    private let vertexBuffer:   MTLBuffer
    private let uniformsBuffer: MTLBuffer

    // MARK: Mutable state

    private let startTime: CFTimeInterval = CACurrentMediaTime()
    /// Holds the live amplitude; renderer reads `amplitudeRef.value` every frame.
    var amplitudeRef: AudioLevelRef = AudioLevelRef()

    // MARK: Init

    init?(cache: SiriWavePipelineCache = .shared) {
        guard
            let dev  = cache.device,
            let q    = cache.commandQueue,
            let pipe = cache.pipeline,
            let vBuf = cache.vertexBuffer
        else { return nil }

        device       = dev
        commandQueue = q
        pipeline     = pipe
        vertexBuffer = vBuf

        // Only the uniforms buffer is per-renderer (mutable per frame)
        var empty = WaveUniforms(time: 0, amplitude: 0.3, resW: 1, resH: 1, cornerR: 47)
        guard let uBuf = dev.makeBuffer(
            bytes: &empty,
            length: MemoryLayout<WaveUniforms>.stride,
            options: .storageModeShared
        ) else { return nil }
        uniformsBuffer = uBuf

        super.init()
    }

    // MARK: MTKViewDelegate

    func draw(in view: MTKView) {
        guard
            let drawable   = view.currentDrawable,
            let descriptor = view.currentRenderPassDescriptor,
            let cmdBuf     = commandQueue.makeCommandBuffer(),
            let encoder    = cmdBuf.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        let sz = view.drawableSize
        let scale = Float(view.contentScaleFactor)
        var uni = WaveUniforms(
            time:      Float(CACurrentMediaTime() - startTime),
            amplitude: amplitudeRef.value,
            resW:      Float(sz.width),
            resH:      Float(sz.height),
            cornerR:   47.0 * scale
        )
        memcpy(uniformsBuffer.contents(), &uni, MemoryLayout<WaveUniforms>.stride)

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer,     offset: 0, index: 0)
        encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}

// MARK: - UIViewRepresentable

/// Wraps an MTKView running the edge glow shader.
/// Pass an `AudioLevelRef` whose `.value` (0–1) the renderer reads every frame.
struct SiriWaveMetalView: UIViewRepresentable {

    /// Live amplitude reference — updated by audio tap, read by renderer at 60 fps.
    var amplitudeRef: AudioLevelRef
    var isPaused:     Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.backgroundColor          = .clear
        view.isOpaque                 = false
        view.layer.isOpaque           = false
        view.clearColor               = MTLClearColorMake(0, 0, 0, 0) // transparent clear
        view.colorPixelFormat         = .bgra8Unorm
        view.framebufferOnly          = false
        view.preferredFramesPerSecond = 60

        let cache = SiriWavePipelineCache.shared
        guard let device = cache.device else { return view }
        view.device = device

        // Renderer reuses pre-compiled pipeline from cache — no shader compilation here
        let renderer = SiriWaveRenderer(cache: cache)
        renderer?.amplitudeRef = amplitudeRef
        context.coordinator.renderer = renderer
        view.delegate = renderer
        view.isPaused = isPaused

        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        if let renderer = context.coordinator.renderer {
            renderer.amplitudeRef = amplitudeRef
        }
        view.isPaused = isPaused
    }

    final class Coordinator {
        fileprivate var renderer: SiriWaveRenderer?
    }
}
