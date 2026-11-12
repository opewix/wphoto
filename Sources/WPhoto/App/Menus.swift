import AppKit

/// Строка меню macOS. Стрелки, Delete, +/− и пробел обрабатывает само окно (повторяются
/// при удержании без мигания меню), здесь — команды с ⌘.
enum Menus {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(viewMenu()))
        main.addItem(submenu(toolsMenu()))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    @discardableResult
    private static func add(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
                            _ mods: NSEvent.ModifierFlags = .command, represented: String? = nil) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        item.representedObject = represented
        return item
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: L10nApp.name)
        add(menu, L.t("О программе WPhoto", "About WPhoto"), #selector(AppDelegate.showAbout(_:)))
        menu.addItem(.separator())
        add(menu, L.t("Открывать рисунки в WPhoto по умолчанию", "Make WPhoto the Default Viewer"),
            #selector(AppDelegate.makeDefaultViewer(_:)))
        menu.addItem(.separator())
        add(menu, L.t("Скрыть WPhoto", "Hide WPhoto"), #selector(NSApplication.hide(_:)), "h")
        add(menu, L.t("Скрыть остальные", "Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(menu, L.t("Показать все", "Show All"), #selector(NSApplication.unhideAllApplications(_:)))
        menu.addItem(.separator())
        add(menu, L.t("Завершить WPhoto", "Quit WPhoto"), #selector(NSApplication.terminate(_:)), "q")
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: L.t("Файл", "File"))
        add(menu, L.t("Новое окно", "New Window"), #selector(AppDelegate.newWindow(_:)), "n")
        add(menu, L.t("Открыть…", "Open…"), #selector(AppDelegate.openDocument(_:)), "o")
        menu.addItem(.separator())
        add(menu, L.t("Сохранить как…", "Save As…"), #selector(EditorController.saveAs(_:)), "s")
        add(menu, L.t("Дублировать файл…", "Duplicate File…"), #selector(ViewerController.makeCopy(_:)), "s", [.command, .shift])
        add(menu, L.t("Показать в Finder", "Show in Finder"), #selector(ViewerController.showInFinder(_:)), "r", [.command, .shift])
        add(menu, L.t("Свойства", "Properties"), #selector(ViewerController.showProperties(_:)), "i")
        add(menu, L.t("Сделать фоном рабочего стола", "Set as Desktop Picture"), #selector(ViewerController.setDesktopPicture(_:)))
        menu.addItem(.separator())
        add(menu, L.t("Печать…", "Print…"), #selector(ViewerController.printDocument(_:)), "p")
        menu.addItem(.separator())
        add(menu, L.t("Закрыть", "Close"), #selector(NSWindow.performClose(_:)), "w")
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: L.t("Правка", "Edit"))
        add(menu, L.t("Отменить", "Undo"), Selector(("undo:")), "z")
        add(menu, L.t("Повторить", "Redo"), Selector(("redo:")), "z", [.command, .shift])
        menu.addItem(.separator())
        add(menu, L.t("Копировать", "Copy"), #selector(ViewerController.copy(_:)), "c")
        add(menu, L.t("Переместить в Корзину", "Move to Trash"), #selector(ViewerController.moveToTrash(_:)), "\u{8}")
        add(menu, L.t("Спрашивать перед удалением", "Ask Before Moving to Trash"), #selector(AppDelegate.toggleConfirmDelete(_:)))
        menu.addItem(.separator())
        add(menu, L.t("Повернуть по часовой стрелке", "Rotate Clockwise"), #selector(ViewerController.rotateRight(_:)), "r")
        add(menu, L.t("Повернуть против часовой стрелки", "Rotate Counterclockwise"), #selector(ViewerController.rotateLeft(_:)), "l")
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: L.t("Вид", "View"))
        add(menu, L.t("Следующий рисунок", "Next Picture"), #selector(ViewerController.nextImage(_:)))
        add(menu, L.t("Предыдущий рисунок", "Previous Picture"), #selector(ViewerController.previousImage(_:)))
        add(menu, L.t("Первый рисунок", "First Picture"), #selector(ViewerController.firstImage(_:)), String(UnicodeScalar(NSUpArrowFunctionKey)!))
        add(menu, L.t("Последний рисунок", "Last Picture"), #selector(ViewerController.lastImage(_:)), String(UnicodeScalar(NSDownArrowFunctionKey)!))
        menu.addItem(.separator())
        add(menu, L.t("Увеличить", "Zoom In"), #selector(ViewerController.zoomIn(_:)), "=")
        add(menu, L.t("Уменьшить", "Zoom Out"), #selector(ViewerController.zoomOut(_:)), "-")
        add(menu, L.t("По размеру окна", "Fit to Window"), #selector(ViewerController.fitToWindow(_:)), "0")
        add(menu, L.t("Реальный размер", "Actual Size"), #selector(ViewerController.actualSize(_:)), "0", [.command, .option])
        menu.addItem(.separator())
        add(menu, L.t("Показ слайдов", "Play Slide Show"), #selector(ViewerController.startSlideshow(_:)), "f", [.command, .shift])
        menu.addItem(.separator())
        let theme = NSMenu(title: L.t("Тема", "Theme"))
        add(theme, "Windows Vista / 7", #selector(AppDelegate.setTheme(_:)), represented: ThemeKind.vista.rawValue)
        add(theme, "Windows XP", #selector(AppDelegate.setTheme(_:)), represented: ThemeKind.xp.rawValue)
        menu.addItem(submenu(theme))
        let wheel = NSMenu(title: L.t("Колесо мыши", "Mouse Wheel"))
        add(wheel, L.t("Меняет масштаб", "Zooms"), #selector(AppDelegate.setWheel(_:)), represented: WheelAction.zoom.rawValue)
        add(wheel, L.t("Листает рисунки", "Switches Pictures"), #selector(AppDelegate.setWheel(_:)), represented: WheelAction.navigate.rawValue)
        menu.addItem(submenu(wheel))
        menu.addItem(.separator())
        return menu
    }

    /// «Инструменты»: из окна просмотра открывают окно правки с нужным инструментом,
    /// в окне правки — переключают инструмент. Сохраняется всегда копия.
    static func toolsMenu() -> NSMenu {
        let menu = NSMenu(title: L.t("Инструменты", "Tools"))
        add(menu, L.t("Открыть в редакторе", "Edit Picture"), #selector(EditorController.editPicture(_:)), "e")
        menu.addItem(.separator())
        func tool(_ t: EditTool) {
            add(menu, t.title, #selector(EditorController.selectEditTool(_:)), represented: t.rawValue)
        }
        tool(.crop)
        add(menu, L.t("Изменить размер…", "Resize…"), #selector(EditorController.showResize(_:)), "r", [.command, .option])
        add(menu, L.t("Отразить по горизонтали", "Flip Horizontal"), #selector(EditorController.flipHorizontal(_:)))
        add(menu, L.t("Отразить по вертикали", "Flip Vertical"), #selector(EditorController.flipVertical(_:)))
        menu.addItem(.separator())
        for t in [EditTool.pen, .brush, .highlighter] { tool(t) }
        menu.addItem(.separator())
        for t in [EditTool.rectangle, .ellipse, .line, .arrow, .text] { tool(t) }
        menu.addItem(.separator())
        for t in [EditTool.blur, .pixelate] { tool(t) }
        menu.addItem(.separator())
        add(menu, L.t("Коррекция цвета…", "Adjust Colors…"), #selector(EditorController.showAdjust(_:)), "c", [.command, .option])
        let filters = filtersMenu()
        filters.title = L.t("Фильтры", "Filters")
        menu.addItem(submenu(filters))
        menu.addItem(.separator())
        add(menu, L.t("Сохранить как…", "Save As…"), #selector(EditorController.saveAs(_:)))
        return menu
    }

    static func filtersMenu() -> NSMenu {
        let menu = NSMenu(title: L.t("Фильтры", "Filters"))
        for filter in QuickFilter.allCases {
            add(menu, filter.title, #selector(EditorController.applyFilter(_:)), represented: filter.rawValue)
        }
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: L.t("Окно", "Window"))
        add(menu, L.t("Свернуть", "Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m")
        add(menu, L.t("Изменить масштаб", "Zoom"), #selector(NSWindow.performZoom(_:)))
        menu.addItem(.separator())
        add(menu, L.t("Все окна — на передний план", "Bring All to Front"), #selector(NSApplication.arrangeInFront(_:)))
        return menu
    }
}
