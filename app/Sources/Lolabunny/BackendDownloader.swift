import Foundation

struct BackendDownloadError: Error {
    let what: String
}

protocol BackendDownloader: Sendable {
    func download(
        from sourceURL: URL
    ) async throws -> AsyncThrowingStream<Data, Error>
}
