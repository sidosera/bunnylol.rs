import Foundation

struct ReleaseInfo {
    let version: String
    let archiveURL: URL
}

struct SemVer: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    var precedenceScore: Int {
        (major * 100) + (minor * 10) + patch
    }

    static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        lhs.precedenceScore < rhs.precedenceScore
    }
}

struct UpdateState {
    var lastCheckedAt: TimeInterval?
    var lastNotifiedBackendVersion: String?
}

struct UpdateCheckOutcome {
    let checkedAt: TimeInterval
    let backendLatestAvailable: String?
    let error: String?
}

enum BackendSetupState {
    case GettingReady
    case WaitForDownloadPermission(requiredMajor: String)
    case DownloadInflight(phase: String, progress: Double)
    case Ready(version: String)
    case Failed(message: String)
}
