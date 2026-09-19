//
//  Concurrency.swift
//  Small, allocation-free primitives for the real-time path. The render path never awaits,
//  never hops to the main actor and never takes a lock that the UI can hold for long.
//

import Foundation
import os
import CoreMedia

/// Minimal lock-protected box. Critical sections must stay tiny (copying a struct).
final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = OSAllocatedUnfairLock()

    init(_ value: Value) { self.value = value }

    func get() -> Value {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Value) {
        lock.lock(); defer { lock.unlock() }
        value = newValue
    }

    @discardableResult
    func mutate<R>(_ body: (inout Value) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        return body(&value)
    }
}

enum Log {
    static let camera   = Logger(subsystem: "vn.kdproductions.deka", category: "camera")
    static let metal    = Logger(subsystem: "vn.kdproductions.deka", category: "metal")
    static let pipeline = Logger(subsystem: "vn.kdproductions.deka", category: "pipeline")
    static let ai       = Logger(subsystem: "vn.kdproductions.deka", category: "ai")
    static let audio    = Logger(subsystem: "vn.kdproductions.deka", category: "audio")
    static let stream   = Logger(subsystem: "vn.kdproductions.deka", category: "stream")
    static let record   = Logger(subsystem: "vn.kdproductions.deka", category: "record")
    static let security = Logger(subsystem: "vn.kdproductions.deka", category: "security")
    static let project  = Logger(subsystem: "vn.kdproductions.deka", category: "project")
}

/// Monotonic host time in seconds (same clock as AVCaptureSession / AVAudioTime host time).
@inline(__always) func hostTimeSeconds() -> Double {
    CMClockGetTime(CMClockGetHostTimeClock()).seconds
}
