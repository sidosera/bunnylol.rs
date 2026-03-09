import AppKit
import XDG

enum Config {
    static let bundleIdentifier = Config.plistString(
        keys: ["LolabunnyBundleIdentifier", "CFBundleIdentifier"]
    ) ?? ProcessInfo.processInfo.processName
    static let appName = "lolabunny"
    static let displayName = "Lolabunny"
    static let backendPort: UInt16 = Config.plistValue("LolabunnyBackendPort") ?? 18085
    static let backendBaseURL = URL(string: "http://localhost:\(backendPort)")!

    static func plistString(_ key: String) -> String? {
        plistString(keys: [key])
    }

    static func plistString(keys: [String]) -> String? {
        for key in keys {
            if let raw = Bundle.main.object(forInfoDictionaryKey: key),
                let value = normalizePlistStringValue(raw)
            {
                return value
            }
            if let value = developmentInfoDictionary[key] {
                return value
            }
        }
        return nil
    }

    private static func normalizePlistStringValue(_ raw: Any) -> String? {
        if let string = raw as? String {
            let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        if let number = raw as? NSNumber {
            let value = number.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private static let developmentInfoDictionary: [String: String] = {
        for path in developmentInfoPlistCandidatePaths() {
            if let raw = NSDictionary(contentsOfFile: path) as? [String: Any] {
                var parsed: [String: String] = [:]
                for (key, value) in raw {
                    if let normalized = normalizePlistStringValue(value) {
                        parsed[key] = normalized
                    }
                }
                if !parsed.isEmpty {
                    return parsed
                }
            }
        }
        return [:]
    }()

    private static func developmentInfoPlistCandidatePaths() -> [String] {
        var candidates: [String] = []
        let sourceURL = URL(fileURLWithPath: #filePath)
        let appDir = sourceURL
            .deletingLastPathComponent()   // Lolabunny
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // app
        candidates.append(appDir.appendingPathComponent("Info.plist").path)

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        candidates.append(cwd.appendingPathComponent("Info.plist").path)
        candidates.append(cwd.appendingPathComponent("app/Info.plist").path)

        var deduped: [String] = []
        var seen = Set<String>()
        for path in candidates {
            if seen.insert(path).inserted {
                deduped.append(path)
            }
        }
        return deduped
    }

    static func plistValue<T: LosslessStringConvertible>(_ key: String) -> T? {
        guard let raw = plistString(key) else {
            return nil
        }
        return T(raw)
    }

    static func plistBool(_ key: String) -> Bool? {
        guard let raw = plistString(key)?.lowercased() else {
            return nil
        }

        switch raw {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }

    enum Icon {
        static let size = NSSize(width: 18, height: 18)
        static let variants = ["bunny", "bunny@2x"]
        static let fileType = "png"
    }

    enum Log {
        static let path = NSHomeDirectory() + "/Library/Logs/\(Config.appName).log"
    }

    enum Backend {
        static let runtimeDir = NSTemporaryDirectory() + ".lolabunny"
        static let pidFile = runtimeDir + "/pid"
        static let launchArgsSignatureFile = runtimeDir + "/backend-args.sig"
        static let address = Config.plistString("LolabunnyBackendAddress") ?? "127.0.0.1"
        static let logLevel = Config.plistString("LolabunnyBackendLogLevel") ?? "normal"
        static let defaultSearch = Config.plistString("LolabunnyDefaultSearch") ?? "google"
        static let historyEnabled = Config.plistBool("LolabunnyHistoryEnabled") ?? true
        static let historyMaxEntries: Int = Config.plistValue("LolabunnyHistoryMaxEntries") ?? 1000
        static let updateReleasesURL: URL? = {
            guard let raw = Config.plistString(
                keys: ["LolabunnyUpdateReleasesURL", "LolabunnyUpdateArchiveBaseURL"]
            ) else {
                return nil
            }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }

            if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
                return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
                    .standardizedFileURL
            }

            guard
                let url = URL(string: trimmed),
                let scheme = url.scheme?.lowercased(),
                scheme == "http" || scheme == "https" || scheme == "file"
            else {
                return nil
            }
            return url.isFileURL ? url.standardizedFileURL : url
        }()
        static let updateReleaseTag = Config.plistString(
            keys: ["LolabunnyUpdateReleaseTag", "LolabunnyUpdateArchiveVersion"]
        )
        static let updateLocalStreamDelayMillis: UInt64 =
            Config.plistValue("LolabunnyUpdateLocalStreamDelayMs") ?? 0
        static let volumePath = Config.plistString("LolabunnyVolumePath")
        static let autoCheckInterval: TimeInterval = 24 * 60 * 60
        static let schedulerTickInterval: TimeInterval = 60 * 60
        static let watchdogIntervalSeconds: TimeInterval = {
            Config.plistValue("LolabunnyBackendWatchdogIntervalSeconds") ?? 20
        }()
        static let launchHealthTimeoutSeconds: TimeInterval = {
            Config.plistValue("LolabunnyBackendLaunchHealthTimeoutSeconds") ?? 10
        }()
        static let dataRoot: String = {
            if let dirs = try? BaseDirectories(prefixAll: ".lolabunny") {
                return dirs.dataHomePrefixed.string
            }
            return NSHomeDirectory() + "/.local/share/.lolabunny"
        }()
        static let configFile = dataRoot + "/config.toml"
        static let installRoot = dataRoot + "/backends"
        static let version: String = {
            guard let path = Bundle.main.path(forResource: ".version", ofType: nil),
                  let contents = try? String(contentsOfFile: path, encoding: .utf8)
            else {
                return "unknown"
            }
            return contents.trimmingCharacters(in: .whitespacesAndNewlines)
        }()
    }

    enum Menu {
        static let openBindings = "Open Bindings"
        static let launchAtLogin = "Launch at Login"
        static let quit = "Quit"
    }

    enum Notification {
        static let identifier = "lolabunny-notification"
        static let updatePromptCategory = "lolabunny-backend-update-prompt"
        static let bootstrapPromptCategory = "lolabunny-backend-bootstrap-prompt"
        static let applyUpdateAction = "lolabunny-backend-update-apply"
        static let deferUpdateAction = "lolabunny-backend-update-later"
        static let bootstrapDownloadAction = "lolabunny-backend-bootstrap-download"
        static let bootstrapLaterAction = "lolabunny-backend-bootstrap-later"
        static let backendVersionKey = "backend_version"
        static let backendRequiredMajorKey = "backend_required_major"
        static let updatesCheckFailedMessage = "Update check failed."
        static let noUpdatesMessage = "No updates available."
        static let backendUpdateApplyFailedMessage = "Could not apply downloaded backend update."
        static let backendBootstrapFailedMessage = "Could not download a compatible backend."

        static func backendUpdateReadyMessage(_ version: String) -> String {
            "Backend update \(version) downloaded. Update now?"
        }

        static func backendUpdatedMessage(_ version: String) -> String {
            "Backend updated to \(version)."
        }

        static func backendBootstrapPermissionMessage(requiredMajor: String) -> String {
            let major = requiredMajor.trimmingCharacters(in: .whitespacesAndNewlines)
            if major.isEmpty {
                return "Download compatible backend now?"
            }
            return "Download compatible backend major \(major) now?"
        }
    }
}
