import SwiftUI

struct ServerRecordingMarkerEditor: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String, String) async -> Bool
    @State private var title = ""
    @State private var details = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Метка у текущей геопозиции") {
                TextField("Название", text: $title)
                TextField("Описание", text: $details, axis: .vertical)
                    .lineLimit(3...6)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Новая метка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { Task { await save() } }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        if await onSave(title.trimmingCharacters(in: .whitespacesAndNewlines), details.trimmingCharacters(in: .whitespacesAndNewlines)) {
            dismiss()
        } else {
            error = "Не удалось сохранить метку. Проверьте соединение и повторите."
        }
    }
}

struct PublishRecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: APISession
    let recordingID: String
    let onSaved: () async -> Void
    @StateObject private var viewModel = PublishRecordingViewModel()
    @State private var title = ""
    @State private var details = ""
    @State private var isPrivate = true

    var body: some View {
        Form {
            Section("Маршрут") {
                TextField("Название", text: $title)
                TextField("Описание", text: $details, axis: .vertical)
                    .lineLimit(3...6)
                Toggle("Приватный маршрут", isOn: $isPrivate)
            }
            if let error = viewModel.error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Сохранить маршрут")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { Task { await save() } }
                    .disabled(viewModel.isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() async {
        if await viewModel.save(
            id: recordingID,
            title: title,
            description: details,
            isPrivate: isPrivate,
            using: RemoteServerRoutesDataSource(session: session)
        ) {
            await onSaved()
            dismiss()
        }
    }
}
