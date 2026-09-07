//
//  MicrosoftEdgeTTSClient.swift
//  odysseus
//

import AVFoundation
import CryptoKit
import Foundation

/// Uses the free Microsoft Edge Read Aloud online voices via the same
/// WebSocket service used by Edge's built-in reader. No Azure key is
/// required; users choose one of the Edge voice identifiers such as
/// `en-US-BrianMultilingualNeural` or `en-GB-RyanNeural`.
@MainActor
final class MicrosoftEdgeTTSClient: OdysseusTTSClient {
    nonisolated static let streamSampleRate: Double = 24_000
    private nonisolated static let defaultVoiceID = "en-US-BrianMultilingualNeural"
    private nonisolated static let trustedClientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    private nonisolated static let chromiumFullVersion = "143.0.3650.75"
    /// Microsoft rotated the Read Aloud handshake in Oct 2026 to Sec-MS-GEC v2
    /// (`2-<version>` + salted "<16hex>-<64hex>" token); v1 handshakes are
    /// rejected with 404/403. See EdgeTTSGECv2Token.swift for the port.
    private nonisolated static let secMSGECVersion = "2-\(chromiumFullVersion)"
    private nonisolated static let outputFormat = "audio-24khz-48kbitrate-mono-mp3"
    private static let chunkSampleCount = 2_048

    private(set) var voiceID: String
    private let session: URLSession
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var streamingTask: Task<Void, Error>?
    private weak var activeStreamingSession: StreamingTTSSession?

    init(voiceID: String) {
        self.voiceID = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.voiceID.isEmpty { self.voiceID = Self.defaultVoiceID }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.httpMaximumConnectionsPerHost = 6
        self.session = URLSession(configuration: configuration)
    }

    func updateConfiguration(apiKey: String?, voiceID: String) {
        let trimmed = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.voiceID = trimmed.isEmpty ? Self.defaultVoiceID : trimmed
    }

    func warmUpConnection() {
        guard let url = URL(string: "https://speech.platform.bing.com/consumer/speech/synthesize/readaloud/voices/list?trustedclienttoken=\(Self.trustedClientToken)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        Self.applyEdgeHeaders(to: &request)
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

    func speakText(
        _ text: String,
        waitUntilFinished: Bool = true,
        onPlaybackStarted: (() -> Void)? = nil
    ) async throws {
        stopPlaybackInternal()
        let samples = try await fetchSentenceSamples(text)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        guard let streamFormat = Self.makeStreamFormat() else {
            throw Self.makeError(-102, "Could not build Microsoft Edge PCM stream format")
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: streamFormat)
        do { try engine.start() } catch {
            throw Self.makeError(-103, "Audio engine failed to start: \(error.localizedDescription)")
        }
        self.audioEngine = engine
        self.playerNode = player

        let playerRef = player
        let engineRef = engine
        let scheduledFrames = TTSStreamingPlaybackEngine.scheduleSamples(samples, on: playerRef, format: streamFormat)
        if scheduledFrames > 0 { onPlaybackStarted?() }

        let task = Task<Void, Error> { [weak self] in
            await TTSStreamingPlaybackEngine.waitForPlaybackToDrain(
                playerRef,
                scheduledFrameCount: scheduledFrames,
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
            print("⚠️ AVAudioEngine failed to start Microsoft Edge streaming session: \(error)")
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
        let streaming = StreamingTTSSession(
            fetchSamples: { [weak self] text in
                guard let self else { throw CancellationError() }
                return try await self.fetchSentenceSamples(text)
            },
            playerNode: player,
            format: streamFormat,
            sampleRate: Self.streamSampleRate,
            onPlaybackStarted: onPlaybackStarted
        )
        self.activeStreamingSession = streaming
        return streaming
    }

    func fetchSentenceSamples(_ text: String) async throws -> [Int16] {
        let selectedVoice = voiceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.defaultVoiceID : voiceID
        let mp3Data = try await Self.fetchMP3Data(
            text: text,
            voiceID: selectedVoice,
            session: session
        )
        return try Self.decodeMP3DataToSamples(mp3Data)
    }

    private static func makeStreamFormat() -> AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: streamSampleRate,
            channels: 1,
            interleaved: false
        )
    }

    nonisolated private static func fetchMP3Data(
        text: String,
        voiceID: String,
        session: URLSession
    ) async throws -> Data {
        guard let url = websocketURL() else {
            throw makeError(-10, "Could not build Microsoft Edge TTS WebSocket URL")
        }
        var request = URLRequest(url: url)
        applyEdgeHeaders(to: &request)
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold", forHTTPHeaderField: "Origin")
        request.setValue("muid=\(UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased());", forHTTPHeaderField: "Cookie")

        let socket = session.webSocketTask(with: request)
        socket.resume()
        defer {
            socket.cancel(with: .goingAway, reason: nil)
        }

        try await socket.send(.string(speechConfigMessage()))
        try await socket.send(.string(ssmlMessage(text: text, voiceID: voiceID)))

        var audioData = Data()
        while true {
            try Task.checkCancellation()
            let message = try await socket.receive()
            switch message {
            case .data(let data):
                let parsed = parseBinaryMessage(data)
                if parsed.path == "audio", !parsed.payload.isEmpty {
                    audioData.append(parsed.payload)
                }
            case .string(let string):
                let parsed = parseTextMessage(string)
                if parsed.path == "turn.end" {
                    if audioData.isEmpty {
                        throw makeError(-11, "Microsoft Edge TTS returned no audio")
                    }
                    return audioData
                }
            @unknown default:
                continue
            }
        }
    }

    nonisolated private static func websocketURL() -> URL? {
        let connectionID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let secMSGEC = generateSecMSGEC()
        return URL(string: "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=\(trustedClientToken)&ConnectionId=\(connectionID)&Sec-MS-GEC=\(secMSGEC)&Sec-MS-GEC-Version=\(secMSGECVersion)")
    }

    nonisolated private static func speechConfigMessage() -> String {
        """
        X-Timestamp:\(edgeTimestamp())\r
        Content-Type:application/json; charset=utf-8\r
        Path:speech.config\r
        \r
        {"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},"outputFormat":"\(outputFormat)"}}}}\r
        """
    }

    nonisolated private static func ssmlMessage(text: String, voiceID: String) -> String {
        let requestID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let escaped = xmlEscaped(cleanedText(text))
        let ssml = """
        <speak version='1.0' xml:lang='en-US'><voice name='\(voiceID)'><prosody pitch='+0Hz' rate='+0%' volume='+0%'>\(escaped)</prosody></voice></speak>
        """
        return """
        X-RequestId:\(requestID)\r
        Content-Type:application/ssml+xml\r
        X-Timestamp:\(edgeTimestamp())Z\r
        Path:ssml\r
        \r
        \(ssml)
        """
    }

    nonisolated private static func parseTextMessage(_ string: String) -> (path: String?, payload: Data) {
        guard let separator = string.range(of: "\r\n\r\n") else {
            return (nil, Data(string.utf8))
        }
        let headerText = String(string[..<separator.lowerBound])
        let payloadText = String(string[separator.upperBound...])
        return (pathFromHeaders(headerText), Data(payloadText.utf8))
    }

    nonisolated private static func parseBinaryMessage(_ data: Data) -> (path: String?, payload: Data) {
        guard data.count >= 2 else { return (nil, Data()) }
        let headerLength = (Int(data[data.startIndex]) << 8) | Int(data[data.index(after: data.startIndex)])
        let headerStart = data.index(data.startIndex, offsetBy: 2)
        guard headerLength > 0,
              let headerEnd = data.index(headerStart, offsetBy: headerLength, limitedBy: data.endIndex) else {
            return (nil, Data())
        }
        let headerData = data[headerStart..<headerEnd]
        let payload = data.suffix(from: headerEnd)
        let headerText = String(data: headerData, encoding: .utf8) ?? ""
        return (pathFromHeaders(headerText), payload)
    }

    nonisolated static func testParseMicrosoftEdgeBinaryMessage(_ data: Data) -> (path: String?, payload: Data) {
        parseBinaryMessage(data)
    }

    nonisolated private static func pathFromHeaders(_ headerText: String) -> String? {
        for line in headerText.components(separatedBy: "\r\n") {
            if let range = line.range(of: "Path:", options: [.caseInsensitive]) {
                return line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let pieces = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2 else { continue }
            if pieces[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "path" {
                return pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    nonisolated private static func decodeMP3DataToSamples(_ data: Data) throws -> [Int16] {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("odysseus-edge-tts-\(UUID().uuidString)")
            .appendingPathExtension("mp3")
        try data.write(to: tempURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let file = try AVAudioFile(forReading: tempURL)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw makeError(-12, "Could not allocate Microsoft Edge audio buffer")
        }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else {
            throw makeError(-13, "Could not decode Microsoft Edge MP3 audio")
        }
        let channelCount = max(1, Int(format.channelCount))
        let frames = Int(buffer.frameLength)
        var samples: [Int16] = []
        samples.reserveCapacity(frames)
        for frame in 0..<frames {
            var mixed: Float = 0
            for channel in 0..<channelCount {
                mixed += channels[channel][frame]
            }
            let clamped = max(-1, min(1, mixed / Float(channelCount)))
            samples.append(Int16(clamped * Float(Int16.max)))
        }
        return samples
    }

    nonisolated private static func cleanedText(_ text: String) -> String {
        String(text.map { character in
            guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
                return character
            }
            switch scalar.value {
            case 0...8, 11...12, 14...31:
                return " "
            default:
                return character
            }
        })
    }

    nonisolated private static func xmlEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    nonisolated private static func edgeTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT+0000 (Coordinated Universal Time)'"
        return formatter.string(from: Date())
    }

    nonisolated private static func generateSecMSGEC() -> String {
        EdgeTTSGECv2Token.generate()
    }

    nonisolated private static func applyEdgeHeaders(to request: inout URLRequest) {
        let major = chromiumFullVersion.split(separator: ".", maxSplits: 1).first ?? "143"
        request.setValue(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(major).0.0.0 Safari/537.36 Edg/\(major).0.0.0",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("gzip, deflate, br, zstd", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
    }

    nonisolated private static func makeError(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "MicrosoftEdgeTTS", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
