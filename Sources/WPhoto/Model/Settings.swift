import Foundation

enum ThemeKind: String {
    case vista, xp
}

/// Что делает колесо мыши (не трекпад): масштаб, как в Windows, или листание.
enum WheelAction: String {
    case zoom, navigate
}

enum SlideSpeed: String, CaseIterable {
    case slow, medium, fast

    var interval: TimeInterval {
        switch self {
        case .slow: return 6
        case .medium: return 3.5
        case .fast: return 2
        }
    }

    var title: String {
        switch self {
        case .slow: return L.t("Медленно", "Slow")
        case .medium: return L.t("Средне", "Medium")
        case .fast: return L.t("Быстро", "Fast")
        }
    }
}

/// Настройки в UserDefaults. Аргументы запуска подменяют их без записи: `-theme xp`.
enum Settings {
    private static let defaults = UserDefaults.standard

    static var theme: ThemeKind {
        get { ThemeKind(rawValue: defaults.string(forKey: "theme") ?? "") ?? .vista }
        set { defaults.set(newValue.rawValue, forKey: "theme") }
    }

    static var wheel: WheelAction {
        get { WheelAction(rawValue: defaults.string(forKey: "wheel") ?? "") ?? .zoom }
        set { defaults.set(newValue.rawValue, forKey: "wheel") }
    }

    static var confirmDelete: Bool {
        get { defaults.object(forKey: "confirmDelete") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "confirmDelete") }
    }

    static var slideSpeed: SlideSpeed {
        get { SlideSpeed(rawValue: defaults.string(forKey: "slideSpeed") ?? "") ?? .medium }
        set { defaults.set(newValue.rawValue, forKey: "slideSpeed") }
    }

    static var slideShuffle: Bool {
        get { defaults.bool(forKey: "slideShuffle") }
        set { defaults.set(newValue, forKey: "slideShuffle") }
    }

    static var slideLoop: Bool {
        get { defaults.object(forKey: "slideLoop") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "slideLoop") }
    }
}
