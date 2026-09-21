//
//  StudioController.swift
//  Wires the engines together and exposes a small, UI-friendly state. SwiftUI only ever talks to
//  this object; the video path runs entirely inside the engines on their own threads.
//

import SwiftUI
import AVFoundation
import Observation
import HaishinKit

@MainActor
@Observable
final class StudioController {

    // MARK: Engines (not observed)
    let camera = CameraManager()
    let audio = AudioEngine()
    let gate: PrivacyGate
    let tokens: TokenService
    let recorder = RecordingEngine()
    let projects = ProjectManager()
    let thermal = ThermalManager()
    @ObservationIgnored private(set) var metal: MetalContext?
    @ObservationIgnored private(set) var compositor: MasterCompositor?
    @ObservationIgnored private(set) var scenesEngine: SceneEngine
    @ObservationIgnored private(set) var lutLibrary: LUTLibrary?
    @ObservationIgnored private var backgrounds: BackgroundEngine?
    @ObservationIgnored private var graphics: GraphicsEngine?
    @ObservationIgnored private var segmentation: SegmentationEngine?
    @ObservationIgnored private(set) var publisher: SRTEngine
    @ObservationIgnored private var telemetryTimer: Timer?
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?

    // MARK: Observed UI state
    var project: StudioProject
    var scenes: [SceneModel] = []
    var activeSceneID: UUID
    var capabilities = CameraCapabilities()
    var telemetry = TelemetrySnapshot()
    var streamState: StreamState = .off
    var lutItems: [LUTItem] = []
    var checks: [CheckResult] = []
    var isCheckRunning = false
    var setupError: String?
    var banner: String?
    var events: [String] = []
    var previewMode: Int32 = Int32(DEKA_PREVIEW_PROGRAM)
    var recordingMode: RecordingMode = .program
    var rotate180 = false
    var cameraActive = false
    var micActive = false
    var appliedThermalSteps: Set<ThermalStep> = []
    var projectList: [ProjectSummary] = []

    var activeScene: SceneModel { scenes.first { $0.id == activeSceneID } ?? scenes.first ?? SceneModel(name: "Scene") }
    var currentMode: CaptureMode { CaptureMode(resolution: project.output.resolution, fps: project.output.fps) }
    var srtReturnView: MTHKView { publisher.returnView }

    init() {
        let pm = ProjectManager()
        let initial = pm.list().first.flatMap { try? pm.load(id: $0.id) } ?? (try? pm.create(name: "Studio A")) ?? StudioProject(name: "Studio A")
        let engine = SceneEngine(scenes: initial.scenes, activeID: initial.activeSceneID)
        let gate = PrivacyGate()
        let tokens = TokenService()
        // Every stored property is initialised before `self` is used.
        self.gate = gate
        self.tokens = tokens
        self.publisher = SRTEngine(gate: gate)
        self.project = initial
        self.scenesEngine = engine
        self.activeSceneID = engine.activeSceneID
        self.scenes = engine.scenes
        buildPipeline()
    }

    // MARK: Setup

    private func buildPipeline() {
        do {
            let ctx = try MetalContext()
            metal = ctx
            let luts = LUTLibrary(device: ctx.device)
            lutLibrary = luts
            lutItems = luts.sortedItems
            let bg = BackgroundEngine(context: ctx)
            let gfx = GraphicsEngine(context: ctx)
            let seg = SegmentationEngine(context: ctx)
            let projectID = project.id
            let pm = projects
            bg.assetURL = { pm.assetURL(projectID: projectID, name: $0) }
            gfx.assetURL = { pm.assetURL(projectID: projectID, name: $0) }
            backgrounds = bg; graphics = gfx; segmentation = seg
            let comp = MasterCompositor(context: ctx, scenes: scenesEngine, backgrounds: bg, graphics: gfx,
                                        segmentation: seg, lutLibrary: luts)
            compositor = comp
            camera.consumer = comp
            seg.onFallbackSuggested = { [weak self] in
                Task { @MainActor in self?.aiCannotKeepUp() }
            }
        } catch {
            setupError = error.localizedDescription
        }

        camera.onCapabilities = { [weak self] caps in Task { @MainActor in self?.capabilities = caps } }
        camera.onRotate180 = { [weak self] r in
            Task { @MainActor in
                guard let self else { return }
                self.rotate180 = r
                self.compositor?.config.mutate { $0.rotate180 = r }
            }
        }
        camera.onRuntimeError = { [weak self] msg in Task { @MainActor in self?.post(msg) } }
        publisher.onStateChange = { [weak self] s in self?.streamStateChanged(s) }
        publisher.onEvent = { [weak self] msg in Task { @MainActor in self?.post(msg) } }
        recorder.onAutoStop = { [weak self] msg in
            Task { @MainActor in self?.post(msg); await self?.stopRecording() }
        }
        scenesEngine.onActiveSceneChanged = { [weak self] scene in
            Task { @MainActor in self?.activeSceneChangedInEngine(scene) }
        }
        thermal.contextProvider = { [weak self] in
            guard let self else { return ThermalContext(outputFPS: 30, aiActive: false, aiFPS: 0, chromaFallbackAllowed: false, applied: []) }
            return MainActor.assumeIsolated {
                ThermalContext(outputFPS: self.project.output.fps,
                               aiActive: self.activeScene.keyMode == .aiCutout,
                               aiFPS: self.activeScene.segmentation.targetFPS,
                               chromaFallbackAllowed: self.activeScene.segmentation.fallbackToChroma,
                               applied: self.appliedThermalSteps)
            }
        }
        thermal.onActions = { [weak self] actions, level in
            MainActor.assumeIsolated { self?.handleThermal(actions, level: level) }
        }
    }

    /// Called once the UI is on screen.
    func start() async {
        guard metal != nil else { return }
        let camOK = await CameraManager.requestAccess()
        let micOK = await AudioEngine.requestAccess()
        if camOK {
            await applyMode(currentMode, reason: nil)
            camera.apply(project.camera)
            camera.start()
            cameraActive = true
        } else {
            setupError = CameraManager.CameraError.notAuthorized.localizedDescription
        }
        if micOK {
            do {
                try audio.configureSession()
                audio.apply(project.audio)
                try audio.start()
                micActive = true
            } catch { post("Audio: \(error.localizedDescription)") }
        } else {
            post(AudioEngine.AudioError.notAuthorized.localizedDescription)
        }
        compositor?.config.mutate {
            $0.outputSize = project.output.resolution.size
            $0.cleanFeed = project.output.cleanFeedLiveOutput
        }
        backgrounds?.outputAspect = Float(project.output.resolution.size.width / project.output.resolution.size.height)
        graphics?.setOutputSize(project.output.resolution.size)
        refreshSceneResources()
        startTelemetry()
        thermal.evaluate()
        projectList = projects.list()
    }

    func handleMemoryWarning() { compositor?.handleMemoryWarning() }

    // MARK: Camera mode / presets

    func applyMode(_ mode: CaptureMode, reason: String?) async {
        var target = mode
        if !capabilities.modes.isEmpty, !capabilities.supports(mode) {
            let r = QualityPreset.resolve(QualityPreset(id: .custom, mode: mode, targetKbps: 0, minKbps: 0, maxKbps: 0, audioKbps: 0),
                                          supported: capabilities.modes)
            guard let m = r.mode else { post(r.note ?? "Mode not supported"); return }
            target = m
            if let note = r.note { post(note) }
        }
        do {
            do {
                try await camera.configure(position: project.camera.position, mode: target)
            } catch CameraManager.CameraError.modeUnsupported(let m) {
                // e.g. front camera without 1080p60: fall back to the universal 1080p30.
                let safe = CaptureMode(resolution: .hd1080, fps: 30)
                guard m != safe else { throw CameraManager.CameraError.modeUnsupported(m) }
                try await camera.configure(position: project.camera.position, mode: safe)
                post("\(m.label) not available on this camera — using \(safe.label)")
                target = safe
            }
            project.output.resolution = target.resolution
            project.output.fps = target.fps
            compositor?.config.mutate { $0.outputSize = target.resolution.size }
            backgrounds?.outputAspect = Float(target.resolution.size.width / target.resolution.size.height)
            graphics?.setOutputSize(target.resolution.size)
            if let reason { post(reason) }
            scheduleAutosave()
        } catch {
            post(error.localizedDescription)
        }
    }

    func applyPreset(_ id: QualityPresetID) async {
        guard let preset = QualityPreset.preset(id) else { project.output.preset = .custom; return }
        let r = QualityPreset.resolve(preset, supported: capabilities.modes)
        guard let mode = r.mode else { post(r.note ?? "Preset not supported"); return }
        preset.apply(to: &project.output)
        if let note = r.note { post(note) }
        await applyMode(mode, reason: nil)
    }

    func switchCamera() async {
        project.camera.position = project.camera.position == .back ? .front : .back
        compositor?.config.mutate { $0.mirror = false }
        await applyMode(currentMode, reason: nil)
        camera.apply(project.camera)
    }

    func updateCamera(_ body: (inout CameraSettings) -> Void) {
        body(&project.camera)
        camera.apply(project.camera)
        scheduleAutosave()
    }

    // MARK: Scenes

    func take(_ id: UUID) {
        scenesEngine.take(id, transition: project.output.transition, duration: project.output.transitionDuration)
        activeSceneID = id
    }

    private func activeSceneChangedInEngine(_ scene: SceneModel) {
        activeSceneID = scene.id
        refreshSceneResources()
    }

    /// Live edit of the active scene: applied on the next frame (never interrupts the stream).
    func editActive(_ body: (inout SceneModel) -> Void) {
        guard let i = scenes.firstIndex(where: { $0.id == activeSceneID }) else { return }
        let before = scenes[i]
        body(&scenes[i])
        let after = scenes[i]
        scenesEngine.update(sceneID: after.id) { $0 = after }
        if before.graphics != after.graphics { graphics?.update(sceneID: after.id, settings: after.graphics) }
        if before.lut.lutID != after.lut.lutID { compositor?.warmLUT(id: after.lut.lutID) }
        if before.background != after.background { backgrounds?.preload(after.background) }
        if before.keyMode != after.keyMode || before.segmentation != after.segmentation { configureSegmentation() }
        scheduleAutosave()
    }

    func addScene() {
        let s = scenesEngine.addScene(named: "Scene \(scenes.count + 1)", copying: activeScene)
        scenes = scenesEngine.scenes
        graphics?.update(sceneID: s.id, settings: s.graphics)
        post("Added \(s.name)")
        scheduleAutosave()
    }

    func deleteScene(_ id: UUID) {
        scenesEngine.removeScene(id)
        scenes = scenesEngine.scenes
        activeSceneID = scenesEngine.activeSceneID
        refreshSceneResources()
        scheduleAutosave()
    }

    func renameScene(_ id: UUID, _ name: String) {
        scenesEngine.renameScene(id, to: name)
        scenes = scenesEngine.scenes
        scheduleAutosave()
    }

    private func refreshSceneResources() {
        guard let graphics else { return }
        for s in scenes { graphics.update(sceneID: s.id, settings: s.graphics) }
        graphics.retain(sceneIDs: Set(scenes.map(\.id)))
        for s in scenes { compositor?.warmLUT(id: s.lut.enabled ? s.lut.lutID : nil) }
        backgrounds?.preload(activeScene.background)
        configureSegmentation()
    }

    private func configureSegmentation() {
        let s = activeScene
        segmentation?.configure(enabled: s.keyMode == .aiCutout, settings: s.segmentation)
    }

    private func aiCannotKeepUp() {
        guard activeScene.keyMode == .aiCutout, activeScene.segmentation.fallbackToChroma else {
            post("AI cutout is struggling on this device. Consider green screen.")
            return
        }
        editActive { $0.keyMode = .greenScreen }
        post("AI cutout could not keep up — switched to GREEN SCREEN.")
    }

    // MARK: LUTs

    func importLUT(from url: URL) {
        guard let lib = lutLibrary else { return }
        do {
            let item = try lib.importFile(at: url)
            lutItems = lib.sortedItems
            editActive { $0.lut.lutID = item.id; $0.lut.enabled = true }
            post("LUT \(item.name) (\(item.size)³) imported")
        } catch { post(error.localizedDescription) }
    }

    func deleteLUT(_ id: String) {
        lutLibrary?.delete(id: id)
        compositor?.evictLUT(id: id)
        lutItems = lutLibrary?.sortedItems ?? []
        for s in scenes where s.lut.lutID == id {
            scenesEngine.update(sceneID: s.id) { $0.lut.lutID = nil; $0.lut.enabled = false }
        }
        scenes = scenesEngine.scenes
    }

    func toggleFavoriteLUT(_ id: String) {
        lutLibrary?.toggleFavorite(id: id)
        lutItems = lutLibrary?.sortedItems ?? []
    }

    // MARK: Assets

    func importBackground(from url: URL) {
        do {
            let name = try projects.addAsset(projectID: project.id, from: url)
            let kind = BackgroundEngine.kind(forAsset: name) ?? .image
            editActive { $0.background.kind = kind; $0.background.assetName = name }
        } catch { post(error.localizedDescription) }
    }

    func reloadBrowserBackground() {
        backgrounds?.reloadBrowser()
        post("Reloading web background…")
    }

    func importLogo(from url: URL) {
        do {
            let name = try projects.addAsset(projectID: project.id, from: url)
            graphics?.invalidateAsset(name)
            editActive { $0.graphics.logoAsset = name; $0.graphics.logoEnabled = true }
        } catch { post(error.localizedDescription) }
    }

    // MARK: Bindings for the UI (edit the ACTIVE scene live)

    // SwiftUI may treat Binding closures as Sendable; they are always invoked on the main
    // thread, which assumeIsolated asserts (and documents) explicitly.
    func sceneBinding<T: Sendable>(_ kp: WritableKeyPath<SceneModel, T>) -> Binding<T> {
        Binding(get: { MainActor.assumeIsolated { self.activeScene[keyPath: kp] } },
                set: { v in MainActor.assumeIsolated { self.editActive { $0[keyPath: kp] = v } } })
    }

    func cameraBinding<T: Sendable>(_ kp: WritableKeyPath<CameraSettings, T>) -> Binding<T> {
        Binding(get: { MainActor.assumeIsolated { self.project.camera[keyPath: kp] } },
                set: { v in MainActor.assumeIsolated { self.updateCamera { $0[keyPath: kp] = v } } })
    }

    func audioBinding<T: Sendable>(_ kp: WritableKeyPath<AudioSettings, T>) -> Binding<T> {
        Binding(get: { MainActor.assumeIsolated { self.project.audio[keyPath: kp] } },
                set: { v in MainActor.assumeIsolated { self.updateAudio { $0[keyPath: kp] = v } } })
    }

    func outputBinding<T: Sendable>(_ kp: WritableKeyPath<OutputSettings, T>) -> Binding<T> {
        Binding(get: { MainActor.assumeIsolated { self.project.output[keyPath: kp] } },
                set: { v in MainActor.assumeIsolated {
                    self.project.output[keyPath: kp] = v
                    self.compositor?.config.mutate { $0.cleanFeed = self.project.output.cleanFeedLiveOutput }
                    self.scheduleAutosave()
                } })
    }

    // MARK: Preview

    func setPreviewMode(_ m: Int32) {
        previewMode = m
        compositor?.renderer.previewMode.set(m)
    }

    // MARK: Streaming

    func goLive() async {
        guard !streamState.isOnAir, let compositor else { return }
        guard let publishURL = project.output.srtPublishURL else {
            post("Invalid SRT host or port. Configure SRT Output in OUTPUT panel.")
            return
        }
        let returnURL = project.output.srtReturnURL
        let cfg = StreamConfiguration(resolution: project.output.resolution, fps: project.output.fps,
                                      videoBitrateKbps: project.output.videoBitrateKbps,
                                      minVideoBitrateKbps: project.output.minVideoBitrateKbps,
                                      audioBitrateKbps: project.output.audioBitrateKbps,
                                      videoCodec: project.output.videoCodec,
                                      streamName: project.output.srtStreamId,
                                      srtPublishURL: publishURL,
                                      srtReturnURL: returnURL)
        // Open the gate and attach the publisher ONLY now — the explicit operator action.
        gate.openForStreaming()
        compositor.addSink(publisher)
        audio.addSink(publisher)
        do {
            try await publisher.start(configuration: cfg)
        } catch {
            detachPublisher()
            post("GO LIVE failed: \(error.localizedDescription)")
        }
    }

    func stopStream() async {
        detachPublisher()
        await publisher.stop()
    }

    private func detachPublisher() {
        gate.close()
        compositor?.removeSink(publisher)
        audio.removeSink(publisher)
    }

    private func streamStateChanged(_ s: StreamState) {
        streamState = s
        if case .failed(let why) = s {
            detachPublisher()
            post("Stream stopped: \(why)")
        }
    }

    // MARK: Recording

    func startRecording() {
        guard let compositor else { return }
        do {
            try recorder.start(mode: recordingMode, size: project.output.resolution.size, fps: project.output.fps,
                               cameraRotated180: rotate180, audioChannels: audio.outputChannels)
            compositor.addSink(recorder)
            audio.addSink(recorder)
        } catch { post(error.localizedDescription) }
    }

    func stopRecording() async {
        compositor?.removeSink(recorder)
        audio.removeSink(recorder)
        if let url = await recorder.stop() { post("Saved \(url.lastPathComponent) (Files app → D-TEK Studio → Recordings)") }
    }

    // MARK: Thermal

    private func handleThermal(_ actions: [ThermalAction], level: ThermalLevel) {
        for a in actions {
            switch a {
            case .warn(let msg):
                banner = msg
            case .apply(let step):
                appliedThermalSteps.insert(step)
                switch step {
                case .reduceFrameRate:
                    Task { await applyMode(CaptureMode(resolution: project.output.resolution, fps: 30), reason: "Thermal: 60 → 30 fps") }
                case .reduceAIRate:
                    segmentation?.capFPS(15)
                    post("Thermal: AI cutout limited to 15 fps")
                case .aiToChroma:
                    if activeScene.keyMode == .aiCutout { editActive { $0.keyMode = .greenScreen } }
                    post("Thermal: AI cutout → GREEN SCREEN")
                }
            }
        }
        if level == .nominal { banner = nil }
    }

    /// Operator chooses to restore full quality once the device has cooled.
    func restoreThermalSteps() {
        appliedThermalSteps.removeAll()
        banner = nil
        configureSegmentation()
    }

    // MARK: Telemetry (2 Hz, main thread, cheap reads only)

    private func startTelemetry() {
        telemetryTimer?.invalidate()
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTelemetry() }
        }
    }

    private func refreshTelemetry() {
        var t = TelemetrySnapshot()
        t.streamState = streamState
        t.mode = currentMode.label
        if let c = compositor?.stats {
            t.programFPS = c.fps
            t.gpuMs = c.gpuMs
            t.droppedFrames = c.droppedFrames
        }
        t.frameBudgetMs = 1000 / Double(max(project.output.fps, 1))
        t.stream = publisher.stats
        t.audio = audio.levels
        t.thermal = ThermalLevel(ProcessInfo.processInfo.thermalState)
        let b = SystemMetrics.battery()
        t.batteryPercent = b.percent
        t.charging = b.charging
        t.memoryMB = SystemMetrics.memoryFootprintMB()
        t.ai = segmentation?.stats ?? SegmentationStats()
        t.aiActive = activeScene.keyMode == .aiCutout
        t.recording = recorder.status
        t.camera = camera.readout()
        telemetry = t
        cameraActive = camera.isRunning
        micActive = audio.isRunning && !project.audio.muted
    }

    func post(_ message: String) {
        events.insert(message, at: 0)
        if events.count > 30 { events.removeLast() }
        banner = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self.banner == message { self.banner = nil }
        }
    }

    // MARK: Audio

    func updateAudio(_ body: (inout AudioSettings) -> Void) {
        body(&project.audio)
        audio.apply(project.audio)
        scheduleAutosave()
    }

    // MARK: Projects

    private func composedProject() -> StudioProject {
        var p = project
        p.scenes = scenesEngine.scenes
        p.activeSceneID = scenesEngine.activeSceneID
        return p
    }

    func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.saveProject()
        }
    }

    func saveProject() {
        do { try projects.save(composedProject()) } catch { post("Save failed: \(error.localizedDescription)") }
    }

    func newProject(named name: String) { open((try? projects.create(name: name)) ?? StudioProject(name: name)) }

    func loadProject(_ id: UUID) {
        do { open(try projects.load(id: id)) } catch { post(error.localizedDescription) }
    }

    func duplicateProject() {
        saveProject()
        do { open(try projects.duplicate(id: project.id)) } catch { post(error.localizedDescription) }
    }

    func exportProject() -> URL? {
        guard let luts = lutLibrary else { return nil }
        saveProject()
        do { return try projects.export(composedProject(), luts: luts) } catch { post(error.localizedDescription); return nil }
    }

    func importProject(from url: URL) {
        guard let luts = lutLibrary else { return }
        do {
            let p = try projects.importArchive(from: url, luts: luts)
            lutItems = luts.sortedItems
            open(p)
        } catch { post(error.localizedDescription) }
    }

    private func open(_ p: StudioProject) {
        saveProject()
        project = p
        scenesEngine.replaceAll(p.scenes, activeID: p.activeSceneID)
        scenes = scenesEngine.scenes
        activeSceneID = scenesEngine.activeSceneID
        let pm = projects, id = p.id
        backgrounds?.purge()
        backgrounds?.assetURL = { pm.assetURL(projectID: id, name: $0) }
        graphics?.assetURL = { pm.assetURL(projectID: id, name: $0) }
        refreshSceneResources()
        audio.apply(p.audio)
        camera.apply(p.camera)
        Task { await applyMode(currentMode, reason: nil) }
        projectList = projects.list()
        post("Opened \(p.name)")
    }

    // MARK: Diagnostics

    func runSystemCheck() async {
        isCheckRunning = true
        checks = []
        let comp = compositor
        let deps = SystemCheck.Dependencies(context: metal,
                                            cameraRunning: { [camera] in camera.isRunning },
                                            programFPS: { comp?.stats.fps ?? 0 },
                                            audio: audio, lutLibrary: lutLibrary)
        await SystemCheck(deps).run { [weak self] r in
            Task { @MainActor in
                guard let self else { return }
                if let i = self.checks.firstIndex(where: { $0.id == r.id }) { self.checks[i] = r } else { self.checks.append(r) }
            }
        }
        isCheckRunning = false
    }
}
