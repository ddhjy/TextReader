import Foundation

enum AppGroupConfiguration {
    static let identifier = "group.cn.1pointech.www.TextReader"
}

enum SharedImportSourceType: String, Codable {
    case text
    case file
}

struct SharedImportItem: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String?
    let sourceType: SharedImportSourceType
    let createdAt: Date
    let payloadFileName: String

    var metadataFileName: String {
        "\(id.uuidString).json"
    }
}

final class SharedImportStore {
    enum StoreError: Error {
        case appGroupUnavailable
    }

    private let inboxDirectoryName = "SharedInbox"
    private let temporaryDirectoryName = "tmp"
    private let fileManager: FileManager
    private let containerURLProvider: () -> URL?

    init(appGroupIdentifier: String = AppGroupConfiguration.identifier,
         fileManager: FileManager = .default,
         containerURLProvider: (() -> URL?)? = nil) {
        self.fileManager = fileManager
        self.containerURLProvider = containerURLProvider ?? {
            fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        }
    }

    @discardableResult
    func enqueueTextImport(text: String,
                           title: String?,
                           sourceType: SharedImportSourceType,
                           createdAt: Date = Date()) throws -> SharedImportItem {
        let importID = UUID()
        let normalizedTitle = Self.normalizeOptionalTitle(title)
        let item = SharedImportItem(
            id: importID,
            title: normalizedTitle,
            sourceType: sourceType,
            createdAt: createdAt,
            payloadFileName: "\(importID.uuidString).txt"
        )

        let inboxURL = try inboxDirectoryURL()
        let tempDirectoryURL = try temporaryDirectoryURL()
        let payloadURL = inboxURL.appendingPathComponent(item.payloadFileName)
        let metadataURL = inboxURL.appendingPathComponent(item.metadataFileName)
        let tempPayloadURL = tempDirectoryURL.appendingPathComponent("\(importID.uuidString)-payload.tmp")
        let tempMetadataURL = tempDirectoryURL.appendingPathComponent("\(importID.uuidString)-metadata.tmp")

        try Data(text.utf8).write(to: tempPayloadURL, options: .atomic)
        try JSONEncoder().encode(item).write(to: tempMetadataURL, options: .atomic)

        try moveItemReplacingExisting(at: tempPayloadURL, to: payloadURL)
        try moveItemReplacingExisting(at: tempMetadataURL, to: metadataURL)

        return item
    }

    func pendingImports() throws -> [SharedImportItem] {
        let inboxURL = try inboxDirectoryURL()
        let fileURLs = try fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )

        let metadataURLs = fileURLs.filter { $0.pathExtension.lowercased() == "json" }
        let decoder = JSONDecoder()

        return metadataURLs.compactMap { metadataURL in
            do {
                let data = try Data(contentsOf: metadataURL)
                return try decoder.decode(SharedImportItem.self, from: data)
            } catch {
                print("[SharedImportStore] 读取共享导入元数据失败: \(metadataURL.lastPathComponent), \(error)")
                return nil
            }
        }
        .sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    @discardableResult
    func consumePendingImports(_ consumer: (SharedImportItem, String) throws -> Bool) throws -> [SharedImportItem] {
        var consumedItems: [SharedImportItem] = []

        for item in try pendingImports() {
            let text: String
            do {
                text = try readPayload(for: item)
            } catch {
                print("[SharedImportStore] 读取共享导入正文失败: \(item.payloadFileName), \(error)")
                try? deleteImportedItem(item)
                continue
            }

            do {
                if try consumer(item, text) {
                    try deleteImportedItem(item)
                    consumedItems.append(item)
                }
            } catch {
                print("[SharedImportStore] 消费共享导入失败，保留待重试项 \(item.id): \(error)")
            }
        }

        return consumedItems
    }

    func deleteImportedItem(_ item: SharedImportItem) throws {
        let inboxURL = try inboxDirectoryURL()
        let payloadURL = inboxURL.appendingPathComponent(item.payloadFileName)
        let metadataURL = inboxURL.appendingPathComponent(item.metadataFileName)

        if fileManager.fileExists(atPath: payloadURL.path) {
            try fileManager.removeItem(at: payloadURL)
        }
        if fileManager.fileExists(atPath: metadataURL.path) {
            try fileManager.removeItem(at: metadataURL)
        }
    }

    private func readPayload(for item: SharedImportItem) throws -> String {
        let inboxURL = try inboxDirectoryURL()
        let payloadURL = inboxURL.appendingPathComponent(item.payloadFileName)
        return try String(contentsOf: payloadURL, encoding: .utf8)
    }

    private func inboxDirectoryURL() throws -> URL {
        let containerURL = try sharedContainerURL()
        let inboxURL = containerURL.appendingPathComponent(inboxDirectoryName, isDirectory: true)
        try ensureDirectoryExists(at: inboxURL)
        return inboxURL
    }

    private func temporaryDirectoryURL() throws -> URL {
        let tempURL = try inboxDirectoryURL().appendingPathComponent(temporaryDirectoryName, isDirectory: true)
        try ensureDirectoryExists(at: tempURL)
        return tempURL
    }

    private func sharedContainerURL() throws -> URL {
        guard let containerURL = containerURLProvider() else {
            throw StoreError.appGroupUnavailable
        }
        return containerURL
    }

    private func ensureDirectoryExists(at url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func moveItemReplacingExisting(at sourceURL: URL, to destinationURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    private static func normalizeOptionalTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
