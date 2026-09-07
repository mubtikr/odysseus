//
//  DeepgramTTSClient.swift
//  odysseus
//

import AVFoundation
import Foundation

// MARK: - DeepgramTTSClient

/// Deepgram Aura TTS client. Posts to `https://api.deepgram.com/v1/speak`
/// with `encoding=linear16&sample_rate=22050&container=none` so the
/// returned bytes are raw Int16 LE PCM and feed straight into the same
/// `StreamingTTSSession` pipeline used by ElevenLabs/Cartesia.
///
/// Auth header `Authorization: Token <key>` matches the existing
/// Deepgram STT path — the same API key works for both. Verified
/// against https://developers.deepgram.com (2026-04-26).
@MainActor
final class DeepgramTTSClient {
    private var apiKey: String?
    /// `voiceID` carries the Deepgram model/voice identifier (e.g.
    /// `aura-2-thalia-en`). Property name kept as `voiceID` to match
    /// the protocol surface.
    private(set) var voiceID: String
    private let session: URLSession

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var streamingTask: Task<Void, Error>?
    private weak var activeStreamingSession: StreamingTTSSession?

    /// Deepgram's supported `sample_rate` values for `encoding=linear16`
    /// are 8000, 16000, 24000, 32000, 44100, 48000 (verified empirically:
    /// `Unsupported audio format: sample_rate must be 8000, 16000, 24000,
    /// 32000, 44100, or 48000 when encoding=linear16`). 22050 — used by
    /// the ElevenLabs path — is rejected. We pick 24000 for Deepgram.
    nonisolated static let streamSampleRate: Double = 24_000
    private static let chunkSampleCount = 2_048

    fileprivate static func makeStreamFormat() -> AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: streamSampleRate,
            channels: 1,
            interleaved: false
        )
    }

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
        guard let url = URL(string: "https://api.deepgram.com") else { return }
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
            throw Self.makeError(-100, "Deepgram API key is not configured")
        }
        guard !voiceID.isEmpty, let url = Self.streamRequestURL(model: voiceID) else {
            throw Self.makeError(-101, "Deepgram TTS voice/model is not configured")
        }

        stopPlaybackInternal()
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        guard let streamFormat = Self.makeStreamFormat() else {
            throw Self.makeError(-102, "Could not build PCM stream format")
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: streamFormat)
        do { try engine.start() } catch {
            throw Self.makeError(-103, "Audio engine failed to start: \(error.localizedDescription)")
        }
        self.audioEngine = engine
        self.playerNode = player

        let request = Self.makeRequest(url: url, apiKey: apiKey, text: text)
        let (asyncBytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (asyncBytes, response) = try await session.bytes(for: request)
        } catch is CancellationError {
            stopPlaybackInternal()
            throw CancellationError()
        } catch {
            stopPlaybackInternal()
            if Self.isExpectedCancellation(error) { throw CancellationError() }
            throw Self.makeError(-104, "Deepgram request failed: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            stopPlaybackInternal()
            throw Self.makeError(-105, "Deepgram returned an invalid response")
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
            throw Self.makeError(http.statusCode, "Deepgram API error \(http.statusCode): \(bodyText.prefix(500))")
        }

        let playerRef = player
        let engineRef = engine
        let streamFormatRef = streamFormat
        var didFireStartCallback = false
        var pendingByte: UInt8?
        var sampleAccumulator: [Int16] = []
        var scheduledFrameCount: AVAudioFramePosition = 0
        sampleAccumulator.reserveCapacity(Self.chunkSampleCount)

        let task = Task { [weak self] in
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
        guard let streamFormat = Self.makeStreamFormat() else {
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
            print("⚠️ AVAudioEngine failed to start Deepgram streaming session: \(error)")
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
            throw Self.makeError(-10, "Deepgram API key not configured")
        }
        guard !voiceID.isEmpty, let url = Self.streamRequestURL(model: voiceID) else {
            throw Self.makeError(-11, "Deepgram TTS voice/model not configured")
        }
        let request = Self.makeRequest(url: url, apiKey: apiKey, text: text)
        let urlSession = self.session
        return try await Self.decodePCMSamples(request: request, session: urlSession)
    }

    nonisolated private static func decodePCMSamples(
        request: URLRequest,
        session: URLSession
    ) async throws -> [Int16] {
        let (asyncBytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            // Drain a chunk of the body so the error surfaces with the
            // server's actual message instead of a bare "HTTP error".
            var body = Data()
            do {
                for try await byte in asyncBytes {
                    body.append(byte)
                    if body.count > 4096 { break }
                }
            } catch {}
            let bodyText = String(data: body, encoding: .utf8) ?? ""
            throw NSError(
                domain: "DeepgramTTS",
                code: (response as? HTTPURLResponse)?.statusCode ?? -12,
                userInfo: [NSLocalizedDescriptionKey: "Deepgram HTTP error \((response as? HTTPURLResponse)?.statusCode ?? 0): \(bodyText.prefix(500))"]
            )
        }

        // Deepgram returns a WAV file: 12-byte RIFF header, then chunks.
        // The "fmt " chunk is 24 bytes total (8 header + 16 body for
        // standard PCM). The "data" chunk header is 8 bytes ("data" +
        // 4-byte size). After that, samples begin. We scan for the
        // "data" tag rather than assuming a fixed 44-byte offset, because
        // some TTS engines insert extra metadata chunks (e.g., "LIST",
        // "fact") between the format and data chunks.
        var samples: [Int16] = []
        samples.reserveCapacity(8_192)

        var headerBuffer: [UInt8] = []
        headerBuffer.reserveCapacity(64)
        var pastHeader = false
        var pendingByte: UInt8?
        // Once we know the WAV "data" chunk's declared size, we stop
        // reading after that many bytes — anything beyond is padding
        // or trailing metadata that's not PCM.
        var dataBytesRemaining: Int = .max

        for try await byte in asyncBytes {
            try Task.checkCancellation()

            if !pastHeader {
                headerBuffer.append(byte)
                // Need at least 12 bytes to validate RIFF+WAVE.
                if headerBuffer.count == 12 {
                    let isRIFF = headerBuffer[0] == 0x52 && headerBuffer[1] == 0x49
                                && headerBuffer[2] == 0x46 && headerBuffer[3] == 0x46
                    let isWAVE = headerBuffer[8] == 0x57 && headerBuffer[9] == 0x41
                                && headerBuffer[10] == 0x56 && headerBuffer[11] == 0x45
                    if !(isRIFF && isWAVE) {
                        // Not a WAV — treat the whole buffer as raw PCM
                        // and continue. Defensive in case Deepgram ever
                        // returns headerless bytes.
                        for b in headerBuffer {
                            if let lo = pendingByte {
                                samples.append(Int16(bitPattern: UInt16(lo) | (UInt16(b) << 8)))
                                pendingByte = nil
                            } else {
                                pendingByte = b
                            }
                        }
                        pastHeader = true
                        headerBuffer.removeAll()
                    }
                }
                // Walk forward looking for the "data" tag once we have
                // enough bytes. The minimum offset is 12 (RIFF/WAVE).
                if headerBuffer.count >= 16 && !pastHeader {
                    var index = 12
                    while index + 8 <= headerBuffer.count {
                        let chunkID = String(bytes: headerBuffer[index..<index+4], encoding: .ascii) ?? ""
                        let chunkSize = Int(headerBuffer[index+4])
                            | (Int(headerBuffer[index+5]) << 8)
                            | (Int(headerBuffer[index+6]) << 16)
                            | (Int(headerBuffer[index+7]) << 24)
                        if chunkID == "data" {
                            // PCM samples start immediately after this
                            // chunk's 8-byte header.
                            let pcmStart = index + 8
                            if headerBuffer.count > pcmStart {
                                // Carry over any bytes already read past
                                // the header.
                                for b in headerBuffer[pcmStart...] {
                                    if let lo = pendingByte {
                                        samples.append(Int16(bitPattern: UInt16(lo) | (UInt16(b) << 8)))
                                        pendingByte = nil
                                    } else {
                                        pendingByte = b
                                    }
                                }
                                let consumedFromData = headerBuffer.count - pcmStart
                                dataBytesRemaining = max(0, chunkSize - consumedFromData)
                            } else {
                                dataBytesRemaining = chunkSize
                            }
                            pastHeader = true
                            headerBuffer.removeAll()
                            break
                        }
                        // Not the data chunk — skip past it. If we
                        // don't have all of the chunk yet, stop and
                        // wait for more bytes.
                        let nextIndex = index + 8 + chunkSize
                        // RIFF chunks have a pad byte when their size
                        // is odd. Account for that.
                        let padded = chunkSize % 2 == 1 ? nextIndex + 1 : nextIndex
                        if padded > headerBuffer.count { break }
                        index = padded
                    }
                }
                continue
            }

            if dataBytesRemaining == 0 { break }
            if let lo = pendingByte {
                samples.append(Int16(bitPattern: UInt16(lo) | (UInt16(byte) << 8)))
                pendingByte = nil
            } else {
                pendingByte = byte
            }
            if dataBytesRemaining != .max { dataBytesRemaining -= 1 }
        }
        return samples
    }

    // MARK: Request building

    nonisolated private static func streamRequestURL(model: String) -> URL? {
        var components = URLComponents(string: "https://api.deepgram.com/v1/speak")
        // Verified against https://developers.deepgram.com/docs/tts-media-output-settings
        // (2026-04-26): for `encoding=linear16` the REST endpoint requires
        // `container=wav` (or omits container, which defaults to wav).
        // `container=none` is NOT a valid value for linear16 here. The
        // body therefore starts with a 44-byte RIFF/WAVE header — the
        // PCM decoder strips it before yielding samples.
        components?.queryItems = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "\(Int(streamSampleRate))"),
            URLQueryItem(name: "container", value: "wav")
        ]
        return components?.url
    }

    nonisolated private static func makeRequest(url: URL, apiKey: String, text: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // Deepgram auth (verified against developers.deepgram.com,
        // 2026-04-26): `Authorization: Token <key>` for both STT and TTS.
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        let body: [String: Any] = ["text": text]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    nonisolated private static func makeError(_ code: Int, _ message: String) -> NSError {
        NSError(
            domain: "DeepgramTTS",
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

extension DeepgramTTSClient: OdysseusTTSClient {}
