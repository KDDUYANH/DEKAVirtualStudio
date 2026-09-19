//
//  ProgramView.swift
//  Hosts the Metal monitor. SwiftUI never sees frames — it only hosts the CAMetalLayer.
//

import SwiftUI

struct ProgramView: UIViewRepresentable {
    let renderer: MetalRenderer?

    func makeUIView(context: Context) -> PreviewMetalView {
        let v = PreviewMetalView()
        renderer?.attach(v)
        return v
    }

    func updateUIView(_ uiView: PreviewMetalView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewMetalView, coordinator: ()) {}
}
