// Ported from Mac Duo (github.com/ninobc/mac-duo): ScreenStream and ContentFilterBuilder.
// Copyright (c) 2026 Nino Bouchedid. MIT License; see THIRD-PARTY-NOTICES.md.

import AppKit
import CoreVideo
import Metal
import ScreenCaptureKit

/// A live picture of the built-in display as Metal textures, kept running only
/// while the lid is on its way down, so the fold can freeze the newest frame
/// the moment it starts. Frames are IOSurface-backed: wrapping them copies nothing.
///
/// Only ever started with Screen Recording already granted: any
/// ScreenCaptureKit call without it raises the system prompt, and this runs
/// unattended, often with the lid shut.
@MainActor
final class ScreenStream {
    private final class Receiver: NSObject, SCStreamOutput, SCStreamDelegate {
        private let cache: CVMetalTextureCache
        private let lock = NSLock()
        private var newest: CVMetalTexture?
        var onStop: (@Sendable () -> Void)?

        init?(device: MTLDevice) {
            var made: CVMetalTextureCache?
            guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &made) == kCVReturnSuccess,
                  let made else { return nil }
            cache = made
        }

        func latest() -> MTLTexture? {
            lock.lock(); defer { lock.unlock() }
            return newest.flatMap(CVMetalTextureGetTexture)
        }

        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
            guard type == .screen, CMSampleBufferIsValid(sampleBuffer),
                  let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            CVMetalTextureCacheFlush(cache, 0)
            var wrapped: CVMetalTexture?
            let result = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, cache, pixels, nil, .bgra8Unorm_srgb,
                CVPixelBufferGetWidth(pixels), CVPixelBufferGetHeight(pixels), 0, &wrapped
            )
            guard result == kCVReturnSuccess, let wrapped else { return }
            lock.lock()
            newest = wrapped
            lock.unlock()
        }

        func stream(_ stream: SCStream, didStopWithError error: Error) {
            onStop?()
        }
    }

    private let device: MTLDevice
    private var stream: SCStream?
    private var receiver: Receiver?
    /// Bumped on every start and stop, so a start that finishes after a stop
    /// closes its stream instead of keeping it.
    private var generation = 0
    private(set) var isRunning = false
    private var lastFailure: CFTimeInterval = -.infinity

    init(device: MTLDevice) {
        self.device = device
    }

    /// The newest frame, nil until one has arrived.
    var latestFrame: MTLTexture? { receiver?.latest() }

    func start(display id: CGDirectDisplayID) {
        // Asked every display frame while a picture is wanted; a start that
        // failed waits a moment rather than asking ScreenCaptureKit again at once.
        guard !isRunning, CACurrentMediaTime() - lastFailure > 2, CGPreflightScreenCaptureAccess() else { return }
        isRunning = true
        generation += 1
        let token = generation
        Task { await begin(display: id, generation: token) }
    }

    func stop() {
        guard isRunning || stream != nil else { return }
        isRunning = false
        generation += 1
        let closing = stream
        stream = nil
        receiver = nil
        if let closing { Task { try? await closing.stopCapture() } }
    }

    private func begin(display id: CGDirectDisplayID, generation token: Int) async {
        guard let receiver = Receiver(device: device), let filter = await Self.filter(display: id),
              isRunning, token == generation else {
            if token == generation {
                isRunning = false
                lastFailure = CACurrentMediaTime()
            }
            return
        }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        // Only the newest frame is ever used, once; no need for the display rate.
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 20)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = FoldRenderer.colourSpace
        configuration.showsCursor = false
        configuration.queueDepth = 4
        configuration.scalesToFit = false

        let fresh = SCStream(filter: filter, configuration: configuration, delegate: receiver)
        receiver.onStop = { [weak self] in
            Task { @MainActor in
                guard let self, token == self.generation else { return }
                self.stream = nil
                self.receiver = nil
                self.isRunning = false
            }
        }
        do {
            try fresh.addStreamOutput(receiver, type: .screen,
                                      sampleHandlerQueue: DispatchQueue(label: "dev.intuito.nosleep.frames", qos: .userInteractive))
            try await fresh.startCapture()
            guard isRunning, token == generation else {
                try? await fresh.stopCapture()
                return
            }
            self.receiver = receiver
            stream = fresh
        } catch {
            if token == generation {
                isRunning = false
                lastFailure = CACurrentMediaTime()
            }
        }
    }

    /// The built-in display without NoSleep's own windows, so the overlay
    /// never captures itself. ScreenCaptureKit only lists an app that has a
    /// window on screen; the overlay is up by the time this runs.
    private static func filter(display id: CGDirectDisplayID) async -> SCContentFilter? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == id }) else { return nil }
        let pid = ProcessInfo.processInfo.processIdentifier
        let own = content.applications.filter { $0.processID == pid }
        if !own.isEmpty {
            return SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        }
        // Nothing of ours listed means nothing to leave out: the picture would
        // carry the cat. No fold this time rather than a doubled one.
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == pid }
        return ownWindows.isEmpty ? nil : SCContentFilter(display: display, excludingWindows: ownWindows)
    }
}
