//
//  OdysseusSystemAudioCaptureController.swift
//  odysseus
//
//  ScreenCaptureKit-powered computer-audio capture. Meeting Notes uses this
//  both to save a system-audio recording and, when possible, to feed the same
//  PCM buffers into Odysseus's transcription providers.
//

import AVFoundation
import Foundation
import ScreenCaptureKit

final class OdysseusSystemAudioCaptureController: NSObject, SCStreamOutput, SCStreamDelegate {
    struct CaptureState: Equatable {
        var isRunning = false
        var outputURL: URL?
        var errorMessage: String?
        var receivedAudioBuffers = 0
    }

    private let queue = DispatchQueue(label: "com.odysseus.system-audio.capture", qos: .userInitiated)
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var hasStartedWriting = false
    private var state = CaptureState()
    private var stateChanged: ((CaptureState) -> Void)?
    private var audioBufferHandler: ((AVAudioPCMBuffer) -> Void)?

    func start(
        outputURL: URL,
        onStateChanged: @escaping (CaptureState) -> Void,
        onAudioBuffer: ((AVAudioPCMBuffer) -> Void)? = nil
    ) async throws {
        self.stateChanged = onStateChanged
        self.audioBufferHandler = onAudioBuffer
        // H6: all writer/input/state mutations are serialized on `queue` (the
        // same serial queue the audio callback runs on) so the callback cannot
        // observe a half-constructed writer/input pair.
        queue.sync {
            state = CaptureState(isRunning: false, outputURL: outputURL, errorMessage: nil, receivedAudioBuffers: 0)
        }
        notifyStateChanged()

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "OdysseusSystemAudioCapture", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "No display is available for system audio capture."
            ])
        }

        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
        input.expectsMediaDataInRealTime = true
        if writer.canAdd(input) {
            writer.add(input)
        }
        // H6: assign writer/input behind `queue` so the audio callback (also on
        // `queue`) never races the assignment in `start()`.
        queue.sync {
            assetWriter = writer
            audioInput = input
            hasStartedWriting = false
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 2)
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        // H6: assign stream behind `queue` to serialize with stop()/didStop.
        queue.sync {
            self.stream = stream
        }
        try await stream.startCapture()
        queue.sync { state.isRunning = true }
        notifyStateChanged()
    }

    func stop() async {
        let activeStream = queue.sync { () -> SCStream? in
            let active = stream
            stream = nil
            return active
        }
        if let activeStream {
            try? await activeStream.stopCapture()
        }

        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                self.audioInput?.markAsFinished()
                if let writer = self.assetWriter, self.hasStartedWriting {
                    writer.finishWriting {
                        continuation.resume()
                    }
                } else {
                    self.assetWriter?.cancelWriting()
                    continuation.resume()
                }
                self.assetWriter = nil
                self.audioInput = nil
                self.hasStartedWriting = false
            }
        }

        queue.sync { state.isRunning = false }
        notifyStateChanged()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // H6: mutate state on `queue` to serialize with the audio callback and
        // start()/stop().
        queue.sync {
            state.isRunning = false
            state.errorMessage = error.localizedDescription
        }
        notifyStateChanged()
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio,
              CMSampleBufferDataIsReady(sampleBuffer) else { return }

        if let pcmBuffer = Self.makePCMBuffer(from: sampleBuffer) {
            audioBufferHandler?(pcmBuffer)
        }

        if let writer = assetWriter,
           let input = audioInput {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if !hasStartedWriting {
                writer.startWriting()
                writer.startSession(atSourceTime: timestamp)
                hasStartedWriting = true
            }
            if input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            }
        }

        state.receivedAudioBuffers += 1
        if state.receivedAudioBuffers == 1 || state.receivedAudioBuffers % 30 == 0 {
            notifyStateChanged()
        }
    }

    private func notifyStateChanged() {
        let snapshot = state
        DispatchQueue.main.async { [stateChanged] in
            stateChanged?(snapshot)
        }
    }

    private static func makePCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescriptionPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }

        var streamDescription = streamDescriptionPointer.pointee
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else { return nil }

        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard sampleCount > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(sampleCount)
              ) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(sampleCount)

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(sampleCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else { return nil }
        return buffer
    }
}
