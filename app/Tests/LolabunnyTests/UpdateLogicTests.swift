import Foundation
import Testing
@testable import Lolabunny

@MainActor
struct UpdateLogicTests {
    @Test func canonicalArchiveNameIncludesVersionAndExtension() {
        let app = AppDelegate()
        let archiveName = app.canonicalBackendArchiveName(version: "v2.4.6")
        #expect(archiveName.contains("v2.4.6"))
        #expect(archiveName.hasPrefix("\(Config.appName)-"))
        #expect(archiveName.hasSuffix(".tar.gz"))
    }

    @Test func updateSourceConfigIsAvailableInPackageRuntime() {
        let app = AppDelegate()
        #expect(app.isBackendUpdateSourceConfigured())
    }

    @Test func parseReleaseTagFromResolvedURLReadsVersionFromTagPath() {
        let app = AppDelegate()
        let url = URL(string: "https://example.com/releases/tag/v2.4.6")!
        #expect(app.parseReleaseTagFromResolvedURL(url) == "v2.4.6")
    }

    @Test func parseReleaseTagFromResolvedURLRejectsNonTagPath() {
        let app = AppDelegate()
        let latestURL = URL(string: "https://example.com/releases/latest")!
        #expect(app.parseReleaseTagFromResolvedURL(latestURL) == nil)
    }

    @Test func parseReleaseTagFromLatestPointerUnderstandsRedirectStyle() {
        let app = AppDelegate()
        let base = URL(fileURLWithPath: "/tmp/release-fixtures/releases", isDirectory: true)
        #expect(
            app.parseReleaseTagFromLatestPointer(
                "/releases/tag/v3.2.1",
                releasesBaseURL: base
            ) == "v3.2.1"
        )
        #expect(
            app.parseReleaseTagFromLatestPointer(
                "v3.2.1",
                releasesBaseURL: base
            ) == "v3.2.1"
        )
    }

    @Test func releaseArchiveURLUsesDownloadTagPathForLocalAndRemote() {
        let app = AppDelegate()
        let archiveName = "lolabunny-v3.2.1-darwin-arm64.tar.gz"
        let remoteBase = URL(string: "https://example.com/releases")!
        let localBase = URL(fileURLWithPath: "/tmp/release-fixtures/releases", isDirectory: true)

        let remote = app.releaseArchiveURL(
            releasesBaseURL: remoteBase,
            version: "v3.2.1",
            archiveName: archiveName
        )
        let local = app.releaseArchiveURL(
            releasesBaseURL: localBase,
            version: "v3.2.1",
            archiveName: archiveName
        )

        #expect(remote.absoluteString.hasSuffix("/releases/download/v3.2.1/\(archiveName)"))
        #expect(local.path.hasSuffix("/releases/download/v3.2.1/\(archiveName)"))
    }

    @Test func readLatestReleaseTagFromMockSourceReadsPointerFile() throws {
        let app = AppDelegate()
        let fm = FileManager.default
        let releasesDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("lolabunny-mock-releases-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: releasesDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: releasesDir) }

        let latestPointer = releasesDir.appendingPathComponent("latest")
        try "/releases/tag/v4.5.6\n".write(to: latestPointer, atomically: true, encoding: .utf8)

        #expect(app.readLatestReleaseTagFromMockSource(releasesURL: releasesDir) == "v4.5.6")
    }

    @Test func versionComparisonUnderstandsSemver() {
        let app = AppDelegate()

        #expect(app.compareVersions("v1.2.10", "v1.2.9") == .orderedDescending)
        #expect(app.compareVersions("v1.2.9", "v1.2.10") == .orderedAscending)
        #expect(app.compareVersions("v1.2.9", "1.2.9") == .orderedSame)
        #expect(app.compareVersions("v1.1-beta+1", "v1.0.1-beta+10") == .orderedDescending)
        #expect(app.compareVersions("v1.2", "v1.2.0-beta+99") == .orderedSame)
        #expect(app.parseSemVer("v1.7-beta+99") == SemVer(major: 1, minor: 7, patch: 0))
        #expect(app.parseSemVer("invalid") == nil)
    }

    @Test func latestCompatibleUpdateVersionOnlyReturnsNewerVersion() {
        let app = AppDelegate()
        let candidates = [" v1.2.1 \n", "v1.2.0", "v1.1.9"]

        #expect(
            app.latestCompatibleUpdateVersion(
                currentVersion: "v1.2.0",
                latestVersions: candidates
            ) == "v1.2.1"
        )
        #expect(
            app.latestCompatibleUpdateVersion(
                currentVersion: "v1.2.1",
                latestVersions: candidates
            ) == nil
        )
        #expect(
            app.latestCompatibleUpdateVersion(
                currentVersion: "v1.2.2",
                latestVersions: candidates
            ) == nil
        )
    }

    @Test func updateMenuVersionTextLooksReadable() {
        let app = AppDelegate()
        #expect(
            app.updateMenuVersionText(updateVersion: "v1.2.1") ==
                "Update Now v1.2.1"
        )
    }

    @Test func updateMenuVersionTextCompactsSuffixes() {
        let app = AppDelegate()
        #expect(
            app.updateMenuVersionText(updateVersion: "v1.1-beta+1") ==
                "Update Now v1.1"
        )
    }

    @Test func versionMatchAllowsUnknownRequiredMajor() {
        let app = AppDelegate()
        #expect(app.versionMatchesRequiredMajor("v0.5.2", requiredMajor: ""))
        #expect(app.versionMatchesRequiredMajor("v2.1.0", requiredMajor: " "))
        #expect(app.versionMatchesRequiredMajor("v0.5.2-beta+1", requiredMajor: "alpha"))
    }

    @Test func bootstrapPermissionMessageWithoutMajorIsReadable() {
        #expect(
            Config.Notification.backendBootstrapPermissionMessage(requiredMajor: "") ==
                "Download compatible backend now?"
        )
    }

    @Test func startupLaunchFailureIsClassifiedAsStartFailure() {
        let app = AppDelegate()
        #expect(app.isBackendStartFailure("launch failed"))
        #expect(app.isBackendStartFailure("start failed"))
        #expect(app.isBackendStartFailure("Backend failed to start"))
        #expect(!app.isBackendStartFailure("download failed"))
    }

    @Test func downloadBackendNowImmediatelyShowsProgressState() {
        let app = AppDelegate()
        app.backendSetupState = .WaitForDownloadPermission(requiredMajor: "1")

        app.downloadBackendNow()

        guard case .DownloadInflight(let phase, let progress) = app.backendSetupState else {
            Issue.record("Expected .downloading state immediately after clicking download.")
            return
        }
        #expect(phase == "Preparing")
        #expect(progress > 0.0)
    }

    @Test func parseExpectedSHA256ExtractsArchiveHash() {
        let archive = "lolabunny-v1.2.3-darwin-universal.tar.gz"
        let hash = String(repeating: "a", count: 64)
        let contents = "\(hash) *\(archive)\n"

        #expect(
            BackendArchiveUtils.parseExpectedSHA256(
                contents: contents,
                archiveName: archive
            ) == hash
        )
    }

    @Test func archiveEntryOutputURLRejectsTraversal() {
        let baseDir = URL(fileURLWithPath: "/tmp/lolabunny-tests", isDirectory: true)

        let safe = BackendArchiveUtils.archiveEntryOutputURL(
            baseDir: baseDir,
            entryName: "./bin/lolabunny"
        )
        #expect(safe?.path == baseDir.appendingPathComponent("bin/lolabunny").path)

        let blocked = BackendArchiveUtils.archiveEntryOutputURL(
            baseDir: baseDir,
            entryName: "../etc/passwd"
        )
        #expect(blocked == nil)
    }

    @Test func backendBinaryLayoutIsFlatByVersion() {
        let app = AppDelegate()
        let binary = app.backendBinary(for: "v1.2.3")
        let locked = app.lockedBackendBinary(for: "v1.2.3")

        #expect(binary.lastPathComponent == Config.appName)
        #expect(binary.deletingLastPathComponent().lastPathComponent == "v1.2.3")
        #expect(locked.deletingLastPathComponent().lastPathComponent == "v1.2.3.locked")
    }

    @Test func unlockedVersionNameParsesLockedEntries() {
        let app = AppDelegate()
        #expect(app.unlockedVersionName(fromLockedEntry: "v1.2.3.locked") == "v1.2.3")
        #expect(app.unlockedVersionName(fromLockedEntry: "v1.2.3") == nil)
        #expect(app.unlockedVersionName(fromLockedEntry: ".locked") == nil)
    }
}
