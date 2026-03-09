import Foundation

extension AppDelegate {
    nonisolated func isBackendUpdateSourceConfigured() -> Bool {
        Config.Backend.updateReleasesURL != nil
    }

    nonisolated func configuredPinnedUpdateVersion() -> String? {
        if let explicit = Config.Backend.updateReleaseTag {
            let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed.caseInsensitiveCompare("latest") != .orderedSame {
                return trimmed
            }
        }
        return nil
    }

    func canonicalBackendArchiveName(version: String) -> String {
        let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let detectedArch = architectureAliases().first ?? architectureLabel().lowercased()
        let arch = detectedArch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(Config.appName)-\(trimmedVersion)-darwin-\(arch).tar.gz"
    }

    func latestCompatibleUpdateVersion(currentVersion: String, latestVersions: [String]) -> String? {
        let current = currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = latestVersions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { compareVersions($0, $1) == .orderedDescending }

        guard !current.isEmpty else {
            return candidates.first
        }

        for candidate in candidates {
            if compareVersions(candidate, current) == .orderedDescending {
                return candidate
            }
        }
        return nil
    }

    func availableBackendUpdateVersion(currentVersion: String) -> String? {
        let requiredMajor = requiredBackendMajor()
        var candidates = Set(
            installedCompatibleVersions(requiredMajor: requiredMajor)
                + downloadedCompatibleVersions(requiredMajor: requiredMajor)
        )
        if let notified = updateState.lastNotifiedBackendVersion {
            candidates.insert(notified)
        }
        return latestCompatibleUpdateVersion(
            currentVersion: currentVersion,
            latestVersions: Array(candidates)
        )
    }

    func shouldRunUpdateCheck(force: Bool, now: Date = Date()) -> Bool {
        if force {
            return true
        }
        if shouldSkipAutomaticUpdateChecks() {
            return false
        }
        guard let last = updateState.lastCheckedAt else {
            return true
        }
        return (now.timeIntervalSince1970 - last) >= Config.Backend.autoCheckInterval
    }

    func scheduleUpdateChecks() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(
            withTimeInterval: Config.Backend.schedulerTickInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.runUpdateCheck(force: false, notify: false)
            }
        }
    }

    func runUpdateCheck(force: Bool, notify: Bool) {
        guard isBackendUpdateSourceConfigured() else {
            return
        }
        guard !isApplyingBackendUpdate else {
            return
        }
        guard shouldRunUpdateCheck(force: force) else {
            return
        }
        guard !isCheckingUpdates else {
            return
        }
        isCheckingUpdates = true

        let previousBackendNotified = updateState.lastNotifiedBackendVersion

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let outcome = await self.performUpdateCheck()
            self.applyUpdateCheckOutcome(
                outcome,
                notify: notify,
                previousBackendNotified: previousBackendNotified
            )
        }
    }

    func performUpdateCheck() async -> UpdateCheckOutcome {
        let now = Date().timeIntervalSince1970
        let requiredMajor = requiredBackendMajor()

        var backendCurrent = currentCompatibleBackendVersion()
        if let configured = configuredBackendVersion(),
            versionMatchesRequiredMajor(configured, requiredMajor: requiredMajor)
        {
            backendCurrent = configured
        } else if let running = await probeRunningBackendAsync() {
            backendCurrent = running
        }

        guard let latestRelease = await fetchLatestRelease() else {
            return UpdateCheckOutcome(
                checkedAt: now,
                backendLatestAvailable: nil,
                error: "failed to check latest release"
            )
        }

        let latest = latestRelease.version.trimmingCharacters(in: .whitespacesAndNewlines)
        let rollingLatestMode = latest.caseInsensitiveCompare("latest") == .orderedSame

        if rollingLatestMode {
            return UpdateCheckOutcome(
                checkedAt: now,
                backendLatestAvailable: nil,
                error: nil
            )
        }

        guard versionMatchesRequiredMajor(latest, requiredMajor: requiredMajor),
              compareVersions(latest, backendCurrent) == .orderedDescending
        else {
            return UpdateCheckOutcome(
                checkedAt: now,
                backendLatestAvailable: nil,
                error: nil
            )
        }

        log("update available: \(latest) (current: \(backendCurrent))")
        return UpdateCheckOutcome(
            checkedAt: now,
            backendLatestAvailable: latest,
            error: nil
        )
    }

    func applyUpdateCheckOutcome(
        _ outcome: UpdateCheckOutcome,
        notify: Bool,
        previousBackendNotified: String?
    ) {
        isCheckingUpdates = false
        updateState.lastCheckedAt = outcome.checkedAt

        if outcome.error != nil {
            if notify {
                postNotification(
                    title: Config.displayName,
                    body: Config.Notification.updatesCheckFailedMessage
                )
            }
            return
        }

        var backendUpdateToNotify: String?
        if let backendLatest = outcome.backendLatestAvailable {
            let shouldNotify = notify || backendLatest != previousBackendNotified
            if shouldNotify {
                backendUpdateToNotify = backendLatest
                updateState.lastNotifiedBackendVersion = backendLatest
            }
        } else {
            updateState.lastNotifiedBackendVersion = nil
        }

        if let backendVersion = backendUpdateToNotify {
            postBackendUpdateReadyNotification(backendVersion)
        } else if notify {
            postNotification(title: Config.displayName, body: Config.Notification.noUpdatesMessage)
        }
    }

    func fetchLatestRelease() async -> ReleaseInfo? {
        guard let releasesBaseURL = Config.Backend.updateReleasesURL else {
            log("missing update releases URL config")
            return nil
        }

        let version: String
        if let pinned = configuredPinnedUpdateVersion() {
            version = pinned
        } else {
            guard let latest = await fetchLatestReleaseTag(
                releasesURL: releasesBaseURL
            )
            else {
                return nil
            }
            version = latest
        }

        let archiveName = canonicalBackendArchiveName(version: version)
        let archiveURL = releaseArchiveURL(
            releasesBaseURL: releasesBaseURL,
            version: version,
            archiveName: archiveName
        )
        return ReleaseInfo(version: version, archiveURL: archiveURL)
    }

    nonisolated func releaseArchiveURL(
        releasesBaseURL: URL,
        version: String,
        archiveName: String
    ) -> URL {
        releasesBaseURL
            .appendingPathComponent("download")
            .appendingPathComponent(version)
            .appendingPathComponent(archiveName)
    }

    nonisolated func parseReleaseTagFromResolvedURL(_ resolvedURL: URL) -> String? {
        let marker = "/releases/tag/"
        guard let markerRange = resolvedURL.path.range(of: marker) else {
            return nil
        }
        var tag = String(resolvedURL.path[markerRange.upperBound...])
        if let slash = tag.firstIndex(of: "/") {
            tag = String(tag[..<slash])
        }
        let trimmed = (tag.removingPercentEncoding ?? tag)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func fetchLatestReleaseTag(releasesURL: URL) async -> String? {
        if releasesURL.isFileURL {
            return readLatestReleaseTagFromMockSource(releasesURL: releasesURL)
        }

        let latestURL = releasesURL.appendingPathComponent("latest")
        var request = URLRequest(url: latestURL)
        request.timeoutInterval = 10
        request.setValue(Config.displayName, forHTTPHeaderField: "User-Agent")

        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            log("failed to resolve latest release at \(latestURL.absoluteString): \(error.localizedDescription)")
            return nil
        }

        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            log("latest release request failed (\(http.statusCode)) for \(latestURL.absoluteString)")
            return nil
        }

        guard let finalURL = response.url else {
            log("latest release request returned no resolved URL")
            return nil
        }

        guard let tag = parseReleaseTagFromResolvedURL(finalURL) else {
            log("failed to parse release tag from URL \(finalURL.absoluteString)")
            return nil
        }
        return tag
    }

    nonisolated func parseReleaseTagFromLatestPointer(
        _ rawValue: String,
        releasesBaseURL: URL
    ) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return parseReleaseTagFromResolvedURL(absolute) ?? trimmed
        }

        if let resolved = URL(string: trimmed, relativeTo: releasesBaseURL)?.absoluteURL,
            let parsed = parseReleaseTagFromResolvedURL(resolved)
        {
            return parsed
        }

        return trimmed
    }

    func readLatestReleaseTagFromMockSource(releasesURL: URL) -> String? {
        let pointerURL = releasesURL.appendingPathComponent("latest")
        guard
            let contents = try? String(contentsOf: pointerURL, encoding: .utf8),
            let tag = parseReleaseTagFromLatestPointer(contents, releasesBaseURL: releasesURL)
        else {
            log("failed to read mocked latest release pointer at \(pointerURL.path)")
            return nil
        }
        return tag
    }

    nonisolated func downloadFileWithBackendDownloader(
        from sourceURL: URL,
        to destinationURL: URL,
        downloader: any BackendDownloader,
        progress: (@MainActor (Double?) -> Void)? = nil
    ) async -> Bool {
        let fm = FileManager.default
        let tempURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".download-\(UUID().uuidString).tmp")
        if fm.fileExists(atPath: tempURL.path) {
            try? fm.removeItem(at: tempURL)
        }
        guard fm.createFile(atPath: tempURL.path, contents: nil) else {
            log("download failed: could not create temp file \(tempURL.path)")
            return false
        }
        var shouldCleanupTempFile = true
        defer {
            if shouldCleanupTempFile {
                try? fm.removeItem(at: tempURL)
            }
        }

        let stream: AsyncThrowingStream<Data, Error>
        do {
            stream = try await downloader.download(from: sourceURL)
        } catch {
            log("download failed: \(error.localizedDescription)")
            return false
        }

        do {
            let handle = try FileHandle(forWritingTo: tempURL)
            defer {
                try? handle.close()
            }

            var chunkCount = 0
            if let progress {
                await progress(0.0)
            }

            for try await chunk in stream {
                if !chunk.isEmpty {
                    try handle.write(contentsOf: chunk)
                }
                chunkCount += 1

                if let progress {
                    // Stream chunks do not expose expected total size; use a smooth bounded estimate.
                    let synthetic = min(0.95, Double(chunkCount) * 0.03)
                    await progress(synthetic)
                }
            }

            try handle.synchronize()
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.moveItem(at: tempURL, to: destinationURL)

            if let progress {
                await progress(1.0)
            }

            shouldCleanupTempFile = false
            return true
        } catch {
            log("download failed: \(error.localizedDescription)")
            return false
        }
    }

    nonisolated func makeBackendDownloader(for sourceURL: URL) -> any BackendDownloader {
        if sourceURL.isFileURL {
            return makeLocalhostBackendDownloader()
        }
        return HttpBackendDownloader(userAgent: Config.displayName)
    }

    nonisolated private func makeLocalhostBackendDownloader() -> LocalhostBackendDownloader {
        LocalhostBackendDownloader(
            streamDelayMillis: Config.Backend.updateLocalStreamDelayMillis
        )
    }
}
