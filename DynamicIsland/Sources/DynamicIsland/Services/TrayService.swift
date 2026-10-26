import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

struct TrayItem: Identifiable, Equatable {
    /// The file name inside the tray folder.
    var id: String { url.lastPathComponent }
    let url: URL
    let added: Date

    var name: String { url.deletingPathExtension().lastPathComponent }
    var isImage: Bool { UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true }
}

/// A shelf for files: drop things on the island, drag them out somewhere else later.
/// Dropped files are copied into a folder of their own, so the originals can move or go away.
@MainActor @Observable
final class TrayService {
    private(set) var items: [TrayItem] = []
    private(set) var thumbnails: [String: NSImage] = [:]
    private(set) var isImporting = false

    let folder: URL
    @ObservationIgnored private let settings: AppSettings

    static let acceptedTypes: [UTType] = [.fileURL, .image, .url, .plainText]

    init(settings: AppSettings) {
        self.settings = settings
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        folder = support.appendingPathComponent("Dynamic Island/Tray", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        reload()
        removeExpired()
    }

    func reload() {
        let keys: [URLResourceKey] = [.creationDateKey, .addedToDirectoryDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles])) ?? []
        let found = urls.map { url -> TrayItem in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return TrayItem(url: url, added: values?.addedToDirectoryDate ?? values?.creationDate ?? Date())
        }
        .sorted { $0.added > $1.added }
        if found != items { items = found }
        for item in found where thumbnails[item.id] == nil { loadThumbnail(item) }
    }

    // MARK: Adding

    /// Accepts files, images, links and text from a drop. Returns false if nothing usable was offered.
    @discardableResult
    func add(_ providers: [NSItemProvider]) -> Bool {
        let usable = providers.filter { provider in Self.acceptedTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) } }
        guard !usable.isEmpty else { return false }
        isImporting = true
        let folder = folder
        Task {
            for provider in usable {
                await Self.importItem(from: provider, into: folder)
            }
            isImporting = false
            reload()
        }
        return true
    }

    func add(urls: [URL]) {
        let folder = folder
        Task {
            for url in urls { await Self.copy(url, into: folder) }
            reload()
        }
    }

    private static func importItem(from provider: NSItemProvider, into folder: URL) async {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadURL(provider, type: .fileURL), url.isFileURL {
            await copy(url, into: folder)
            return
        }
        if let imageType = provider.registeredTypeIdentifiers.compactMap({ UTType($0) }).first(where: { $0.conforms(to: .image) }),
           let data = await loadData(provider, type: imageType) {
            let name = (provider.suggestedName ?? "Bild") + "." + (imageType.preferredFilenameExtension ?? "png")
            write(data, named: name, into: folder)
            return
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier), let url = await loadURL(provider, type: .url) {
            let plist: [String: String] = ["URL": url.absoluteString]
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                write(data, named: (url.host ?? "Länk") + ".webloc", into: folder)
            }
            return
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let data = await loadData(provider, type: .plainText) {
            let text = String(decoding: data, as: UTF8.self)
            let title = String(text.prefix(30)).components(separatedBy: .newlines).first ?? "Text"
            write(Data(text.utf8), named: (title.isEmpty ? "Text" : title) + ".txt", into: folder)
        }
    }

    private static func loadURL(_ provider: NSItemProvider, type: UTType) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
                if let data = item as? Data {
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let string = item as? String {
                    continuation.resume(returning: URL(string: string))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadData(_ provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func copy(_ source: URL, into folder: URL) async {
        await Task.detached(priority: .userInitiated) {
            let destination = uniqueURL(for: source.lastPathComponent, in: folder)
            try? FileManager.default.copyItem(at: source, to: destination)
        }.value
    }

    private static func write(_ data: Data, named name: String, into folder: URL) {
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        try? data.write(to: uniqueURL(for: safe, in: folder))
    }

    private nonisolated static func uniqueURL(for name: String, in folder: URL) -> URL {
        var url = folder.appendingPathComponent(name)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            number += 1
        }
        return url
    }

    // MARK: Managing

    func remove(_ item: TrayItem) {
        try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        thumbnails[item.id] = nil
        reload()
    }

    func clear() {
        for item in items { try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil) }
        thumbnails = [:]
        reload()
    }

    func open(_ item: TrayItem) { NSWorkspace.shared.open(item.url) }
    func reveal(_ item: TrayItem) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
    func openFolder() { NSWorkspace.shared.open(folder) }

    func copyToPasteboard(_ item: TrayItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item.url as NSURL])
    }

    /// Moves items older than the retention setting to the Trash.
    func removeExpired() {
        let days = settings.trayRetentionDays
        guard days > 0, let limit = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return }
        for item in items where item.added < limit {
            try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        }
        if !items.isEmpty { reload() }
    }

    private func loadThumbnail(_ item: TrayItem) {
        thumbnails[item.id] = NSWorkspace.shared.icon(forFile: item.url.path)
        let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 120, height: 120),
                                                   scale: 2, representationTypes: .thumbnail)
        Task {
            guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return }
            thumbnails[item.id] = representation.nsImage
        }
    }
}
