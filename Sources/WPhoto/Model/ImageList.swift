import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Список рисунков, по которому листают стрелки: все рисунки папки открытого файла
/// (по имени, как в Finder) или файлы, выделенные и открытые вместе.
/// Папка отслеживается: новые и удалённые файлы появляются и исчезают сами.
final class ImageList {
    private(set) var urls: [URL]
    private(set) var index: Int
    let folder: URL?
    /// Состав папки поменялся снаружи (файл добавили, удалили, переименовали).
    var onExternalChange: (() -> Void)?

    private var watcher: DispatchSourceFileSystemObject?
    private var rescanPending = false

    /// Расширения, которые умеет читать ImageIO (без PDF — это не рисунок).
    static let extensions: Set<String> = {
        let ids = CGImageSourceCopyTypeIdentifiers() as? [String] ?? []
        var result = Set<String>()
        for id in ids {
            guard let type = UTType(id), !type.conforms(to: .pdf) else { continue }
            for ext in type.tags[.filenameExtension] ?? [] {
                result.insert(ext.lowercased())
            }
        }
        return result
    }()

    static func isImage(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    init(opening input: [URL]) {
        let files = input.map(\.standardizedFileURL)
        if files.count == 1 {
            let url = files[0]
            if Self.isDirectory(url) {
                folder = url
                urls = Self.scan(url)
                index = 0
            } else {
                let dir = url.deletingLastPathComponent()
                folder = dir
                var list = Self.scan(dir)
                if !list.contains(where: { $0.lastPathComponent == url.lastPathComponent }) {
                    // Файл с непривычным расширением открыли явно — всё равно показываем.
                    list.append(url)
                    list.sort(by: Self.order)
                }
                urls = list
                index = list.firstIndex { $0.lastPathComponent == url.lastPathComponent } ?? 0
            }
        } else {
            folder = nil
            urls = files.filter { !Self.isDirectory($0) }.sorted(by: Self.order)
            index = 0
        }
        startWatching()
    }

    deinit {
        watcher?.cancel()
    }

    var current: URL? {
        urls.indices.contains(index) ? urls[index] : nil
    }

    var count: Int { urls.count }

    func step(_ delta: Int) {
        guard !urls.isEmpty else { return }
        let n = urls.count
        index = ((index + delta) % n + n) % n
    }

    func select(_ newIndex: Int) {
        guard urls.indices.contains(newIndex) else { return }
        index = newIndex
    }

    func select(_ url: URL) {
        if let i = urls.firstIndex(where: { $0.path == url.path }) {
            index = i
        }
    }

    /// Соседи текущего — их стоит декодировать заранее: сначала следующий, потом предыдущий.
    func neighbors() -> [URL] {
        guard urls.count > 1 else { return [] }
        var result: [URL] = []
        for delta in [1, -1, 2] {
            let n = urls.count
            let url = urls[((index + delta) % n + n) % n]
            if url != current, !result.contains(url) {
                result.append(url)
            }
        }
        return result
    }

    func remove(_ url: URL) {
        guard let i = urls.firstIndex(where: { $0.path == url.path }) else { return }
        urls.remove(at: i)
        if i < index {
            index -= 1
        } else if index >= urls.count {
            index = 0
        }
    }

    func insert(_ url: URL) {
        if !urls.contains(where: { $0.path == url.path }) {
            urls.append(url)
            urls.sort(by: Self.order)
        }
        select(url)
    }

    // MARK: - Папка

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    static func scan(_ folder: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return items.filter(isImage).sorted(by: order)
    }

    /// Порядок Finder: «img2» раньше «img10».
    static func order(_ a: URL, _ b: URL) -> Bool {
        a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
    }

    private func startWatching() {
        guard let folder else { return }
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleRescan() }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private func scheduleRescan() {
        guard !rescanPending else { return }
        rescanPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.rescanPending = false
            self.rescan()
        }
    }

    private func rescan() {
        guard let folder else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fresh = Self.scan(folder)
            DispatchQueue.main.async { self?.apply(fresh) }
        }
    }

    private func apply(_ fresh: [URL]) {
        guard fresh.map(\.path) != urls.map(\.path) else { return }
        let name = current?.lastPathComponent
        let old = index
        urls = fresh
        if let name, let i = fresh.firstIndex(where: { $0.lastPathComponent == name }) {
            index = i
        } else {
            index = min(old, max(0, fresh.count - 1))
        }
        onExternalChange?()
    }
}
