import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: Self { self }

    var title: String {
        switch self {
        case .light: "Дневная"
        case .dark: "Ночная"
        case .system: "Авто"
        }
    }

    var icon: String {
        switch self {
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        case .system: "circle.lefthalf.filled"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

struct AppBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.warmBackground.ignoresSafeArea())
    }
}

extension View {
    func appBackground() -> some View {
        modifier(AppBackground())
    }
}
