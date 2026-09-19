//
//  CapturePanels.swift — CAM, COLOR, LUT, KEY, BG
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: CAM

struct CameraPanel: View {
    @Environment(StudioController.self) private var studio

    var body: some View {
        let caps = studio.capabilities
        let cam = studio.project.camera
        VStack(alignment: .leading, spacing: 10) {
            PanelSection(title: "FORMAT") {
                // Only modes this camera really supports are shown.
                let modes = caps.modes
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 4)], spacing: 4) {
                    ForEach(modes) { m in
                        Button { Task { await studio.applyMode(m, reason: nil) } } label: {
                            Text(m.label).font(Theme.label).frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(studio.currentMode == m ? Theme.text : Theme.panelRaised)
                                .foregroundStyle(studio.currentMode == m ? Color.black : Theme.text)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain)
                    }
                }
                Text(caps.deviceName).font(Theme.label).foregroundStyle(Theme.dim)
            }
            PanelSection(title: "LENS") {
                HStack(spacing: 4) {
                    ForEach(caps.lenses) { lens in
                        Button { studio.updateCamera { $0.zoom = Float(lens.zoomFactor / max(caps.displayZoomMultiplier, 0.01)) } } label: {
                            Text(lens.displayLabel).font(Theme.label).frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(Theme.panelRaised).clipShape(RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain)
                    }
                    Button { Task { await studio.switchCamera() } } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera").frame(maxWidth: .infinity).padding(.vertical, 5)
                            .background(Theme.panelRaised).clipShape(RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain)
                }
                ValueSlider(label: "ZOOM", value: studio.cameraBinding(\.zoom),
                            range: Float(caps.minZoom / max(caps.displayZoomMultiplier, 0.01))...Float(max(caps.maxZoom / max(caps.displayZoomMultiplier, 0.01), 1.01)),
                            neutral: 1, format: "%.1f×")
            }
            PanelSection(title: "EXPOSURE") {
                Pills(options: modes(lock: caps.supportsExposureLock, manual: caps.supportsManualExposure),
                      selection: studio.cameraBinding(\.exposureMode)) { $0.rawValue }
                if cam.exposureMode == .manual {
                    ValueSlider(label: "ISO", value: studio.cameraBinding(\.iso), range: caps.isoRange, neutral: caps.isoRange.lowerBound, format: "%.0f")
                    ValueSlider(label: "SHUTTER 1/x", value: studio.cameraBinding(\.shutterDenominator),
                                range: max(caps.shutterRange.lowerBound, Float(studio.project.output.fps))...min(caps.shutterRange.upperBound, 10000),
                                neutral: Float(studio.project.output.fps * 2), format: "1/%.0f")
                } else if cam.exposureMode == .auto {
                    ValueSlider(label: "EV BIAS", value: studio.cameraBinding(\.exposureBias), range: -3...3, format: "%+.1f")
                }
            }
            PanelSection(title: "FOCUS") {
                Pills(options: modes(lock: caps.supportsFocusLock, manual: caps.supportsManualFocus),
                      selection: studio.cameraBinding(\.focusMode)) { $0.rawValue }
                if cam.focusMode == .manual {
                    ValueSlider(label: "LENS POSITION", value: studio.cameraBinding(\.lensPosition), range: 0...1, neutral: 0.5)
                }
            }
            PanelSection(title: "WHITE BALANCE") {
                Pills(options: modes(lock: caps.supportsWhiteBalanceLock, manual: caps.supportsWhiteBalanceLock),
                      selection: studio.cameraBinding(\.whiteBalanceMode)) { $0.rawValue }
                if cam.whiteBalanceMode == .manual {
                    ValueSlider(label: "KELVIN", value: studio.cameraBinding(\.whiteBalanceKelvin), range: 2500...9000, neutral: 5600, format: "%.0f K")
                    ValueSlider(label: "TINT", value: studio.cameraBinding(\.whiteBalanceTint), range: -50...50, format: "%+.0f")
                }
            }
            if caps.hasTorch {
                PanelSection(title: "TORCH") {
                    ValueSlider(label: "LEVEL", value: studio.cameraBinding(\.torch), range: 0...1)
                }
            }
            let r = studio.telemetry.camera
            Text(String(format: "ISO %.0f · 1/%.0f · %.0f K · %.1f×", r.iso, r.shutterDenominator, r.whiteBalanceKelvin, r.zoomDisplay))
                .font(Theme.label).foregroundStyle(Theme.dim)
        }
    }

    private func modes(lock: Bool, manual: Bool) -> [ControlMode] {
        [ControlMode.auto] + (lock ? [.lock] : []) + (manual ? [.manual] : [])
    }
}

// MARK: COLOR

struct ColorPanel: View {
    @Environment(StudioController.self) private var studio
    @State private var advanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ToggleRow(label: "COLOR", isOn: studio.sceneBinding(\.color.enabled))
                Button("RESET") { studio.editActive { $0.color = .neutral } }.font(Theme.label).tint(Theme.dim)
            }
            PanelSection(title: "BASIC") {
                ValueSlider(label: "EXPOSURE", value: studio.sceneBinding(\.color.exposure), range: -3...3, format: "%+.2f EV")
                ValueSlider(label: "CONTRAST", value: studio.sceneBinding(\.color.contrast))
                ValueSlider(label: "HIGHLIGHTS", value: studio.sceneBinding(\.color.highlights))
                ValueSlider(label: "SHADOWS", value: studio.sceneBinding(\.color.shadows))
                ValueSlider(label: "WHITES", value: studio.sceneBinding(\.color.whites))
                ValueSlider(label: "BLACKS", value: studio.sceneBinding(\.color.blacks))
                ValueSlider(label: "SATURATION", value: studio.sceneBinding(\.color.saturation))
                ValueSlider(label: "VIBRANCE", value: studio.sceneBinding(\.color.vibrance))
                ValueSlider(label: "TEMPERATURE", value: studio.sceneBinding(\.color.temperature))
                ValueSlider(label: "TINT", value: studio.sceneBinding(\.color.tint))
            }
            DisclosureGroup(isExpanded: $advanced) {
                VStack(spacing: 8) {
                    ValueSlider(label: "LIFT", value: studio.sceneBinding(\.color.liftMaster), range: -0.3...0.3)
                    ValueSlider(label: "GAMMA", value: studio.sceneBinding(\.color.gammaMaster), range: 0.3...2.5, neutral: 1)
                    ValueSlider(label: "GAIN", value: studio.sceneBinding(\.color.gainMaster), range: 0...2, neutral: 1)
                    ValueSlider(label: "OFFSET", value: studio.sceneBinding(\.color.offsetMaster), range: -0.3...0.3)
                    rgb("LIFT", \.color.lift, -0.3...0.3, 0)
                    rgb("GAMMA", \.color.gamma, 0.3...2.5, 1)
                    rgb("GAIN", \.color.gain, 0...2, 1)
                    rgb("OFFSET", \.color.offset, -0.3...0.3, 0)
                    ValueSlider(label: "HUE", value: studio.sceneBinding(\.color.hue), range: -180...180, format: "%+.0f°")
                    ValueSlider(label: "MIDTONE DETAIL", value: studio.sceneBinding(\.color.midtoneDetail))
                }
                .padding(.top, 6)
            } label: {
                Text("ADVANCED").font(Theme.label).foregroundStyle(Theme.dim)
            }
            .tint(Theme.dim)
        }
    }

    private func rgb(_ name: String, _ kp: WritableKeyPath<SceneModel, RGBValue>, _ range: ClosedRange<Float>, _ n: Float) -> some View {
        VStack(spacing: 4) {
            ValueSlider(label: "\(name) R", value: studio.sceneBinding(kp.appending(path: \.r)), range: range, neutral: n)
            ValueSlider(label: "\(name) G", value: studio.sceneBinding(kp.appending(path: \.g)), range: range, neutral: n)
            ValueSlider(label: "\(name) B", value: studio.sceneBinding(kp.appending(path: \.b)), range: range, neutral: n)
        }
    }
}

// MARK: LUT

struct LUTPanel: View {
    @Environment(StudioController.self) private var studio
    @State private var importing = false

    var body: some View {
        let scene = studio.activeScene
        VStack(alignment: .leading, spacing: 10) {
            ToggleRow(label: "LUT", isOn: studio.sceneBinding(\.lut.enabled))
            ValueSlider(label: "INTENSITY", value: studio.sceneBinding(\.lut.intensity), range: 0...1, neutral: 1)
            Button { importing = true } label: {
                Label("IMPORT .CUBE", systemImage: "square.and.arrow.down").font(Theme.label)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Theme.panelRaised).clipShape(RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain)
            PanelSection(title: "LIBRARY") {
                ForEach(studio.lutItems) { item in
                    let selected = scene.lut.lutID == item.id
                    HStack {
                        Button { studio.toggleFavoriteLUT(item.id) } label: {
                            Image(systemName: item.favorite ? "star.fill" : "star").foregroundStyle(item.favorite ? Theme.warn : Theme.dim)
                        }.buttonStyle(.plain)
                        Button {
                            // Tap = live preview on program (it is the active scene).
                            studio.editActive { $0.lut.lutID = item.id; $0.lut.enabled = true }
                        } label: {
                            HStack {
                                Text(item.name).font(.system(size: 12, weight: selected ? .bold : .regular)).lineLimit(1)
                                Spacer()
                                Text("\(item.size)³").font(Theme.label).foregroundStyle(Theme.dim)
                            }
                        }.buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(selected ? Theme.panelRaised : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contextMenu {
                        if !item.isBuiltIn {
                            Button("Delete", role: .destructive) { studio.deleteLUT(item.id) }
                        }
                    }
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "cube") ?? .data]) { result in
            if case .success(let url) = result { studio.importLUT(from: url) }
        }
    }
}

// MARK: KEY

struct KeyPanel: View {
    @Environment(StudioController.self) private var studio

    var body: some View {
        let scene = studio.activeScene
        VStack(alignment: .leading, spacing: 10) {
            Pills(options: KeyMode.allCases, selection: studio.sceneBinding(\.keyMode)) { m in
                m == .greenScreen ? "CHROMA" : (m == .aiCutout ? "AI" : "OFF")
            }
            PanelSection(title: "MONITOR") {
                Pills(options: [Int32(DEKA_PREVIEW_PROGRAM), Int32(DEKA_PREVIEW_MATTE), Int32(DEKA_PREVIEW_ORIGINAL)],
                      selection: Binding(get: { studio.previewMode }, set: { studio.setPreviewMode($0) })) { m in
                    m == Int32(DEKA_PREVIEW_MATTE) ? "MATTE" : (m == Int32(DEKA_PREVIEW_ORIGINAL) ? "ORIGINAL" : "COMPOSITE")
                }
            }
            if scene.keyMode == .greenScreen {
                PanelSection(title: "KEY COLOR") {
                    Pills(options: KeyColorPreset.allCases, selection: studio.sceneBinding(\.chroma.preset)) { $0.rawValue.uppercased() }
                    if scene.chroma.preset == .custom {
                        ColorWellRow(label: "CUSTOM", color: studio.sceneBinding(\.chroma.customColor))
                    }
                }
                PanelSection(title: "MATTE") {
                    ValueSlider(label: "SIMILARITY", value: studio.sceneBinding(\.chroma.similarity), range: 0.01...0.5, neutral: 0.10, format: "%.3f")
                    ValueSlider(label: "SMOOTHNESS", value: studio.sceneBinding(\.chroma.smoothness), range: 0.001...0.3, neutral: 0.08, format: "%.3f")
                    ValueSlider(label: "SPILL", value: studio.sceneBinding(\.chroma.spill), range: 0...0.5, neutral: 0.10, format: "%.3f")
                    ValueSlider(label: "EDGE", value: studio.sceneBinding(\.chroma.edge), range: -1...1)
                    ValueSlider(label: "FEATHER", value: studio.sceneBinding(\.chroma.feather), range: 0...20, neutral: 2, format: "%.0f px")
                    ValueSlider(label: "OPACITY", value: studio.sceneBinding(\.chroma.opacity), range: 0...1, neutral: 1)
                }
            }
            if scene.keyMode == .aiCutout {
                PanelSection(title: "AI CUTOUT") {
                    Pills(options: SegmentationQuality.allCases, selection: studio.sceneBinding(\.segmentation.quality)) { $0.rawValue.uppercased() }
                    Pills(options: [10, 15, 30], selection: studio.sceneBinding(\.segmentation.targetFPS)) { "\($0) FPS" }
                    ToggleRow(label: "FALL BACK TO CHROMA IF SLOW", isOn: studio.sceneBinding(\.segmentation.fallbackToChroma))
                    ValueSlider(label: "EDGE", value: studio.sceneBinding(\.chroma.edge), range: -1...1)
                    ValueSlider(label: "FEATHER", value: studio.sceneBinding(\.chroma.feather), range: 0...20, neutral: 2, format: "%.0f px")
                    let ai = studio.telemetry.ai
                    Text("\(ai.backend)\n\(String(format: "%.0f fps · %.0f ms · target %d", ai.effectiveFPS, ai.inferenceMs, ai.targetFPS))")
                        .font(Theme.label).foregroundStyle(Theme.dim)
                    if let e = ai.lastError { Text(e).font(Theme.label).foregroundStyle(Theme.tally) }
                }
            }
        }
    }
}

// MARK: BG

struct BackgroundPanel: View {
    @Environment(StudioController.self) private var studio
    @State private var importing = false

    var body: some View {
        let bg = studio.activeScene.background
        VStack(alignment: .leading, spacing: 10) {
            Pills(options: BackgroundKind.allCases, selection: studio.sceneBinding(\.background.kind)) { $0.rawValue.uppercased() }
            if bg.kind == .solid || bg.kind == .gradient {
                ColorWellRow(label: "COLOR A", color: studio.sceneBinding(\.background.colorA))
                if bg.kind == .gradient {
                    ColorWellRow(label: "COLOR B", color: studio.sceneBinding(\.background.colorB))
                    ValueSlider(label: "ANGLE", value: studio.sceneBinding(\.background.gradientAngle), range: 0...360, neutral: 90, format: "%.0f°")
                }
            }
            if bg.kind == .image || bg.kind == .video {
                Button { importing = true } label: {
                    Label(bg.assetName == nil ? "CHOOSE FILE" : "REPLACE FILE", systemImage: "photo.on.rectangle").font(Theme.label)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(Theme.panelRaised).clipShape(RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain)
                ValueSlider(label: "SCALE", value: studio.sceneBinding(\.background.scale), range: 0.5...3, neutral: 1)
                ValueSlider(label: "POSITION X", value: studio.sceneBinding(\.background.positionX), range: -0.5...0.5)
                ValueSlider(label: "POSITION Y", value: studio.sceneBinding(\.background.positionY), range: -0.5...0.5)
                ValueSlider(label: "BLUR", value: studio.sceneBinding(\.background.blur), range: 0...120, format: "%.0f px")
            }
            ValueSlider(label: "OPACITY", value: studio.sceneBinding(\.background.opacity), range: 0...1, neutral: 1)
            ValueSlider(label: "BRIGHTNESS", value: studio.sceneBinding(\.background.brightness))
            ValueSlider(label: "CONTRAST", value: studio.sceneBinding(\.background.contrast))
            PanelSection(title: "SUBJECT") {
                ValueSlider(label: "SCALE", value: studio.sceneBinding(\.transform.scale), range: 0.3...2, neutral: 1)
                ValueSlider(label: "POSITION X", value: studio.sceneBinding(\.transform.positionX), range: -0.5...0.5)
                ValueSlider(label: "POSITION Y", value: studio.sceneBinding(\.transform.positionY), range: -0.5...0.5)
                ValueSlider(label: "SHADOW", value: studio.sceneBinding(\.background.shadowOpacity), range: 0...1)
                ValueSlider(label: "LIGHT WRAP", value: studio.sceneBinding(\.background.lightWrap), range: 0...1)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .movie]) { result in
            if case .success(let url) = result { studio.importBackground(from: url) }
        }
    }
}
