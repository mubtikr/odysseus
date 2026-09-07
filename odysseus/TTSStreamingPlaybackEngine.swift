//
//  TTSStreamingPlaybackEngine.swift
//  odysseus
//
//  Shared AVAudioEngine + AVAudioPlayerNode playback plumbing used by the
//  streaming TTS clients (ElevenLabs, Cartesia, Microsoft Edge, OpenAI
//  Realtime, Deepgram). Each client owns its own engine/player instance
//  and lifecycle; these are the pure scheduling/draining/stopping
//  primitives that were previously duplicated per client.
//

import AVFoundation
import Foundation

@MainActor
enum TTSStreamingPlaybackEngine {
    static func makeStreamFormat(sampleRate: Double) -> AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )
    }

    @discardableResult
    static func scheduleSamples(
        _ samples: [Int16],
        on player: AVAudioPlayerNode,
        format: AVAudioFormat,
        startPlaybackIfNeeded: Bool = true
    ) -> AVAudioFramePosition {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let channel = buffer.floatChannelData?[0] else {
            return 0
        }
        let scale: Float = (1.0 / 32_768.0) * Float(AppBundleConfiguration.voicePlaybackVolume())
        for index in samples.indices {
            channel[index] = Float(samples[index]) * scale
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        // The player may have been detached between sentence enqueue
        // and this scheduling pass (e.g. user spoke again, which calls
        // `stopPlayback` → `stopPlaybackInternal` → engine teardown).
        // `AVAudioPlayerNode.engine` is a weak reference; once the
        // engine deallocates, `engine` returns nil. Calling `play()` on
        // an engineless node throws `_engine != nil` and crashes the
        // process — guard before scheduling and starting.
        guard let engine = player.engine else { return 0 }
        // If the engine isn't running, drop this buffer rather than
        // restart mid-stream — restarting AVAudioEngine while samples
        // are queued causes audible skipping/jumping. The streaming
        // session owner is responsible for keeping the engine running
        // for the full response; if it stopped, the response is over.
        guard engine.isRunning else { return 0 }
        player.scheduleBuffer(buffer, completionHandler: nil)
        if startPlaybackIfNeeded && !player.isPlaying {
            player.play()
        }
        return AVAudioFramePosition(buffer.frameLength)
    }

    static func waitForPlaybackToDrain(
        _ player: AVAudioPlayerNode,
        scheduledFrameCount: AVAudioFramePosition,
        sampleRate: Double
    ) async {
        guard scheduledFrameCount > 0 else {
            stopPlayerIfAttached(player)
            return
        }

        // AVAudioPlayerNode can keep reporting `isPlaying` after queued
        // buffers are exhausted. Poll rendered frames, but do not stop
        // merely because the rendered-frame value is temporarily nil or
        // unchanged; that clipped Cartesia/Deepgram playback when their
        // players were started before buffers were queued. The wall-clock
        // deadline remains as a conservative stuck-device guard.
        let expectedDuration = Double(scheduledFrameCount) / sampleRate
        let deadline = Date().addingTimeInterval(max(expectedDuration + 3.0, 3.0))

        while !Task.isCancelled {
            if let renderedFrame = renderedSampleTime(for: player),
               renderedFrame >= scheduledFrameCount {
                break
            }

            if Date() >= deadline {
                break
            }

            try? await Task.sleep(nanoseconds: 80_000_000)
        }

        stopPlayerIfAttached(player)
    }

    nonisolated static func stopPlayerIfAttached(_ player: AVAudioPlayerNode) {
        guard player.engine != nil else { return }
        player.stop()
    }

    private static func renderedSampleTime(for player: AVAudioPlayerNode) -> AVAudioFramePosition? {
        guard player.engine != nil,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else {
            return nil
        }
        return playerTime.sampleTime
    }
}
