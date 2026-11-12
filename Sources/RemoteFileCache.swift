import CryptoKit
import Foundation

struct CachedRemoteFile: Sendable {
    let name: String
    let local: URL
}

/// 文件预览的磁盘缓存。同一文件并发打开或预取时只下载一次。
actor RemoteFileCache {
    static let shared = RemoteFileCache()

    private var tasks: [String: Task<CachedRemoteFile, Error>] = [:]

    nonisolated static func localFile(path: String, preferredName: String) -> CachedRemoteFile? {
        let cleanPath = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        guard let local = LocalStore.localURL(cleanPath),
              FileManager.default.fileExists(atPath: local.path),
              let values = try? local.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? 0) > 0 else { return nil }
        let localName = preferredName.isEmpty ? local.lastPathComponent : preferredName
        return CachedRemoteFile(name: safeName(localName), local: local)
    }

    func file(path: String, preferredName: String) async throws -> CachedRemoteFile {
        /* 发送方刚上传时 LocalStore 已经保存了原文件。文件名是随机且不可变的，
           直接打开本地副本，避免上传完成后又绕服务器整包下载一次。 */
        if let local = Self.localFile(path: path, preferredName: preferredName) { return local }
        guard let remote = API.shared.assetURL(path) else {
            throw APIError.message("这个文件找不到了")
        }
        let key = Self.key(remote.absoluteString)
        let directory = try cacheDirectory()
        if let existing = cachedFile(key: key, in: directory) {
            return existing
        }
        if let task = tasks[key] {
            return try await task.value
        }

        let name = Self.safeName(preferredName)
        let task = Task { () throws -> CachedRemoteFile in
            let destination = directory.appendingPathComponent(key + "-" + name)
            let temporary = directory.appendingPathComponent(
                ".download-" + key + "-" + UUID().uuidString)
            do {
                try await API.shared.downloadAssetToDisk(remote, destination: temporary)
                let values = try temporary.resourceValues(forKeys: [.fileSizeKey])
                let size = values.fileSize ?? 0
                guard size > 0 else { throw APIError.message("文件是空的") }
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: temporary, to: destination)
                try? (destination as NSURL).setResourceValue(
                    URLFileProtection.complete,
                    forKey: .fileProtectionKey
                )
                return CachedRemoteFile(name: name, local: destination)
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                throw error
            }
        }
        tasks[key] = task
        do {
            let result = try await task.value
            tasks[key] = nil
            return result
        } catch {
            tasks[key] = nil
            throw error
        }
    }

    func prefetch(path: String, preferredName: String, bytes: Int) {
        guard bytes > 0, bytes <= 30 * 1024 * 1024 else { return }
        guard let remote = API.shared.assetURL(path) else { return }
        let key = Self.key(remote.absoluteString)
        guard let directory = try? cacheDirectory(),
              cachedFile(key: key, in: directory) == nil,
              tasks[key] == nil else { return }
        Task { _ = try? await self.file(path: path, preferredName: preferredName) }
    }

    private func cacheDirectory() throws -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = root.appendingPathComponent("RemoteFilePreview", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func cachedFile(key: String, in directory: URL) -> CachedRemoteFile? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        guard let url = files.first(where: { $0.lastPathComponent.hasPrefix(key + "-") }),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? 0) > 0 else { return nil }
        let prefix = key + "-"
        return CachedRemoteFile(name: String(url.lastPathComponent.dropFirst(prefix.count)),
                                local: url)
    }

    private static func key(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func safeName(_ value: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = cleaned.isEmpty ? "文件" : cleaned
        if fallback.count <= 120 { return fallback }
        let ext = (fallback as NSString).pathExtension
        let base = String(fallback.prefix(100))
        return ext.isEmpty ? base : base + "." + ext
    }
}

extension API {
    /// 复用 App 现有证书固定会话，但把文件直接落盘，避免整文件进入内存。
    func downloadAssetToDisk(_ url: URL, destination: URL) async throws {
        var req = URLRequest(url: url)
        req.timeoutInterval = 120
        let useShared = !API.trustedHost(url.host ?? "")
        if !useShared, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let downloaded: URL
        let response: URLResponse
        if useShared {
            (downloaded, response) = try await URLSession.shared.download(for: req)
        } else {
            (downloaded, response) = try await session.download(for: req)
        }
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw APIError.message("文件下载失败（HTTP \(http.statusCode)）")
        }

        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: downloaded, to: destination)
    }
}
