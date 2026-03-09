import AppKit
import ServiceManagement
import SwiftUI

struct AppView: View {
    @ObservedObject var app: AppDelegate

    var body: some View {
        Group {
            backendStatusSection

            if let version = app.availableBackendUpdateVersionForMenu {
                Button(app.updateMenuVersionText(updateVersion: version)) {
                    app.applyDownloadedBackendUpdate(version: version)
                }
                .disabled(app.isApplyingBackendUpdate)
            }

            Button(Config.Menu.openBindings) {
                app.openBindings()
            }
            .disabled(!app.canOpenBindings)

            Toggle(Config.Menu.launchAtLogin, isOn: Binding(
                get: { app.enableLaunchAtLogin },
                set: { app.setLaunchAtLogin(enabled: $0) }
            ))

            Divider()

            Button(Config.Menu.quit) {
                app.quit()
            }
        }
        .onAppear {
            app.startIfNeeded()
            app.refreshBackendSetupUI()
        }
    }

    @ViewBuilder
    private var backendStatusSection: some View {
        switch app.backendSetupState {
        case .GettingReady:
            Text("Locating Backend...")
                .foregroundStyle(.secondary)

        case .WaitForDownloadPermission:
            Button("Download Backend") {
                app.downloadBackendNow()
            }
            .disabled(app.isBootstrappingBackend)

        case .DownloadInflight(_, let progress):
            Text("Downloading \(Int(progress * 100))%")
                .foregroundStyle(.secondary)

        case .Ready(let version):
            Text(version)
                .foregroundStyle(.secondary)

        case .Failed(let message):
            if app.isBackendStartFailure(message) {
                Text("Backend Failed")
                    .foregroundStyle(.secondary)
            } else {
                Button("Retry Download") {
                    app.downloadBackendNow()
                }
                .disabled(app.isBootstrappingBackend)
            }
        }
    }
}

extension AppDelegate {
    var shouldDimStatusBarIcon: Bool {
        if case .Ready = backendSetupState {
            return false
        }
        return true
    }

    var canOpenBindings: Bool {
        if case .Ready = backendSetupState {
            return true
        }
        return false
    }

    var availableBackendUpdateVersionForMenu: String? {
        guard case .Ready(let version) = backendSetupState else {
            return nil
        }
        return availableBackendUpdateVersion(
            currentVersion: version.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func setBackendSetupState(_ state: BackendSetupState) {
        backendSetupState = state
    }

    func refreshBackendSetupUI() {
        let enabled = isLaunchAtLoginEnabled
        if enableLaunchAtLogin != enabled {
            enableLaunchAtLogin = enabled
        }
    }

    func updateMenuVersionText(updateVersion: String) -> String {
        "Update Now \(compactMenuVersion(updateVersion))"
    }

    func compactMenuVersion(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let parsed = parseSemVer(trimmed) else {
            return trimmed
        }

        if parsed.patch == 0 {
            return "v\(parsed.major).\(parsed.minor)"
        }

        return "v\(parsed.major).\(parsed.minor).\(parsed.patch)"
    }

    func makeStatusBarIcon() -> NSImage {
        let icon = NSImage(size: Config.Icon.size)
        let bundles = [Bundle.main, Bundle.module]

        for name in Config.Icon.variants {
            for bundle in bundles {
                guard
                    let path = bundle.path(forResource: name, ofType: Config.Icon.fileType),
                    let image = NSImage(contentsOfFile: path),
                    let tiff = image.tiffRepresentation,
                    let rep = NSBitmapImageRep(data: tiff)
                else {
                    continue
                }

                rep.size = Config.Icon.size
                icon.addRepresentation(rep)
                icon.isTemplate = true
                return icon
            }
        }

        return makeFallbackIcon()
    }

    func makeFallbackIcon() -> NSImage {
        let image = NSImage(
            systemSymbolName: "shippingbox",
            accessibilityDescription: nil
        ) ?? NSImage(size: Config.Icon.size)

        image.size = Config.Icon.size
        image.isTemplate = true
        return image
    }

    func openBindings() {
        NSWorkspace.shared.open(Config.backendBaseURL)
    }

    func downloadBackendNow() {
        guard !isBootstrappingBackend else {
            return
        }

        setBackendSetupState(.DownloadInflight(phase: "Preparing", progress: 0.01))

        Task { @MainActor [weak self] in
            await self?.beginBootstrapBackendDownload(requiredMajor: nil)
        }
    }

    func isBackendStartFailure(_ message: String) -> Bool {
        let normalized = message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return normalized == "launch failed"
            || normalized == "start failed"
            || normalized.contains("failed to start")
    }

    func quit() {
        backendWatchdogTimer?.invalidate()
        updateTimer?.invalidate()
        stopRunningBackend()
        NSApp.terminate(nil)
    }

    var isLaunchAtLoginEnabled: Bool {
        guard #available(macOS 13.0, *) else {
            return false
        }
        return SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            refreshBackendSetupUI()
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log("failed to set launch at login: \(error)")
        }

        refreshBackendSetupUI()
    }
}
