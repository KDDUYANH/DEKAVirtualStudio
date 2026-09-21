//
//  ThermalManager.swift
//  ProcessInfo.thermalState → operator warning first, then ordered, configurable degradation.
//  The policy is a pure function (unit tested); the manager only observes and dispatches.
//

import Foundation

enum ThermalLevel: Int, Comparable, Codable {
    case nominal, fair, serious, critical
    static func < (a: ThermalLevel, b: ThermalLevel) -> Bool { a.rawValue < b.rawValue }

    init(_ s: ProcessInfo.ThermalState) {
        switch s {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .serious
        }
    }
    var label: String {
        switch self {
        case .nominal: return "NORMAL"
        case .fair: return "WARM"
        case .serious: return "HOT"
        case .critical: return "CRITICAL"
        }
    }
}

enum ThermalStep: String, Codable, CaseIterable {
    case reduceFrameRate      // 60 → 30 fps
    case reduceAIRate         // AI 30 → 15 fps
    case aiToChroma           // AI cutout → chroma key
}

enum ThermalAction: Equatable {
    case warn(String)
    case apply(ThermalStep)
}

struct ThermalContext: Equatable {
    var outputFPS: Int
    var aiActive: Bool
    var aiFPS: Int
    var chromaFallbackAllowed: Bool
    var applied: Set<ThermalStep>
}

struct ThermalPolicy: Codable, Equatable {
    /// Order in which quality is traded for temperature. Operator-configurable.
    var order: [ThermalStep] = [.reduceAIRate, .reduceFrameRate, .aiToChroma]
    var enabled = true

    func isApplicable(_ step: ThermalStep, _ c: ThermalContext) -> Bool {
        guard !c.applied.contains(step) else { return false }
        switch step {
        case .reduceFrameRate: return c.outputFPS > 30
        case .reduceAIRate: return c.aiActive && c.aiFPS > 15
        case .aiToChroma: return c.aiActive && c.chromaFallbackAllowed
        }
    }

    /// fair → warn only. serious → next single step. critical → every remaining step.
    func actions(level: ThermalLevel, context c: ThermalContext) -> [ThermalAction] {
        guard enabled else { return level >= .serious ? [.warn("Device is \(level.label). Automatic protection is off.")] : [] }
        let pending = order.filter { isApplicable($0, c) }
        switch level {
        case .nominal:
            return []
        case .fair:
            return pending.isEmpty ? [] : [.warn("Device is warming up. If it gets hot, D-TEK will first \(Self.describe(pending[0])).")]
        case .serious:
            guard let next = pending.first else { return [.warn("Device is hot. Consider shade, a fan, or removing the case.")] }
            return [.warn("Device is hot: \(Self.describe(next))."), .apply(next)]
        case .critical:
            return [.warn("Device is critically hot: protecting the stream.")] + pending.map { .apply($0) }
        }
    }

    static func describe(_ s: ThermalStep) -> String {
        switch s {
        case .reduceFrameRate: return "reduce 60 fps to 30 fps"
        case .reduceAIRate: return "reduce AI cutout to 15 fps"
        case .aiToChroma: return "switch AI cutout to green screen"
        }
    }
}

final class ThermalManager {
    private(set) var level = ThermalLevel(ProcessInfo.processInfo.thermalState)
    var policy = ThermalPolicy()
    /// Supplies the current pipeline context (main thread).
    var contextProvider: (() -> ThermalContext)?
    /// Performs actions (main thread).
    var onActions: (([ThermalAction], ThermalLevel) -> Void)?

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(changed),
                                               name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
    }

    @objc private func changed() {
        DispatchQueue.main.async { self.evaluate() }
    }

    func evaluate() {
        level = ThermalLevel(ProcessInfo.processInfo.thermalState)
        guard let ctx = contextProvider?() else { return }
        let actions = policy.actions(level: level, context: ctx)
        onActions?(actions, level)
    }
}
