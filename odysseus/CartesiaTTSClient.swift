//
//  CartesiaTTSClient.swift
//  odysseus
//

import AVFoundation
import Foundation

/// TTS provider parallel to `ElevenLabsTTSClient`. Posts to Cartesia's
/// `/tts/bytes` endpoint requesting raw PCM_S16LE @ 22.05 kHz so the
/// returned bytes plug directly into the same `StreamingTTSSession`
/// pipeline. Public surface mirrors ElevenLabs (same method names,
/// same signatures) so `CompanionManager` can switch between them via
/// a single `currentTTSClient` reference without provider-specific
/// branching elsewhere.
@MainActor
final class CartesiaTTSClient {
    private var apiKey: String?
    private(set) var voiceID: String
    private let session: URLSession
    // Cartesia-Version pinned to the latest stable. Verified against
    // https://docs.cartesia.ai (2026-04-26). The voice-ID request
    // shape (`{"voice": {"mode": "id", ...}}`) is the supported format
    // on this version; voice embeddings will stop working June 2026.
    nonisolated private static let cartesiaVersionHeader = "2026-03-01"
    nonisolated private static let modelID = "sonic-turbo"

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var streamingTask: Task<Void, Error>?
    private weak var activeStreamingSession: StreamingTTSSession?

    nonisolated static let streamSampleRate: Double = 22_050
    private static let chunkSampleCount = 2_048

    init(apiKey: String?, voiceID: String) {
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.voiceID = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.httpMaximumConnectionsPerHost = 6
        self.session = URLSession(configuration: configuration)
    }

    func updateConfiguration(apiKey: String?, voiceID: String) {
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.voiceID = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func warmUpConnection() {
        guard let url = URL(string: "https://api.cartesia.ai") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        session.dataTask(with: request) { _, _, _ in }.resume()
    }

    var isPlaying: Bool {
        guard let playerNode, playerNode.engine != nil else { return false }
        return playerNode.isPlaying
    }

    func stopPlayback() {
        activeStreamingSession?.cancel()
        activeStreamingSession = nil
        stopPlaybackInternal()
    }

    private func stopPlaybackInternal() {
        streamingTask?.cancel()
        streamingTask = nil
        if let playerNode {
            TTSStreamingPlaybackEngine.stopPlayerIfAttached(playerNode)
        }
        playerNode = nil
        audioEngine?.stop()
        audioEngine = nil
    }

    // MARK: One-shot streaming

    func speakText(
        _ text: String,
        waitUntilFinished: Bool = true,
        onPlaybackStarted: (() -> Void)? = nil
    ) async throws {
        guard let apiKey, !apiKey.isEmpty else {
            throw Self.makeError(-100, "Cartesia API key is not configured")
        }
        guard !voiceID.isEmpty,
              let url = URL(string: "https://api.cartesia.ai/tts/bytes") else {
            throw Self.makeError(-101, "Cartesia voice ID is not configured")
        }

        stopPlaybackInternal()
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        guard let streamFormat = TTSStreamingPlaybackEngine.makeStreamFormat(sampleRate: Self.streamSampleRate) else {
            throw Self.makeError(-102, "Could not build PCM stream format")
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: streamFormat)
        do { try engine.start() } catch {
            throw Self.makeError(-103, "Audio engine failed to start: \(error.localizedDescription)")
        }
        self.audioEngine = engine
        self.playerNode = player

        let request = Self.makeRequest(url: url, apiKey: apiKey, voiceID: voiceID, text: text)
        let (asyncBytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (asyncBytes, response) = try await session.bytes(for: request)
        } catch is CancellationError {
            stopPlaybackInternal()
            throw CancellationError()
        } catch {
            stopPlaybackInternal()
            if Self.isExpectedCancellation(error) { throw CancellationError() }
            throw Self.makeError(-104, "Cartesia request failed: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            stopPlaybackInternal()
            throw Self.makeError(-105, "Cartesia returned an invalid response")
        }
        guard (200...299).contains(http.statusCode) else {
            var body = Data()
            do {
                for try await byte in asyncBytes {
                    body.append(byte)
                    if body.count > 4096 { break }
                }
            } catch {}
            stopPlaybackInternal()
            let bodyText = String(data: body, encoding: .utf8) ?? "Unknown error"
            throw Self.makeError(http.statusCode, "Cartesia API error \(http.statusCode): \(bodyText.prefix(500))")
        }

        let playerRef = player
        let engineRef = engine
        let streamFormatRef = streamFormat
        var didFireStartCallback = false
        var pendingByte: UInt8?
        var sampleAccumulator: [Int16] = []
        var scheduledFrameCount: AVAudioFramePosition = 0
        sampleAccumulator.reserveCapacity(Self.chunkSampleCount)

        let task = Task<Void, Error> { [weak self] in
            do {
                for try await byte in asyncBytes {
                    try Task.checkCancellation()
                    if let lo = pendingByte {
                        let hi = byte
                        sampleAccumulator.append(Int16(bitPattern: UInt16(lo) | (UInt16(hi) << 8)))
                        pendingByte = nil
                    } else {
                        pendingByte = byte
                    }
                    if sampleAccumulator.count >= Self.chunkSampleCount {
                        let chunk = sampleAccumulator
                        sampleAccumulator.removeAll(keepingCapacity: true)
                        let frames = await MainActor.run { () -> AVAudioFramePosition in
                            let f = TTSStreamingPlaybackEngine.scheduleSamples(chunk, on: playerRef, format: streamFormatRef)
                            if f > 0 && !didFireStartCallback {
                                didFireStartCallback = true
                                onPlaybackStarted?()
                            }
                            return f
                        }
                        scheduledFrameCount += frames
                    }
                }
                if !sampleAccumulator.isEmpty {
                    let tail = sampleAccumulator
                    let frames = await MainActor.run { () -> AVAudioFramePosition in
                        let f = TTSStreamingPlaybackEngine.scheduleSamples(tail, on: playerRef, format: streamFormatRef)
                        if f > 0 && !didFireStartCallback {
                            didFireStartCallback = true
                            onPlaybackStarted?()
                        }
                        return f
                    }
                    scheduledFrameCount += frames
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Self.isExpectedCancellation(error) { throw CancellationError() }
                throw error
            }
            await TTSStreamingPlaybackEngine.waitForPlaybackToDrain(
                playerRef,
                scheduledFrameCount: scheduledFrameCount,
                sampleRate: Self.streamSampleRate
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                if self.audioEngine === engineRef {
                    self.audioEngine?.stop()
                    self.audioEngine = nil
                    self.playerNode = nil
                }
            }
        }
        self.streamingTask = task
        if waitUntilFinished {
            do { try await task.value }
            catch is CancellationError { stopPlaybackInternal(); throw CancellationError() }
            catch { stopPlaybackInternal(); throw error }
        }
    }

    // MARK: Sentence-pipelined streaming

    func beginStreamingResponse(onPlaybackStarted: @escaping @MainActor () -> Void) -> StreamingTTSSession {
        stopPlaybackInternal()
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        guard let streamFormat = TTSStreamingPlaybackEngine.makeStreamFormat(sampleRate: Self.streamSampleRate) else {
            return StreamingTTSSession(
                fetchSamples: { [weak self] text in
                    guard let self else { throw CancellationError() }
                    return try await self.fetchSentenceSamples(text)
                },
                playerNode: nil,
                format: nil,
                sampleRate: Self.streamSampleRate,
                onPlaybackStarted: onPlaybackStarted
            )
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: streamFormat)
        do { try engine.start() } catch {
            print("⚠️ AVAudioEngine failed to start Cartesia streaming session: \(error)")
            return StreamingTTSSession(
                fetchSamples: { [weak self] text in
                    guard let self else { throw CancellationError() }
                    return try await self.fetchSentenceSamples(text)
                },
                playerNode: nil,
                format: nil,
                sampleRate: Self.streamSampleRate,
                onPlaybackStarted: onPlaybackStarted
            )
        }
        self.audioEngine = engine
        self.playerNode = player
        let session = StreamingTTSSession(
            fetchSamples: { [weak self] text in
                guard let self else { throw CancellationError() }
                return try await self.fetchSentenceSamples(text)
            },
            playerNode: player,
            format: streamFormat,
            sampleRate: Self.streamSampleRate,
            onPlaybackStarted: onPlaybackStarted
        )
        self.activeStreamingSession = session
        return session
    }

    func fetchSentenceSamples(_ text: String) async throws -> [Int16] {
        guard let apiKey, !apiKey.isEmpty else {
            throw Self.makeError(-10, "Cartesia API key not configured")
        }
        guard !voiceID.isEmpty, let url = URL(string: "https://api.cartesia.ai/tts/bytes") else {
            throw Self.makeError(-11, "Cartesia voice ID not configured")
        }
        let request = Self.makeRequest(url: url, apiKey: apiKey, voiceID: voiceID, text: text)
        let urlSession = self.session
        return try await Self.decodePCMSamples(request: request, session: urlSession)
    }

    nonisolated private static func decodePCMSamples(
        request: URLRequest,
        session: URLSession
    ) async throws -> [Int16] {
        let (asyncBytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(
                domain: "CartesiaTTS",
                code: (response as? HTTPURLResponse)?.statusCode ?? -12,
                userInfo: [NSLocalizedDescriptionKey: "Cartesia HTTP error"]
            )
        }
        var samples: [Int16] = []
        samples.reserveCapacity(8_192)
        var pendingByte: UInt8?
        for try await byte in asyncBytes {
            try Task.checkCancellation()
            if let lo = pendingByte {
                samples.append(Int16(bitPattern: UInt16(lo) | (UInt16(byte) << 8)))
                pendingByte = nil
            } else {
                pendingByte = byte
            }
        }
        return samples
    }

    // MARK: Request building

    nonisolated private static func makeRequest(url: URL, apiKey: String, voiceID: String, text: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // Verified against https://docs.cartesia.ai (2026-04-26):
        // current auth scheme is `Authorization: Bearer <key>` (the
        // legacy `X-API-Key` header is rejected on `2026-03-01`).
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(cartesiaVersionHeader, forHTTPHeaderField: "Cartesia-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "model_id": modelID,
            "transcript": text,
            "voice": ["mode": "id", "id": voiceID],
            "output_format": [
                "container": "raw",
                "encoding": "pcm_s16le",
                "sample_rate": Int(streamSampleRate)
            ],
            "language": "en"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    nonisolated private static func makeError(_ code: Int, _ message: String) -> NSError {
        NSError(
            domain: "CartesiaTTS",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    nonisolated private static func isExpectedCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
        if ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError { return true }
        let desc = String(describing: error).lowercased()
        return desc == "cancellationerror()" || desc.contains("cancelled") || desc.contains("canceled")
    }
}
