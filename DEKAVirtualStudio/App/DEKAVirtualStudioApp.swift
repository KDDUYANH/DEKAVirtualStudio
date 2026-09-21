//
//  DEKAVirtualStudioApp.swift
//  D-TEK Virtual Studio — iPhone virtual production camera.
//

import SwiftUI
import Combine

@main
struct DEKAVirtualStudioApp: App {
    @State private var studio = StudioController()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(studio)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
                .task { await studio.start() }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    studio.handleMemoryWarning()
                }
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }   // a camera must not auto-lock
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .background { studio.saveProject() }
        }
    }
}
