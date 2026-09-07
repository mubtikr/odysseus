// EdgeTTSGECv2Token.swift — byte-parity port of edge-tts master drm.py (Oct 2026 v2 Sec-MS-GEC).
// Constants machine-generated from drm.py; do not hand-edit.

import Foundation

nonisolated enum EdgeTTSGECv2Token {
    static let trustedClientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    static let winEpoch: Double = 11_644_473_600

    private static let roundConstants: [UInt32] = [
        0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5,
        0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
        0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3,
        0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
        0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC,
        0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
        0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7,
        0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
        0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13,
        0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
        0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3,
        0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
        0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5,
        0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
        0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208,
        0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
    ]
    private static let block14Adjustment: UInt32 = 0xC9DC06A7
    private static let sigma0Adjustment: UInt32 = 0x059C0B80
    private static let sigma1Adjustment: UInt32 = 0x000B92C0

    private static let sha256Initial: [UInt32] = [
        0x6A09E667, 0xBB67AE85,
        0x3C6EF372, 0xA54FF53A,
        0x510E527F, 0x9B05688C,
        0x1F83D9AB, 0x5BE0CD19,
    ]
    private static let sha256SaltState: [UInt32] = [
        0xFD9FBEA2, 0x91243CE7,
        0xBE499094, 0xCD2E1E0A,
        0x6C006F49, 0x04BD35AB,
        0xFEB0A7E4, 0x03EFFBD2,
    ]
    private static let sha256SaltSchedule: [UInt32] = [
        0xEB24BF9E, 0x1558691F,
        0xA0C09EE2, 0x0CFA32BA,
        0xA622EE8C, 0xD1DD9491,
        0xC0DD25A0, 0xF9E70AB6,
        0xF0C31573, 0x7058CE4E,
        0x7188E606, 0x00E5AB33,
        0xD258B060, 0x72766564,
    ]
    private static let cs64Coefficients: [(UInt64, UInt64)] = [
        (0xE82E91B1, 0xB32700D0),
        (0x44DE24C6, 0x88DFF51D),
        (0x3BEB65BC, 0x29514038),
        (0xC89C5933, 0xB328CBDF),
        (0x8D1EC211, 0xD405B4D5),
        (0x314EF5D5, 0x26E55F3C),
        (0xE92491B1, 0x607801C6),
        (0xF0A5B9D5, 0x82B2C1FB),
        (0x06064CF3, 0xFA51A3DA),
        (0xDA79FA60, 0x207CC464),
        (0xBED20560, 0x3C3C74F3),
        (0x89F9C9F8, 0xD2D14B61),
        (0x35FA38C6, 0xBB04A2C1),
        (0xCB49E3C6, 0xC5626167),
    ]

    private static func combinedSigma0(_ v: UInt32) -> UInt32 {
        (v >> 7) ^ (v << 25) ^ (v >> 18) ^ (v << 14) ^ (v >> 3)
    }
    private static func combinedSigma1(_ v: UInt32) -> UInt32 {
        (v >> 17) ^ (v << 15) ^ (v >> 19) ^ (v << 13) ^ (v >> 10)
    }
    private static func rol16x(_ v: UInt64) -> UInt64 {
        let low = v & 0xFFFFFFFF
        return ((low << 16) | (low >> 16)) & 0xFFFFFFFF
    }

    private static func expandSchedule(_ words: inout [UInt32], from first: Int = 16) {
        for index in first..<64 {
            let x = words[index - 2]
            let y = words[index - 15]
            words.append((combinedSigma1(x) &+ words[index - 7] &+ combinedSigma0(y) &+ words[index - 16]) & 0xFFFFFFFF)
        }
    }

    private static func u32BE(_ bytes: [UInt8]) -> UInt32 {
        var value: UInt32 = 0
        for byte in bytes.prefix(4) { value = (value << 8) | UInt32(byte) }
        return value
    }

    private static func dbl(_ v: UInt32) -> UInt64 {
        (UInt64(v) << 32) | UInt64(v)
    }

    private static func sha256Rounds(state: [UInt32], words: [UInt32], firstRound: Int = 0) -> [UInt32] {
        var a = state[0], b = state[1], c = state[2], d = state[3]
        var e = state[4], f = state[5], g = state[6], h = state[7]
        let mask: UInt32 = 0xFFFFFFFF

        func k(_ index: Int) -> UInt32 {
            (firstRound == 14 && index == 14) ? block14Adjustment : roundConstants[index]
        }

        let aligned = Swift.min(64, ((firstRound + 7) / 8) * 8)
        for index in firstRound..<aligned {
            let rotE: UInt64 = UInt64(e) * 0x100000001
            let rotA: UInt64 = UInt64(a) * 0x100000001
            let t1: UInt64 = UInt64(h)
                + ((rotE >> 6) ^ (rotE >> 11) ^ (rotE >> 25))
                + (UInt64(g) ^ (UInt64(e) & (UInt64(f) ^ UInt64(g))))
                + UInt64(k(index)) + UInt64(words[index])
            let t2: UInt64 = ((rotA >> 2) ^ (rotA >> 13) ^ (rotA >> 22))
                + ((UInt64(a) & UInt64(b)) | (UInt64(c) & (UInt64(a) | UInt64(b))))
            let aNew = (t1 &+ t2) & 0xFFFFFFFF
            let eNew = (UInt64(d) &+ t1) & 0xFFFFFFFF
            (a, b, c, d, e, f, g, h) = (UInt32(truncatingIfNeeded: aNew), a, b, c,
                                        UInt32(truncatingIfNeeded: eNew), e, f, g)
        }

        for index in stride(from: aligned, to: 64, by: 8) {
        do {
            let s1 = (dbl(e) >> 6) ^ (dbl(e) >> 11) ^ (dbl(e) >> 25)
            let chv = UInt64(g) ^ (UInt64(e) & (UInt64(f) ^ UInt64(g)))
            let t = UInt64(h) &+ s1 &+ chv &+ UInt64(k(index)) &+ UInt64(words[index])
            d = (d &+ UInt32(truncatingIfNeeded: t)) & mask
            let s2 = (dbl(a) >> 2) ^ (dbl(a) >> 13) ^ (dbl(a) >> 22)
            let majv = (UInt64(a) & UInt64(b)) | (UInt64(c) & (UInt64(a) | UInt64(b)))
            h = UInt32(truncatingIfNeeded: t &+ s2 &+ majv) & 0xFFFFFFFF
        }
        do {
            let s1 = (dbl(d) >> 6) ^ (dbl(d) >> 11) ^ (dbl(d) >> 25)
            let chv = UInt64(f) ^ (UInt64(d) & (UInt64(e) ^ UInt64(f)))
            let t = UInt64(g) &+ s1 &+ chv &+ UInt64(k(index &+ 1)) &+ UInt64(words[index &+ 1])
            c = (c &+ UInt32(truncatingIfNeeded: t)) & mask
            let s2 = (dbl(h) >> 2) ^ (dbl(h) >> 13) ^ (dbl(h) >> 22)
            let majv = (UInt64(h) & UInt64(a)) | (UInt64(b) & (UInt64(h) | UInt64(a)))
            g = UInt32(truncatingIfNeeded: t &+ s2 &+ majv) & 0xFFFFFFFF
        }
        do {
            let s1 = (dbl(c) >> 6) ^ (dbl(c) >> 11) ^ (dbl(c) >> 25)
            let chv = UInt64(e) ^ (UInt64(c) & (UInt64(d) ^ UInt64(e)))
            let t = UInt64(f) &+ s1 &+ chv &+ UInt64(k(index &+ 2)) &+ UInt64(words[index &+ 2])
            b = (b &+ UInt32(truncatingIfNeeded: t)) & mask
            let s2 = (dbl(g) >> 2) ^ (dbl(g) >> 13) ^ (dbl(g) >> 22)
            let majv = (UInt64(g) & UInt64(h)) | (UInt64(a) & (UInt64(g) | UInt64(h)))
            f = UInt32(truncatingIfNeeded: t &+ s2 &+ majv) & 0xFFFFFFFF
        }
        do {
            let s1 = (dbl(b) >> 6) ^ (dbl(b) >> 11) ^ (dbl(b) >> 25)
            let chv = UInt64(d) ^ (UInt64(b) & (UInt64(c) ^ UInt64(d)))
            let t = UInt64(e) &+ s1 &+ chv &+ UInt64(k(index &+ 3)) &+ UInt64(words[index &+ 3])
            a = (a &+ UInt32(truncatingIfNeeded: t)) & mask
            let s2 = (dbl(f) >> 2) ^ (dbl(f) >> 13) ^ (dbl(f) >> 22)
            let majv = (UInt64(f) & UInt64(g)) | (UInt64(h) & (UInt64(f) | UInt64(g)))
            e = UInt32(truncatingIfNeeded: t &+ s2 &+ majv) & 0xFFFFFFFF
        }
        do {
            let s1 = (dbl(a) >> 6) ^ (dbl(a) >> 11) ^ (dbl(a) >> 25)
            let chv = UInt64(c) ^ (UInt64(a) & (UInt64(b) ^ UInt64(c)))
            let t = UInt64(d) &+ s1 &+ chv &+ UInt64(k(index &+ 4)) &+ UInt64(words[index &+ 4])
            h = (h &+ UInt32(truncatingIfNeeded: t)) & mask
            let s2 = (dbl(e) >> 2) ^ (dbl(e) >> 13) ^ (dbl(e) >> 22)
            let majv = (UInt64(e) & UInt64(f)) | (UInt64(g) & (UInt64(e) | UInt64(f)))
            d = UInt32(truncatingIfNeeded: t &+ s2 &+ majv) & 0xFFFFFFFF
        }
        do {
            let s1 = (dbl(h) >> 6) ^ (dbl(h) >> 11) ^ (dbl(h) >> 25)
            let chv = UInt64(b) ^ (UInt64(h) & (UInt64(a) ^ UInt64(b)))
            let t = UInt64(c) &+ s1 &+ chv &+ UInt64(k(index &+ 5)) &+ UInt64(words[index &+ 5])
            g = (g &+ UInt32(truncatingIfNeeded: t)) & mask
            let s2 = (dbl(d) >> 2) ^ (dbl(d) >> 13) ^ (dbl(d) >> 22)
            let majv = (UInt64(d) & UInt64(e)) | (UInt64(f) & (UInt64(d) | UInt64(e)))
            c = UInt32(truncatingIfNeeded: t &+ s2 &+ majv) & 0xFFFFFFFF
        }
        do {
            let s1 = (dbl(g) >> 6) ^ (dbl(g) >> 11) ^ (dbl(g) >> 25)
            let chv = UInt64(a) ^ (UInt64(g) & (UInt64(h) ^ UInt64(a)))
            let t = UInt64(b) &+ s1 &+ chv &+ UInt64(k(index &+ 6)) &+ UInt64(words[index &+ 6])
            f = (f &+ UInt32(truncatingIfNeeded: t)) & mask
            let s2 = (dbl(c) >> 2) ^ (dbl(c) >> 13) ^ (dbl(c) >> 22)
            let majv = (UInt64(c) & UInt64(d)) | (UInt64(e) & (UInt64(c) | UInt64(d)))
            b = UInt32(truncatingIfNeeded: t &+ s2 &+ majv) & 0xFFFFFFFF
        }
        do {
            let s1 = (dbl(f) >> 6) ^ (dbl(f) >> 11) ^ (dbl(f) >> 25)
            let chv = UInt64(h) ^ (UInt64(f) & (UInt64(g) ^ UInt64(h)))
            let t = UInt64(a) &+ s1 &+ chv &+ UInt64(k(index &+ 7)) &+ UInt64(words[index &+ 7])
            e = (e &+ UInt32(truncatingIfNeeded: t)) & mask
            let s2 = (dbl(b) >> 2) ^ (dbl(b) >> 13) ^ (dbl(b) >> 22)
            let majv = (UInt64(b) & UInt64(c)) | (UInt64(d) & (UInt64(b) | UInt64(c)))
            a = UInt32(truncatingIfNeeded: t &+ s2 &+ majv) & 0xFFFFFFFF
        }
        }

        return [a, b, c, d, e, f, g, h]
    }

    /// drm.py `_sha256_init`: salt-seeded IV from data[0..<7].
    private static func initialSaltState(data: [UInt8]) -> [UInt32] {
        var words: [UInt32] = Array(repeating: 0, count: 14)
        words.append(u32BE(Array(data[0..<3])))
        words.append(u32BE(Array(data[3..<7])))
        for index in 16..<30 {
            var value = sha256SaltSchedule[index - 16]
            if index - 2 >= 14 {
                let base = combinedSigma1(words[index - 2])
                value &+= (index == 16 ? base ^ sigma1Adjustment : base)
            }
            if index - 7 >= 14 { value &+= words[index - 7] }
            if index - 15 >= 14 {
                let base = combinedSigma0(words[index - 15])
                value &+= (index == 29 ? base ^ sigma0Adjustment : base)
            }
            words.append(value & 0xFFFFFFFF)
        }
        words.append(
            (combinedSigma1(words[28]) &+ words[23] &+ combinedSigma0(words[15])
                &+ words[14] &+ block14Adjustment &- roundConstants[14]) & 0xFFFFFFFF
        )
        expandSchedule(&words, from: 31)
        return zip(sha256Initial, sha256Rounds(state: sha256SaltState, words: words, firstRound: 14))
            .map { ($0.0 &+ $0.1) & 0xFFFFFFFF }
    }

    private static func saltedSHA256Digest(data: [UInt8]) -> [UInt8] {
        precondition(data.count >= 7)
        let length = 57 + data.count
        var padded = Array(data[7...])
        padded.append(0x80)
        let padZeros = ((55 - length) % 64 + 64) % 64
        padded.append(contentsOf: Array(repeating: 0, count: padZeros))
        var lengthBytes = UInt64(length * 8).bigEndian
        padded.append(contentsOf: withUnsafeBytes(of: &lengthBytes) { Array($0) })

        var state = initialSaltState(data: data)
        for offset in stride(from: 0, to: padded.count, by: 64) {
            let block = Array(padded[offset..<Swift.min(offset + 64, padded.count)])
            let blockWords: [UInt32] = stride(from: 0, to: 64, by: 4).map { i in
                var bytes = Array(block[i..<Swift.min(i &+ 4, block.count)])
                while bytes.count < 4 { bytes.append(0) }
                return u32BE(bytes)
            }
            var schedule = blockWords
            expandSchedule(&schedule)
            let rounds = sha256Rounds(state: state, words: schedule)
            state = zip(state, rounds).map { ($0.0 &+ $0.1) & 0xFFFFFFFF }
        }
        return state.flatMap { withUnsafeBytes(of: $0.bigEndian) { Array($0) } }
    }

    private static func wordsLE4Even(_ input: [UInt8]) -> [UInt64] {
        var padded = input
        while padded.count % 4 != 0 { padded.append(0) }
        var words: [UInt64] = []
        for i in stride(from: 0, to: padded.count, by: 4) {
            words.append(UInt64(padded[i]) | UInt64(padded[i+1]) << 8
                | UInt64(padded[i+2]) << 16 | UInt64(padded[i+3]) << 24)
        }
        if words.count % 2 == 1 { words.append(0) }
        return words
    }

    private static let cs64Factor: UInt64 = 0x82893933
    private static let cs64Adjustment0: UInt64 = 0xF2F90B1A
    private static let cs64Adjustment1: UInt64 = 0x0B1A0000

    private static func cs64Digest(data: [UInt8], digest: [UInt8]) -> [UInt64] {
        let keyA = UInt64(digest[0]) | UInt64(digest[1]) << 8 | UInt64(digest[2]) << 16 | UInt64(digest[3]) << 24
        let keyB = UInt64(digest[4]) | UInt64(digest[5]) << 8 | UInt64(digest[6]) << 16 | UInt64(digest[7]) << 24
        let ka = keyA | 1
        let kb = keyB | 1
        let mask: UInt64 = 0xFFFFFFFF
        let factors: [UInt64] = [(ka * cs64Factor) & mask, (kb * cs64Factor) & mask]

        var terms: [UInt64] = cs64Coefficients.enumerated().map { i, p in (p.0 * factors[i % 2]) & mask }
        var offsets: [UInt64] = cs64Coefficients.map { $0.1 }
        for (i, w) in wordsLE4Even([UInt8](repeating: 0, count: 1) + data).enumerated() {
            var term = (w * (i % 2 == 0 ? ka : kb)) & mask
            var offset = (rol16x(w) * (i % 2 == 0 ? 0xEF0569FB : 0xC31713DB)) & mask
            if i == 0 {
                term = (term &+ cs64Adjustment0 &* factors[0]) & mask
                offset = (offset &+ cs64Adjustment1) & mask
            }
            terms.append(term)
            offsets.append(offset)
        }
        var swapAcc: UInt64 = 0, swapLast: UInt64 = 0, st: UInt64 = 0, acc: UInt64 = 0
        var i = 0
        while i < terms.count {
            let x = terms[i], y = terms[i &+ 1]
            var t = rol16x((offsets[i] &+ x) & mask)
            var q = (t &* 0x76F50F34) & mask
            swapAcc = (swapAcc &+ ((rol16x(q) &* 0xC3EFEA97 &+ q) & mask)) & mask
            t = rol16x((offsets[i &+ 1] &+ y) & mask)
            q = (t &* 0x1881CE3C) & mask
            swapLast = ((rol16x(q) &* 0x35BD1EC9 &+ q) & mask)
            swapAcc = (swapAcc &+ swapLast) & mask

            st = (st &* ka &+ x) & mask
            st = (rol16x(st) &* 0xCF98B111) & mask
            st = (rol16x(st) &* 0x87085B9F) & mask
            st = (rol16x(st) &* 0x12CEB96D) & mask
            st = (rol16x(st) &* 0x257E1D83) & mask
            acc = (acc &+ st) & mask
            t = (st &* kb &+ y) & mask
            t = (rol16x(t) &* 0xA27416F5) & mask
            t = (rol16x(t) &* 0xD38396FF) & mask
            st = (rol16x((rol16x(t) &* 0x7C932B89) & mask) &* 0xBFA49F69) & mask
            acc = (acc &+ st) & mask
            i &+= 2
        }
        return [swapLast ^ st, swapAcc ^ acc]
    }

    static func generate(unixTimestamp: Double = Date().timeIntervalSince1970) -> String {
        var ticks = unixTimestamp + winEpoch
        ticks -= ticks.truncatingRemainder(dividingBy: 300)
        ticks *= 1e9 / 100
        let tokenString = "\(String(format: "%.0f", ticks))\(trustedClientToken)"
        let data = Array(tokenString.utf8)
        let sha = saltedSHA256Digest(data: data)
        let cs = cs64Digest(data: data, digest: sha)
        let csHex: String = cs.flatMap { w -> [UInt8] in
            let w32 = UInt32(truncatingIfNeeded: w)
            return [UInt8(w32 & 0xFF), UInt8((w32 >> 8) & 0xFF), UInt8((w32 >> 16) & 0xFF), UInt8((w32 >> 24) & 0xFF)]
        }.map { String(format: "%02X", $0) }.joined()
        return csHex + "-" + sha.map { String(format: "%02X", $0) }.joined()
    }

    // Test helpers (parity harness).
    static func probeSHA(data: [UInt8]) -> [UInt8] { saltedSHA256Digest(data: data) }
    static func probeCS64Stages(data: [UInt8], digest: [UInt8]) -> ([UInt64], [UInt64], [UInt64]) {
        let mask: UInt64 = 0xFFFFFFFF
        let keyA = UInt64(digest[0]) | UInt64(digest[1]) << 8 | UInt64(digest[2]) << 16 | UInt64(digest[3]) << 24
        let keyB = UInt64(digest[4]) | UInt64(digest[5]) << 8 | UInt64(digest[6]) << 16 | UInt64(digest[7]) << 24
        let ka = keyA | 1
        let kb = keyB | 1
        let factors: [UInt64] = [(ka * cs64Factor) & mask, (kb * cs64Factor) & mask]
        var terms: [UInt64] = cs64Coefficients.enumerated().map { i, p in (p.0 * factors[i % 2]) & mask }
        let offsets0 = cs64Coefficients.map { $0.1 }
        var offsets: [UInt64] = offsets0
        for (i, w) in wordsLE4Even([UInt8](repeating: 0, count: 1) + data).enumerated() {
            var term = (w * (i % 2 == 0 ? ka : kb)) & mask
            var offset = (rol16x(w) * (i % 2 == 0 ? 0xEF0569FB : 0xC31713DB)) & mask
            if i == 0 {
                term = (term &+ cs64Adjustment0 &* factors[0]) & mask
                offset = (offset &+ cs64Adjustment1) & mask
            }
            terms.append(term)
            offsets.append(offset)
        }
        return (terms, offsets, wordsLE4Even([UInt8](repeating: 0, count: 1) + data))
    }
    static func probeCS64(data: [UInt8], digest: [UInt8]) -> [UInt64] { cs64Digest(data: data, digest: digest) }
}
