//
//  Theme.swift
//  Minimal, dark, broadcast-monitor look. One accent (tally red), one live green.
//

import SwiftUI

enum Theme {
    static let bg = Color(red: 0.035, green: 0.039, blue: 0.051)
    static let panel = Color(red: 0.075, green: 0.082, blue: 0.10)
    static let panelRaised = Color(red: 0.11, green: 0.12, blue: 0.145)
    static let line = Color.white.opacity(0.08)
    static let text = Color.white.opacity(0.92)
    static let dim = Color.white.opacity(0.5)
    static let tally = Color(red: 0.93, green: 0.26, blue: 0.21)
    static let live = Color(red: 0.18, green: 0.80, blue: 0.44)
    static let warn = Color(red: 0.98, green: 0.72, blue: 0.20)

    static let label = Font.system(size: 10, weight: .semibold).monospaced()
    static let value = Font.system(size: 12, weight: .medium).monospacedDigit()
    static let title = Font.system(size: 13, weight: .semibold)
}

/// Section header used in every panel.
struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.label).foregroundStyle(Theme.dim).tracking(1.2)
            content
        }
        .padding(.vertical, 6)
    }
}

/// Compact slider row: label · value · slider. Double-tap the label to reset.
struct ValueSlider: View {
    let label: String
    @Binding var value: Float
    var range: ClosedRange<Float> = -1...1
    var neutral: Float = 0
    var format: String = "%.2f"

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(label).font(Theme.label).foregroundStyle(Theme.dim)
                    .onTapGesture(count: 2) { value = neutral }
                Spacer()
                Text(String(format: format, value)).font(Theme.value)
                    .foregroundStyle(value == neutral ? Theme.dim : Theme.text)
            }
            Slider(value: $value, in: range).tint(Theme.tally).controlSize(.mini)
        }
    }
}

/// Segmented pill control that looks consistent in dark UI.
struct Pills<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let title: (T) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { o in
                Button { selection = o } label: {
                    Text(title(o)).font(Theme.label)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(selection == o ? Theme.text : Theme.panelRaised)
                        .foregroundStyle(selection == o ? Color.black : Theme.text)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct StatusBadge: View {
    let text: String
    let on: Bool
    var color: Color = Theme.live
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(on ? color : Theme.dim.opacity(0.4)).frame(width: 6, height: 6)
            Text(text).font(Theme.label).foregroundStyle(on ? Theme.text : Theme.dim)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.55)))
    }
}

struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) { Text(label).font(Theme.label).foregroundStyle(Theme.text) }
            .tint(Theme.tally).controlSize(.mini)
    }
}

struct ColorWellRow: View {
    let label: String
    @Binding var color: RGBAColor
    var body: some View {
        ColorPicker(selection: Binding(
            get: { Color(.sRGB, red: Double(color.r), green: Double(color.g), blue: Double(color.b), opacity: Double(color.a)) },
            set: { c in
                let ui = UIColor(c)
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                ui.getRed(&r, green: &g, blue: &b, alpha: &a)
                color = RGBAColor(r: Float(r), g: Float(g), b: Float(b), a: Float(a))
            })) {
            Text(label).font(Theme.label).foregroundStyle(Theme.text)
        }
    }
}
