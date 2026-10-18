import SwiftUI
import MapKit

struct MapSettingsView: View {
    @Binding var mapStyle: MapDisplayStyle
    @Binding var appTheme: AppTheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Вид карты") {
                Picker("Вид карты", selection: $mapStyle) {
                    ForEach(MapDisplayStyle.allCases) { style in
                        Label(style.title, systemImage: style.icon).tag(style)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Тема приложения") {
                Picker("Тема", selection: $appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Label(theme.title, systemImage: theme.icon).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle("Настройки карты")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово", systemImage: "checkmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
