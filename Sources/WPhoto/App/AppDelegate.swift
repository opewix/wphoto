import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var launched = false
    private var pendingOpen: [URL] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Menus.build()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if launched {
            open(urls)
        } else {
            pendingOpen += urls
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launched = true
        if let directory = Snapshot.directory {
            Snapshot.run(into: directory, files: commandLineFiles())
            return
        }
        let urls = pendingOpen.isEmpty ? commandLineFiles() : pendingOpen
        pendingOpen = []
        open(urls)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { open([]) }
        return true
    }

    private func open(_ urls: [URL]) {
        let controller = urls.isEmpty ? ViewerController.make() : ViewerController.target()
        controller.open(urls)
        controller.showWindow(nil)
    }

    /// Пути из командной строки; `-ключ значение` — настройки, их пропускаем.
    private func commandLineFiles() -> [URL] {
        var result: [URL] = []
        var skip = false
        for arg in CommandLine.arguments.dropFirst() {
            if skip { skip = false; continue }
            if arg.hasPrefix("-") { skip = true; continue }
            if FileManager.default.fileExists(atPath: arg) {
                result.append(URL(fileURLWithPath: arg))
            }
        }
        return result
    }

    // MARK: - Команды меню

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .folder]
        if panel.runModal() == .OK {
            open(panel.urls)
        }
    }

    @objc func newWindow(_ sender: Any?) {
        open([])
    }

    @objc func setTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = ThemeKind(rawValue: raw) else { return }
        Settings.theme = kind
        NotificationCenter.default.post(name: Theme.changed, object: nil)
    }

    @objc func setWheel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = WheelAction(rawValue: raw) else { return }
        Settings.wheel = action
    }

    @objc func toggleConfirmDelete(_ sender: Any?) {
        Settings.confirmDelete.toggle()
    }

    @objc func showAbout(_ sender: Any?) {
        let credits = NSAttributedString(
            string: L.t("Просмотр рисунков в духе Windows для macOS.\nНезависимый проект, не связан с Microsoft.",
                        "A Windows-style picture viewer for macOS.\nAn independent project, not affiliated with Microsoft."),
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    /// Назначить WPhoto программой по умолчанию для распространённых форматов.
    @objc func makeDefaultViewer(_ sender: Any?) {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else {
            let alert = NSAlert()
            alert.messageText = L.t("Нужна собранная программа", "The app bundle is required")
            alert.informativeText = L.t("Запустите WPhoto.app (scripts/bundle.sh), а не исполняемый файл.",
                                        "Run WPhoto.app (scripts/bundle.sh), not the bare executable.")
            alert.runModal()
            return
        }
        let ids = ["public.jpeg", "public.png", "public.heic", "public.heif", "com.compuserve.gif", "public.tiff",
                   "com.microsoft.bmp", "org.webmproject.webp", "public.avif", "public.jpeg-2000",
                   "com.adobe.photoshop-image", "public.camera-raw-image", "com.microsoft.ico"]
        let types = ids.compactMap { UTType($0) }
        let group = DispatchGroup()
        var failed: [String] = []
        for type in types {
            group.enter()
            NSWorkspace.shared.setDefaultApplication(at: bundle, toOpen: type) { error in
                if error != nil { DispatchQueue.main.async { failed.append(type.preferredFilenameExtension ?? type.identifier) } }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let alert = NSAlert()
            alert.messageText = failed.isEmpty
                ? L.t("WPhoto открывает рисунки по умолчанию", "WPhoto is now the default picture viewer")
                : L.t("Не для всех форматов получилось", "Some formats could not be changed")
            if !failed.isEmpty { alert.informativeText = failed.joined(separator: ", ") }
            alert.runModal()
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(setTheme(_:)):
            item.state = (item.representedObject as? String) == Settings.theme.rawValue ? .on : .off
        case #selector(setWheel(_:)):
            item.state = (item.representedObject as? String) == Settings.wheel.rawValue ? .on : .off
        case #selector(toggleConfirmDelete(_:)):
            item.state = Settings.confirmDelete ? .on : .off
        default:
            break
        }
        return true
    }
}
