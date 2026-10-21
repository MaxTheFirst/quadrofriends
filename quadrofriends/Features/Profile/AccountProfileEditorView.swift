import PhotosUI
import SwiftUI

private struct VehicleEditorTarget: Identifiable {
    let id = UUID()
    let vehicle: AccountVehicleDTO?
}

struct AccountProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: APISession
    private let viewModel = AccountEditingViewModel()
    let onSaved: () async -> Void
    @State private var firstName: String
    @State private var lastName: String
    @State private var username: String
    @State private var birthYear: String
    @State private var city: String
    @State private var avatarURL: URL?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var error: String?
    @State private var isSaving = false
    @State private var isLoadingPhoto = false

    init(account: AccountProfileDTO, onSaved: @escaping () async -> Void) {
        self.onSaved = onSaved
        _firstName = State(initialValue: account.firstName)
        _lastName = State(initialValue: account.lastName)
        _username = State(initialValue: account.username)
        _birthYear = State(initialValue: account.birthYear.map(String.init) ?? "")
        _city = State(initialValue: account.city ?? "")
        _avatarURL = State(initialValue: account.avatar?.thumbnailUrl)
    }

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var isValid: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        username.range(of: "^[a-z0-9_]{3,30}$", options: .regularExpression) != nil &&
        (birthYear.isEmpty || (Int(birthYear).map { (1900...currentYear).contains($0) } ?? false))
    }

    var body: some View {
        Form {
            Section("Аватар") {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    HStack(spacing: 14) {
                        Group {
                            if let previewImage {
                                Image(uiImage: previewImage).resizable().scaledToFill()
                            } else if let avatarURL {
                                AsyncImage(url: avatarURL) { image in image.resizable().scaledToFill() } placeholder: {
                                    Image(systemName: "person.crop.circle.fill").resizable().scaledToFit()
                                }
                            } else {
                                Image(systemName: "person.crop.circle.fill").resizable().scaledToFit()
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                        Text("Выбрать фотографию")
                    }
                }
            }
            Section("Основное") {
                LabeledContent("Имя") { TextField("Имя", text: $firstName).multilineTextAlignment(.trailing) }
                LabeledContent("Фамилия") { TextField("Фамилия", text: $lastName).multilineTextAlignment(.trailing) }
                LabeledContent("Юзернейм") {
                    TextField("Юзернейм", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Год рождения") {
                    TextField("Год рождения", text: $birthYear)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Город") { TextField("Город", text: $city).multilineTextAlignment(.trailing) }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("Редактировать профиль")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { Task { await save() } }.disabled(!isValid || isSaving || isLoadingPhoto)
            }
        }
        .onChange(of: selectedPhoto) { _, photo in
            isLoadingPhoto = photo != nil
            Task { await loadPhoto(photo) }
        }
    }

    private func loadPhoto(_ photo: PhotosPickerItem?) async {
        guard let photo else { return }
        defer { isLoadingPhoto = false }
        do {
            guard let data = try await photo.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { throw APIError.invalidResponse }
            previewImage = image
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await viewModel.saveProfile(
                AccountProfileUpdate(
                    firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                    lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                    username: username,
                    birthYear: Int(birthYear),
                    city: city.trimmingCharacters(in: .whitespacesAndNewlines),
                    avatarMediaId: nil
                ),
                avatar: previewImage,
                using: RemoteAccountEditingDataSource(session: session)
            )
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct AccountVehiclesView: View {
    @EnvironmentObject private var session: APISession
    private let viewModel = AccountEditingViewModel()
    let account: AccountProfileDTO
    let onChanged: () async -> Void
    @State private var vehicles: [AccountVehicleDTO]
    @State private var vehicleEditor: VehicleEditorTarget?
    @State private var pendingSavedVehicle: AccountVehicleDTO?
    @State private var error: String?

    init(account: AccountProfileDTO, onChanged: @escaping () async -> Void) {
        self.account = account
        self.onChanged = onChanged
        _vehicles = State(initialValue: account.vehicles)
    }

    var body: some View {
        List {
            ForEach(vehicles) { vehicle in
                Button {
                    vehicleEditor = VehicleEditorTarget(vehicle: vehicle)
                } label: {
                    HStack(spacing: 12) {
                        Group {
                            if let url = vehicle.image?.thumbnailUrl {
                                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
                                    Image(systemName: "car.side.fill")
                                }
                            } else {
                                Image(systemName: "car.side.fill")
                            }
                        }
                        .frame(width: 54, height: 48).clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(vehicle.model).foregroundStyle(.primary)
                            Text("\(vehicle.year) г.\(vehicle.isPrimary ? " · основной" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                let selected = offsets.map { vehicles[$0] }
                for vehicle in selected { Task { await deleteVehicle(vehicle) } }
            }
            Button("Добавить технику", systemImage: "plus") {
                vehicleEditor = VehicleEditorTarget(vehicle: nil)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Моя техника")
        .sheet(item: $vehicleEditor, onDismiss: applyPendingVehicleChange) { target in
            NavigationStack {
                AccountVehicleEditorView(vehicle: target.vehicle) { saved in
                    pendingSavedVehicle = saved
                }
            }
        }
    }

    private func applyPendingVehicleChange() {
        guard let saved = pendingSavedVehicle else { return }
        pendingSavedVehicle = nil
        if let index = vehicles.firstIndex(where: { $0.id == saved.id }) {
            vehicles[index] = saved
        } else {
            vehicles.append(saved)
        }
        Task { await onChanged() }
    }

    private func deleteVehicle(_ vehicle: AccountVehicleDTO) async {
        do {
            try await viewModel.deleteVehicle(
                id: vehicle.id,
                using: RemoteAccountEditingDataSource(session: session)
            )
            vehicles.removeAll { $0.id == vehicle.id }
            await onChanged()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct AccountVehicleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: APISession
    private let viewModel = AccountEditingViewModel()
    let vehicle: AccountVehicleDTO?
    let onSaved: (AccountVehicleDTO) -> Void
    @State private var model: String
    @State private var year: String
    @State private var isPrimary: Bool
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var error: String?
    @State private var isSaving = false
    @State private var isLoadingPhoto = false

    init(vehicle: AccountVehicleDTO?, onSaved: @escaping (AccountVehicleDTO) -> Void) {
        self.vehicle = vehicle
        self.onSaved = onSaved
        _model = State(initialValue: vehicle?.model ?? "")
        _year = State(initialValue: vehicle.map { String($0.year) } ?? String(Calendar.current.component(.year, from: Date())))
        _isPrimary = State(initialValue: vehicle?.isPrimary ?? true)
    }

    private var isValid: Bool {
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (Int(year).map { (1950...Calendar.current.component(.year, from: Date()) + 1).contains($0) } ?? false)
    }

    var body: some View {
        Form {
            Section("Фото техники") {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    HStack(spacing: 14) {
                        Group {
                            if let previewImage {
                                Image(uiImage: previewImage).resizable().scaledToFill()
                            } else if let url = vehicle?.image?.thumbnailUrl {
                                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
                                    Image(systemName: "car.side.fill")
                                }
                            } else {
                                Image(systemName: "car.side.fill")
                            }
                        }
                        .frame(width: 80, height: 60).clipShape(RoundedRectangle(cornerRadius: 10))
                        Text("Выбрать фотографию")
                    }
                }
            }
            Section("Квадроцикл") {
                LabeledContent("Марка и модель") { TextField("Марка и модель", text: $model).multilineTextAlignment(.trailing) }
                LabeledContent("Год выпуска") { TextField("Год выпуска", text: $year).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                Toggle("Основной", isOn: $isPrimary)
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle(vehicle == nil ? "Добавить технику" : "Редактировать технику")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { Task { await save() } }.disabled(!isValid || isSaving || isLoadingPhoto)
            }
        }
        .onChange(of: selectedPhoto) { _, photo in
            isLoadingPhoto = photo != nil
            Task {
                guard let photo else { return }
                defer { isLoadingPhoto = false }
                do {
                    guard let data = try await photo.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { throw APIError.invalidResponse }
                    previewImage = image
                    error = nil
                } catch { self.error = error.localizedDescription }
            }
        }
    }

    private func save() async {
        guard let year = Int(year) else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await viewModel.saveVehicle(
                AccountVehicleWrite(
                    model: model.trimmingCharacters(in: .whitespacesAndNewlines), year: year,
                    imageMediaId: vehicle?.image?.id, isPrimary: isPrimary
                ),
                id: vehicle?.id,
                image: previewImage,
                using: RemoteAccountEditingDataSource(session: session)
            )
            onSaved(saved)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
