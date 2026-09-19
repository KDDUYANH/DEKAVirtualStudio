//
//  SceneEngine.swift
//  Scenes + CUT/FADE transitions. Switching a scene only swaps parameters the render thread
//  reads each frame — the camera, encoder and stream are never touched, so going live and
//  switching scenes can happen at any time without a hiccup.
//

import Foundation

/// Pure transition state (unit tested).
struct TransitionState: Equatable {
    var from: UUID?
    var to: UUID
    var startTime: Double
    var duration: Double

    /// 0…1 progress; 1 when finished or for a CUT.
    func progress(at time: Double) -> Float {
        guard let _ = from, duration > 0 else { return 1 }
        let p = (time - startTime) / duration
        // Smoothstep easing: broadcast dissolves look linear-in-perception with an eased curve.
        let x = Float(min(max(p, 0), 1))
        return x * x * (3 - 2 * x)
    }

    func isFinished(at time: Double) -> Bool {
        from == nil || time - startTime >= duration
    }
}

/// What the render thread needs for one frame.
struct SceneRenderState {
    let outgoing: SceneModel?     // non-nil only during a FADE
    let incoming: SceneModel
    let mix: Float                // 0 = outgoing, 1 = incoming
}

final class SceneEngine {

    private struct State {
        var scenes: [SceneModel]
        var transition: TransitionState
    }

    private let state: Locked<State>

    /// Called on the main thread after the active scene changes (UI + graphics residency).
    var onActiveSceneChanged: ((SceneModel) -> Void)?

    init(scenes: [SceneModel], activeID: UUID?) {
        let list = scenes.isEmpty ? SceneModel.defaultScenes() : scenes
        let active = activeID.flatMap { id in list.first { $0.id == id }?.id } ?? list[0].id
        state = Locked(State(scenes: list, transition: TransitionState(from: nil, to: active, startTime: 0, duration: 0)))
    }

    var scenes: [SceneModel] { state.get().scenes }
    var activeSceneID: UUID { state.get().transition.to }
    var activeScene: SceneModel {
        let s = state.get()
        return s.scenes.first { $0.id == s.transition.to } ?? s.scenes[0]
    }

    /// Render-thread snapshot.
    func renderState(at time: Double) -> SceneRenderState {
        let s = state.get()
        let incoming = s.scenes.first { $0.id == s.transition.to } ?? s.scenes[0]
        guard !s.transition.isFinished(at: time), let fromID = s.transition.from,
              let outgoing = s.scenes.first(where: { $0.id == fromID }) else {
            return SceneRenderState(outgoing: nil, incoming: incoming, mix: 1)
        }
        return SceneRenderState(outgoing: outgoing, incoming: incoming, mix: s.transition.progress(at: time))
    }

    func take(_ id: UUID, transition: TransitionKind, duration: Double, now: Double = hostTimeSeconds()) {
        var changed: SceneModel?
        state.mutate { s in
            guard s.scenes.contains(where: { $0.id == id }), id != s.transition.to else { return }
            let from: UUID? = (transition == .fade && duration > 0) ? s.transition.to : nil
            s.transition = TransitionState(from: from, to: id, startTime: now, duration: transition == .fade ? duration : 0)
            changed = s.scenes.first { $0.id == id }
        }
        if let changed { onActiveSceneChanged?(changed) }
    }

    /// Edits the ACTIVE scene live (colour, key, background… all update on the next frame).
    func updateActive(_ body: (inout SceneModel) -> Void) {
        state.mutate { s in
            guard let i = s.scenes.firstIndex(where: { $0.id == s.transition.to }) else { return }
            body(&s.scenes[i])
        }
    }

    func update(sceneID: UUID, _ body: (inout SceneModel) -> Void) {
        state.mutate { s in
            guard let i = s.scenes.firstIndex(where: { $0.id == sceneID }) else { return }
            body(&s.scenes[i])
        }
    }

    func replaceAll(_ scenes: [SceneModel], activeID: UUID?) {
        guard !scenes.isEmpty else { return }
        state.mutate { s in
            s.scenes = scenes
            let active = activeID.flatMap { id in scenes.first { $0.id == id }?.id } ?? scenes[0].id
            s.transition = TransitionState(from: nil, to: active, startTime: 0, duration: 0)
        }
    }

    @discardableResult
    func addScene(named name: String, copying source: SceneModel? = nil) -> SceneModel {
        var scene = source ?? SceneModel(name: name)
        scene.id = UUID()
        scene.name = name
        state.mutate { $0.scenes.append(scene) }
        return scene
    }

    func removeScene(_ id: UUID) {
        state.mutate { s in
            guard s.scenes.count > 1 else { return }
            s.scenes.removeAll { $0.id == id }
            if s.transition.to == id || s.transition.from == id {
                s.transition = TransitionState(from: nil, to: s.scenes[0].id, startTime: 0, duration: 0)
            }
        }
    }

    func renameScene(_ id: UUID, to name: String) {
        update(sceneID: id) { $0.name = name }
    }
}
