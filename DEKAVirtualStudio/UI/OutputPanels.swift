//
//  OutputPanels.swift — GFX, AUDIO, OUT, SYS
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: GFX

struct GraphicsPanel: View {
    @Environment(StudioController.self) private var studio
    @State private var importingLogo = false
    @State private var countdownMinutes = 5

    var body: some View {
        let g = studio.activeScene.graphics
        VStack(alignment: .leading, spacing: 10) {
            PanelSection(title: "LOGO") {
                HStack {
                    ToggleRow(label: "SHOW", isOn: studio.sceneBinding(\.graphics.logoEnabled))
                    Button(g.logoAsset == nil ? "CHOOSE" : "REPLACE") { importingLogo = true }.font(Theme.label)
                }
                Pills(options: CornerPosition.allCases, selection: studio.sceneBinding(\.graphics.logoPosition)) { p in
                    switch p { case .topLeft: return "TL"; case .topRight: return "TR"; case .bottomLeft: return "BL"; case .bottomRight: return "BR" }
                }
                ValueSlider(label: "SIZE", value: studio.sceneBinding(\.graphics.logoScale), range: 0.04...0.4, neutral: 0.12)
                ValueSlider(label: "OPACITY", value: studio.sceneBinding(\.graphics.logoOpacity), range: 0...1, neutral: 1)
            }
            PanelSection(title: "LOWER THIRD") {
                ToggleRow(label: "SHOW", isOn: studio.sceneBinding(\.graphics.lowerThird.enabled))
                TextField("Title", text: studio.sceneBinding(\.graphics.lowerThird.title)).textFieldStyle(.roundedBorder)
                TextField("Subtitle", text: studio.sceneBinding(\.graphics.lowerThird.subtitle)).textFieldStyle(.roundedBorder)
                ColorWellRow(label: "ACCENT", color: studio.sceneBinding(\.graphics.lowerThird.accent))
            }
            PanelSection(title: "TEXT") {
                ToggleRow(label: "SHOW", isOn: studio.sceneBinding(\.graphics.textEnabled))
                TextField("Headline", text: studio.sceneBinding(\.graphics.text)).textFieldStyle(.roundedBorder)
                ValueSlider(label: "SIZE", value: studio.sceneBinding(\.graphics.textSize), range: 24...160, neutral: 64, format: "%.0f")
            }
            PanelSection(title: "TICKER") {
                ToggleRow(label: "SHOW", isOn: studio.sceneBinding(\.graphics.ticker.enabled))
                TextField("Ticker text", text: studio.sceneBinding(\.graphics.ticker.text)).textFieldStyle(.roundedBorder)
                ValueSlider(label: "SPEED", value: studio.sceneBinding(\.graphics.ticker.speed), range: 0.02...0.3, neutral: 0.08)
            }
            PanelSection(title: "TIME") {
                ToggleRow(label: "CLOCK", isOn: studio.sceneBinding(\.graphics.clockEnabled))
                ToggleRow(label: "COUNTDOWN", isOn: studio.sceneBinding(\.graphics.countdownEnabled))
                HStack {
                    Stepper("\(countdownMinutes) min", value: $countdownMinutes, in: 1...180).font(Theme.label)
                    Button("START") {
                        let target = Date().addingTimeInterval(TimeInterval(countdownMinutes * 60))
                        studio.editActive { $0.graphics.countdownTarget = target; $0.graphics.countdownEnabled = true }
                    }.font(Theme.label)
                }
            }
            PanelSection(title: "WATERMARK") {
                TextField("Watermark", text: studio.sceneBinding(\.graphics.watermarkText)).textFieldStyle(.roundedBorder)
            }
        }
        .fileImporter(isPresented: $importingLogo, allowedContentTypes: [.png, .jpeg, .heic]) { result in
            if case .success(let url) = result { studio.importLogo(from: url) }
        }
    }
}

// MARK: AUDIO

struct AudioPanel: View {
    @Environment(StudioController.self) private var studio

    var body: some View {
        let t = studio.telemetry.audio
        VStack(alignment: .leading, spacing: 10) {
            PanelSection(title: "INPUT") {
                ForEach(studio.audio.availableInputs) { input in
                    Button {
                        try? studio.audio.selectInput(uid: input.id)
                        studio.updateAudio { $0.preferredInputUID = input.id }
                    } label: {
                        HStack {
                            Text(input.name).font(.system(size: 12)).lineLimit(1)
                            Spacer()
                            Text(input.kind.uppercased()).font(Theme.label).foregroundStyle(Theme.dim)
                        }
                        .padding(8)
                        .background(studio.audio.currentInputName == input.name ? Theme.panelRaised : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain)
                }
            }
            PanelSection(title: "LEVEL") {
                AudioMeter(levels: t)
                HStack {
                    Text(String(format: "PEAK %.0f / %.0f dBFS", t.peakDB[0], t.peakDB[1])).font(Theme.label)
                    Spacer()
                    Text(String(format: "GR %.1f dB", t.gainReductionDB)).font(Theme.label).foregroundStyle(Theme.dim)
                }
                if t.clipCount > 0 { Text("CLIPPED \(t.clipCount)×").font(Theme.label).foregroundStyle(Theme.tally) }
                ToggleRow(label: "MUTE", isOn: studio.audioBinding(\.muted))
                ValueSlider(label: "GAIN", value: studio.audioBinding(\.gainDB), range: -24...24, format: "%+.0f dB")
            }
            PanelSection(title: "DYNAMICS") {
                ToggleRow(label: "COMPRESSOR", isOn: studio.audioBinding(\.compressorEnabled))
                ValueSlider(label: "THRESHOLD", value: studio.audioBinding(\.compressorThresholdDB), range: -40...0, neutral: -18, format: "%.0f dB")
                ValueSlider(label: "RATIO", value: studio.audioBinding(\.compressorRatio), range: 1...10, neutral: 3, format: "%.1f:1")
                ToggleRow(label: "LIMITER", isOn: studio.audioBinding(\.limiterEnabled))
                ValueSlider(label: "CEILING", value: studio.audioBinding(\.limiterCeilingDB), range: -6...0, neutral: -1, format: "%.1f dBFS")
            }
        }
    }
}

// MARK: OUT

struct OutputPanel: View {
    @Environment(StudioController.self) private var studio

    var body: some View {
        let s = studio.telemetry.stream
        VStack(alignment: .leading, spacing: 10) {
            PanelSection(title: "QUALITY") {
                Pills(options: [QualityPresetID.mobile, .broadcast, .lowBandwidth],
                      selection: Binding(get: { studio.project.output.preset },
                                         set: { id in Task { await studio.applyPreset(id) } })) { $0.label }
                Text("\(studio.currentMode.label) · \(studio.project.output.videoBitrateKbps) kbps · \(studio.project.output.videoCodec.uppercased())")
                    .font(Theme.label).foregroundStyle(Theme.dim)
                ValueSlider(label: "MAX VIDEO kbps",
                            value: Binding(get: { Float(studio.project.output.videoBitrateKbps) },
                                           set: { v in studio.outputBinding(\.videoBitrateKbps).wrappedValue = Int(v) }),
                            range: 1000...12000, neutral: 4000, format: "%.0f")
            }

            PanelSection(title: "LIVE DESTINATION") {
                Pills(options: StreamDestination.allCases, selection: studio.outputBinding(\.destination)) { $0.rawValue }
            }

            if studio.project.output.destination == .srtServer {
                PanelSection(title: "SRT SERVER SETTINGS") {
                    HStack(spacing: 6) {
                        TextField("Host / IP", text: studio.outputBinding(\.srtHost))
                            .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Port", value: studio.outputBinding(\.srtPort), format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 65)
                    }
                    TextField("Publish Stream ID (e.g. publish:cam1)", text: studio.outputBinding(\.srtStreamId))
                        .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                    ValueSlider(label: "LATENCY",
                                value: Binding(get: { Float(studio.project.output.srtLatencyMs) },
                                               set: { v in studio.outputBinding(\.srtLatencyMs).wrappedValue = Int(v) }),
                                range: 50...1000, neutral: 200, format: "%.0f ms")
                    SecureField("Passphrase (optional)", text: studio.outputBinding(\.srtPassphrase))
                        .textFieldStyle(.roundedBorder)
                    Text(studio.project.output.srtPublishURLString)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(2)
                }
            } else {
                PanelSection(title: "DOLBY OPTIVIEW (MILLICAST)") {
                    HStack(spacing: 6) {
                        TextField("Dolby Ingest", text: studio.outputBinding(\.dolbyEndpoint))
                            .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Port", value: studio.outputBinding(\.dolbyPort), format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 65)
                    }
                    TextField("Dolby Stream Name", text: studio.outputBinding(\.dolbyStreamName))
                        .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Dolby Publishing Token", text: studio.outputBinding(\.dolbyPublishingToken))
                        .textFieldStyle(.roundedBorder)
                    ValueSlider(label: "LATENCY",
                                value: Binding(get: { Float(studio.project.output.srtLatencyMs) },
                                               set: { v in studio.outputBinding(\.srtLatencyMs).wrappedValue = Int(v) }),
                                range: 50...1000, neutral: 200, format: "%.0f ms")
                    Text(studio.project.output.srtPublishURLString)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(2)
                }
            }

            PanelSection(title: "BROADCAST CLEAN FEED") {
                ToggleRow(label: "CLEAN PROGRAM FEED (NO GFX ON STREAM)", isOn: studio.outputBinding(\.cleanFeedLiveOutput))
                Text("When enabled, the stream sends only talent + background. Check matte and UI overlays are never broadcast.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(Theme.dim)
            }

            PanelSection(title: "SRT INPUT (RETURN FEED / PiP)") {
                Toggle("RETURN MONITOR (PiP)", isOn: studio.outputBinding(\.srtReturnEnabled))
                    .font(Theme.label)
                if studio.project.output.srtReturnEnabled {
                    TextField("Return Stream ID (e.g. read:program)", text: studio.outputBinding(\.srtReturnStreamId))
                        .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text(studio.project.output.srtReturnURLString)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(2)
                }
            }

            PanelSection(title: "TRANSITION") {
                Pills(options: TransitionKind.allCases, selection: studio.outputBinding(\.transition)) { $0.rawValue.uppercased() }
                ValueSlider(label: "FADE",
                            value: Binding(get: { Float(studio.project.output.transitionDuration) },
                                           set: { v in studio.outputBinding(\.transitionDuration).wrappedValue = Double(v) }),
                            range: 0.1...2, neutral: 0.5, format: "%.1f s")
            }

            if studio.streamState.isOnAir {
                PanelSection(title: "SRT TELEMETRY") {
                    Group {
                        Text(String(format: "%.2f Mbps send · %.0f ms RTT", s.videoBitrateKbps / 1000, s.rttMs))
                        Text(String(format: "loss: %.2f%% · bandwidth: %.2f Mbps", s.packetLossPercent, s.availableOutgoingKbps / 1000))
                        Text("status: \(s.connectionState) · latency: \(studio.project.output.srtLatencyMs) ms")
                    }
                    .font(Theme.label).foregroundStyle(Theme.dim)
                }
            }
        }
    }
}

// MARK: SYS

struct SystemPanel: View {
    @Environment(StudioController.self) private var studio
    @State private var importing = false
    @State private var exportURL: URL?
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelSection(title: "SYSTEM CHECK") {
                Button(studio.isCheckRunning ? "RUNNING…" : "RUN SYSTEM CHECK") { Task { await studio.runSystemCheck() } }
                    .font(Theme.label).disabled(studio.isCheckRunning)
                ForEach(studio.checks) { c in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text(c.id.uppercased()).font(Theme.label)
                            Spacer()
                            Text(c.status.rawValue).font(Theme.label).foregroundStyle(color(c.status))
                        }
                        if !c.detail.isEmpty { Text(c.detail).font(.system(size: 9)).foregroundStyle(Theme.dim) }
                    }
                }
            }
            PanelSection(title: "PROJECT · \(studio.project.name.uppercased())") {
                HStack {
                    Button("SAVE") { studio.saveProject(); studio.post("Saved") }
                    Button("DUPLICATE") { studio.duplicateProject() }
                    Button("EXPORT") { exportURL = studio.exportProject() }
                    Button("IMPORT") { importing = true }
                }.font(Theme.label)
                if let exportURL {
                    ShareLink(item: exportURL) { Label("SHARE \(exportURL.lastPathComponent)", systemImage: "square.and.arrow.up").font(Theme.label) }
                }
                HStack {
                    TextField("New project", text: $newName).textFieldStyle(.roundedBorder)
                    Button("NEW") { studio.newProject(named: newName.isEmpty ? "Studio" : newName); newName = "" }.font(Theme.label)
                }
                ForEach(studio.projectList) { p in
                    Button { studio.loadProject(p.id) } label: {
                        HStack {
                            Text(p.name).font(.system(size: 12, weight: p.id == studio.project.id ? .bold : .regular))
                            Spacer()
                            Text(p.modifiedAt, style: .date).font(Theme.label).foregroundStyle(Theme.dim)
                        }
                    }.buttonStyle(.plain)
                }
                HStack {
                    Button("ADD SCENE") { studio.addScene() }
                    Spacer()
                    if studio.scenes.count > 1 {
                        Button("DELETE ACTIVE SCENE", role: .destructive) { studio.deleteScene(studio.activeSceneID) }
                    }
                }.font(Theme.label)
                TextField("Scene name", text: Binding(get: { studio.activeScene.name },
                                                      set: { studio.renameScene(studio.activeSceneID, $0) }))
                    .textFieldStyle(.roundedBorder)
            }
            PanelSection(title: "THERMAL") {
                Text("Protection order: " + ThermalPolicy().order.map(ThermalPolicy.describe).joined(separator: " → "))
                    .font(.system(size: 9)).foregroundStyle(Theme.dim)
                if !studio.appliedThermalSteps.isEmpty {
                    Button("RESTORE FULL QUALITY") { studio.restoreThermalSteps() }.font(Theme.label)
                }
            }
            PanelSection(title: "EVENTS") {
                ForEach(Array(studio.events.prefix(12).enumerated()), id: \.offset) { _, e in
                    Text(e).font(.system(size: 9)).foregroundStyle(Theme.dim)
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { studio.importProject(from: url) }
        }
    }

    private func color(_ s: CheckStatus) -> Color {
        switch s {
        case .pass: return Theme.live
        case .warn: return Theme.warn
        case .fail: return Theme.tally
        default: return Theme.dim
        }
    }
}
