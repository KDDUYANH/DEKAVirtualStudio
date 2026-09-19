//
//  PrivacyGate.swift
//  RAW CAMERA VIDEO NEVER LEAVES THE DEVICE BEFORE THE USER STARTS STREAMING.
//
//  Enforced twice:
//   1. The publisher is attached to the master output ONLY between GO LIVE and STOP.
//   2. The publisher itself refuses frames unless this gate is open (defence in depth).
//  Only the processed MASTER program is ever published; the raw camera buffer is never
//  handed to the network layer.
//

import Foundation

final class PrivacyGate {
    private let open = Locked(false)
    private(set) var openedAt: Date?

    /// True only while the operator has an active GO LIVE.
    var allowsUpload: Bool { open.get() }

    func openForStreaming() {
        open.set(true)
        openedAt = Date()
        Log.security.notice("Privacy gate OPEN (operator started streaming)")
    }

    func close() {
        open.set(false)
        openedAt = nil
        Log.security.notice("Privacy gate CLOSED")
    }
}
