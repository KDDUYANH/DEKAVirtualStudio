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
    static let camera   = Logger(subsystem: "com.dtek.studio", category: "camera")
    static let metal    = Logger(subsystem: "com.dtek.studio", category: "metal")
    static let pipeline = Logger(subsystem: "com.dtek.studio", category: "pipeline")
    static let ai       = Logger(subsystem: "com.dtek.studio", category: "ai")
    static let audio    = Logger(subsystem: "com.dtek.studio", category: "audio")
    static let stream   = Logger(subsystem: "com.dtek.studio", category: "stream")
    static let record   = Logger(subsystem: "com.dtek.studio", category: "record")
    static let security = Logger(subsystem: "com.dtek.studio", category: "security")
    static let project  = Logger(subsystem: "com.dtek.studio", category: "project")
}

/// Monotonic host time in seconds (same clock as AVCaptureSession / AVAudioTime host time).
@inline(__always) func hostTimeSeconds() -> Double {
    CMClockGetTime(CMClockGetHostTimeClock()).seconds
}
