import AppKit
import SwiftUI

struct LolabunnyApp: App {
    @StateObject private var app: AppDelegate

    init() {
        let model = AppDelegate()
        _app = StateObject(wrappedValue: model)

        if let bundleID = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
            !bundleID.isEmpty
        {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if running.count > 1 {
                log("another instance already running, exiting")
                exit(0)
            }
        } else {
            log("skipping single-instance check – missing bundle identifier (debug build?)")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            AppView(app: app)
        } label: {
            Image(nsImage: app.statusBarIcon)
                .opacity(app.shouldDimStatusBarIcon ? 0.5 : 1.0)
                .onAppear {
                    app.startIfNeeded()
                }
        }
        .menuBarExtraStyle(.menu)
    }
}

LolabunnyApp.main()
