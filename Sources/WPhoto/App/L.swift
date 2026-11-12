import Foundation

/// Две строки интерфейса — русская и английская; язык берётся из настроек системы.
enum L {
    static let isRussian = Locale.preferredLanguages.first?.hasPrefix("ru") ?? false

    static func t(_ ru: String, _ en: String) -> String {
        isRussian ? ru : en
    }
}
