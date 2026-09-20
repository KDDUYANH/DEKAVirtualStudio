//
//  ContentView.swift
//  Landscape operator layout:
//
//  ┌──────────────────────────────────────────┬──────┬──────────────┐
//  │ DEKA VIRTUAL STUDIO  CAM● MIC● STREAM OFF│ rail │  panel       │
//  │                PROGRAM                   │ CAM  │              │
//  │ [SCENE 1][SCENE 2][SCENE 3][SCENE 4]  REC│ COLOR│              │
//  │ 1080p60 · 5.8 Mbps · RTT 38 · L/R · GPU  │ …    │  [GO LIVE]   │
//  └──────────────────────────────────────────┴──────┴──────────────┘
//

import SwiftUI
import HaishinKit

struct SRTReturnMonitorView: UIViewRepresentable {
    let view: MTHKView
    func makeUIView(context: Context) -> MTHKView { view }
    func updateUIView(_ uiView: MTHKView, context: Context) {}
}

enum PanelTab: String, CaseIterable, Identifiable {
    case camera = "CAM", color = "COLOR", lut = "LUT", key = "KEY", background = "BG",
         graphics = "GFX", audio = "AUDIO", output = "OUT", system = "SYS"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .camera: return "camera.aperture"
        case .color: return "circle.lefthalf.filled"
        case .lut: return "cube"
        case .key: return "person.crop.rectangle"
        case .background: return "photo"
        case .graphics: return "textformat"
        case .audio: return "waveform"
        case .output: return "antenna.radiowaves.left.and.right"
        case .system: return "checklist"
        }
    }
}

struct ContentView: View {
    @Environment(StudioController.self) private var studio
    @State private var tab: PanelTab = .color

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    ProgramView(renderer: studio.compositor?.renderer)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                    if studio.project.output.srtReturnEnabled {
                        SRTReturnMonitorView(view: studio.srtReturnView)
                            .frame(width: 160, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Theme.panelRaised, lineWidth: 1.5)
                            )
                            .overlay(alignment: .topLeading) {
                                Text("RETURN (PiP)")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.7))
                                    .foregroundStyle(Theme.text)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .padding(4)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                    StatusBar()
                    if let banner = studio.banner {
                        Text(banner).font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.75)))
                            .foregroundStyle(Theme.text)
                            .padding(.top, 34)
                            .transition(.opacity)
                    }
                    if let err = studio.setupError {
                        Text(err).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.tally)
                            .padding().background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.8)))
                            .frame(maxHeight: .infinity)
                    }
                }
                SceneBar()
                TelemetryStrip()
            }
            .background(Theme.bg)

            TabRail(tab: $tab)

            VStack(spacing: 0) {
                ScrollView {
                    Group {
                        switch tab {
                        case .camera: CameraPanel()
                        case .color: ColorPanel()
                        case .lut: LUTPanel()
                        case .key: KeyPanel()
                        case .background: BackgroundPanel()
                        case .graphics: GraphicsPanel()
                        case .audio: AudioPanel()
                        case .output: OutputPanel()
                        case .system: SystemPanel()
                        }
                    }
                    .padding(12)
                }
                LiveButton().padding(10)
            }
            .frame(width: 270)
            .background(Theme.panel)
        }
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.2), value: studio.banner)
    }
}

struct TabRail: View {
    @Binding var tab: PanelTab
    var body: some View {
        VStack(spacing: 2) {
            ForEach(PanelTab.allCases) { t in
                Button { tab = t } label: {
                    VStack(spacing: 2) {
                        Image(systemName: t.icon).font(.system(size: 14, weight: .medium))
                        Text(t.rawValue).font(.system(size: 8, weight: .bold))
                    }
                    .frame(width: 46, height: 38)
                    .foregroundStyle(tab == t ? Theme.text : Theme.dim)
                    .background(tab == t ? Theme.panelRaised : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(width: 52)
        .background(Theme.bg)
    }
}

struct StatusBar: View {
    @Environment(StudioController.self) private var studio
    var body: some View {
        HStack(spacing: 6) {
            Text("D-TEK STUDIO").font(.system(size: 11, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.text)
            Spacer()
            StatusBadge(text: "CAMERA ACTIVE", on: studio.cameraActive)
            StatusBadge(text: studio.micActive ? "MIC ACTIVE" : "MIC OFF", on: studio.micActive)
            StatusBadge(text: studio.streamState.label, on: studio.streamState.isOnAir,
                        color: studio.streamState == .live ? Theme.tally : Theme.warn)
        }
        .padding(.horizontal, 10).padding(.top, 6)
    }
}

func timeString(_ t: TimeInterval) -> String {
    let s = Int(t); return String(format: "%02ld:%02ld:%02ld", s / 3600, (s % 3600) / 60, s % 60)
}

struct SceneBar: View {
    @Environment(StudioController.self) private var studio
    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(studio.scenes.enumerated()), id: \.element.id) { i, scene in
                        let active = scene.id == studio.activeSceneID
                        Button { studio.take(scene.id) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(String(format: "SCENE %02ld", i + 1)).font(.system(size: 8, weight: .bold)).foregroundStyle(active ? .black.opacity(0.6) : Theme.dim)
                                Text(scene.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .frame(minWidth: 86, alignment: .leading)
                            .background(active ? Theme.tally : Theme.panelRaised)
                            .foregroundStyle(active ? Color.white : Theme.text)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }

                    // (+) Add extra scene on demand
                    Button {
                        studio.addScene()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text("ADD")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Theme.panelRaised)
                        .foregroundStyle(Theme.dim)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            Pills(options: TransitionKind.allCases, selection: studio.outputBinding(\.transition)) { $0.rawValue.uppercased() }
                .frame(width: 96)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }
}

struct LiveButton: View {
    @Environment(StudioController.self) private var studio
    @State private var confirmStop = false
    var body: some View {
        let onAir = studio.streamState.isOnAir
        let busy = studio.streamState == .authorizing || studio.streamState == .connecting
        Button {
            if onAir { confirmStop = true } else if !busy { Task { await studio.goLive() } }
        } label: {
            Text(onAir ? "● LIVE — STOP" : (busy ? studio.streamState.label : "GO LIVE"))
                .font(.system(size: 14, weight: .heavy)).tracking(1)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(onAir ? Theme.tally : (busy ? Theme.warn : Theme.text))
                .foregroundStyle(onAir ? Color.white : Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .confirmationDialog("Stop the live stream?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop stream", role: .destructive) { Task { await studio.stopStream() } }
        }
    }
}

struct TelemetryStrip: View {
    @Environment(StudioController.self) private var studio
    var body: some View {
        let t = studio.telemetry
        HStack(spacing: 14) {
            metric("FORMAT", t.mode)
            metric("FPS", String(format: "%.0f", t.programFPS), bad: t.programFPS > 0 && t.programFPS < Double(studio.project.output.fps) * 0.9)
            if t.streamState.isOnAir {
                metric("STREAM", String(format: "● %.1f Mbps", t.stream.videoBitrateKbps / 1000))
                metric("RTT", String(format: "%.0f ms", t.stream.rttMs), bad: t.stream.rttMs > 200)
                metric("LOSS", String(format: "%.1f%%", t.stream.packetLossPercent), bad: t.stream.packetLossPercent > 2)
            } else {
                metric("STREAM", "STANDBY")
            }
            AudioMeter(levels: t.audio).frame(width: 85)
            metric("THERMAL", t.thermal.label, bad: t.thermal >= .serious)
            metric("BATT", t.batteryPercent.map { "\($0)%\(t.charging ? "+" : "")" } ?? "—")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.black)
    }

    private func metric(_ k: String, _ v: String, bad: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.dim)
            Text(v).font(Theme.value).foregroundStyle(bad ? Theme.warn : Theme.text).lineLimit(1)
        }
    }
}

/// L/R peak meter, −60…0 dBFS, red above −3 dBFS.
struct AudioMeter: View {
    let levels: AudioLevels
    var body: some View {
        VStack(spacing: 3) {
            bar("L", levels.peakDB[safe: 0] ?? -120)
            bar("R", levels.peakDB[safe: 1] ?? -120)
        }
    }
    private func bar(_ ch: String, _ db: Float) -> some View {
        HStack(spacing: 4) {
            Text(ch).font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.dim)
            GeometryReader { g in
                let f = CGFloat(max(0, min(1, (db + 60) / 60)))
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.panelRaised)
                    Capsule().fill(db > -3 ? Theme.tally : (db > -12 ? Theme.warn : Theme.live)).frame(width: g.size.width * f)
                }
            }
            .frame(height: 5)
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
