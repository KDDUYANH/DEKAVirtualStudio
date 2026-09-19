//
//  StreamStats.swift
//  Transport statistics derived from the WebRTC stats report (RFC 8888 / W3C webrtc-stats):
//  outbound-rtp, remote-inbound-rtp and candidate-pair. Rates are computed from counter
//  deltas between reports — exactly how chrome://webrtc-internals does it.
//

import Foundation

struct StreamStats: Equatable {
    var videoBitrateKbps: Double = 0
    var audioBitrateKbps: Double = 0
    var targetBitrateKbps: Double = 0
    var availableOutgoingKbps: Double = 0
    var rttMs: Double = 0
    var packetLossPercent: Double = 0
    var jitterMs: Double = 0
    var framesPerSecond: Double = 0
    var frameWidth: Int = 0
    var frameHeight: Int = 0
    var framesEncoded: Int = 0
    var framesSent: Int = 0
    var qualityLimitation: String = "none"
    var encoder: String = ""
    var viewers: Int = 0
    var connectionState: String = "idle"
}

/// Raw counters sampled from one report.
struct OutboundSample: Equatable {
    var timestampMs: Double
    var videoBytesSent: UInt64
    var audioBytesSent: UInt64
    var framesEncoded: UInt64
}

enum StatsMath {
    /// kbps from a byte counter delta; resets (counter went down) yield 0 instead of garbage.
    static func kbps(bytesNow: UInt64, bytesBefore: UInt64, msNow: Double, msBefore: Double) -> Double {
        guard msNow > msBefore, bytesNow >= bytesBefore else { return 0 }
        return Double(bytesNow - bytesBefore) * 8 / (msNow - msBefore)   // bits per ms == kbps
    }

    /// Encoded fps from a frame counter delta.
    static func fps(framesNow: UInt64, framesBefore: UInt64, msNow: Double, msBefore: Double) -> Double {
        guard msNow > msBefore, framesNow >= framesBefore else { return 0 }
        return Double(framesNow - framesBefore) * 1000 / (msNow - msBefore)
    }
}

/// Exponential backoff with jitter, capped. Pure and deterministic given `random`.
struct ReconnectPolicy: Equatable {
    var baseDelay: Double = 1
    var maxDelay: Double = 15
    var maxAttempts: Int = 20

    func delay(forAttempt attempt: Int, random: Double = Double.random(in: 0...1)) -> Double? {
        guard attempt >= 1, attempt <= maxAttempts else { return nil }
        let exp = min(maxDelay, baseDelay * pow(2, Double(attempt - 1)))
        return exp * (0.75 + 0.5 * random)    // ±25 % jitter so many publishers don't retry in lockstep
    }
}
