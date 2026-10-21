import PhotosUI
import SwiftUI

private struct VehicleEditorTarget: Identifiable {
    let vehicle: Vehicle
    let isNew: Bool
    var id: UUID { vehicle.id }
}

struct EditProfileView: View {
    enum Mode { case profile, vehicles }
    @Environment(\.dismiss) private var dismiss
    @State private var draft: UserProfile
    @State private var vehicleEditor: VehicleEditorTarget?
    @State private var selectedPhoto: PhotosPickerItem?
    let mode: Mode
    let onSave: (UserProfile) -> Void

    init(profile: UserProfile, mode: Mode = .profile, onSave: @escaping (UserProfile) -> Void) {
        _draft = State(initialValue: profile)
        self.mode = mode
        self.onSave = onSave
    }

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var isValid: Bool {
        !draft.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (1900...currentYear).contains(draft.birthYear)
    }

    var body: some View {
        Form {
            if mode == .profile {
                Section("Аватар") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        HStack(spacing: 14) {
                            Group {
                                if let data = draft.avatarData, let image = UIImage(data: data) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                } else {
                                    Image(systemName: "person.crop.circle.fill").resizable().scaledToFit()
                                }
                            }
                            .frame(width: 64, height: 64).clipShape(Circle())
                            Text("Выбрать фотографию")
                        }
                    }
                }
                Section("Основное") {
                    LabeledContent("Имя") { TextField("Имя", text: $draft.firstName).multilineTextAlignment(.trailing) }
                    LabeledContent("Фамилия") { TextField("Фамилия", text: $draft.lastName).multilineTextAlignment(.trailing) }
                    LabeledContent("Юзернейм") {
                        TextField("Юзернейм", text: $draft.username)
                            .textInputAutocapitalization(.never).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Год рождения") {
                        TextField("Год рождения", value: $draft.birthYear, format: .number.grouping(.never))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Город") { TextField("Город", text: $draft.city).multilineTextAlignment(.trailing) }
                }
            }

            if mode == .vehicles {
              Section("Моя техника") {
                ForEach(draft.vehicles) { vehicle in
                    Button {
                        vehicleEditor = VehicleEditorTarget(vehicle: vehicle, isNew: false)
                    } label: {
                        HStack {
                            VehicleRow(vehicle: vehicle)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteVehicles)

                Button("Добавить квадроцикл", systemImage: "plus") {
                    vehicleEditor = VehicleEditorTarget(
                        vehicle: Vehicle(model: "", year: currentYear, imageName: "RouteForest", isPrimary: draft.vehicles.isEmpty),
                        isNew: true
                    )
                }
            }
            }
        }
        .navigationTitle(mode == .profile ? "Редактировать профиль" : "Моя техника")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить", systemImage: "checkmark") {
                    onSave(draft)
                    dismiss()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .sheet(item: $vehicleEditor) { target in
            NavigationStack {
                EditVehicleView(vehicle: target.vehicle) { vehicle in
                    upsertVehicle(vehicle, isNew: target.isNew)
                }
            }
        }
        .onChange(of: selectedPhoto) { _, photo in
            Task {
                guard let photo, let data = try? await photo.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                draft.avatarData = image.jpegData(compressionQuality: 0.72)
            }
        }
    }

    private func upsertVehicle(_ vehicle: Vehicle, isNew: Bool) {
        if vehicle.isPrimary {
            for index in draft.vehicles.indices {
                draft.vehicles[index].isPrimary = false
            }
        }
        if isNew {
            draft.vehicles.append(vehicle)
        } else if let index = draft.vehicles.firstIndex(where: { $0.id == vehicle.id }) {
            draft.vehicles[index] = vehicle
        }
        if !draft.vehicles.isEmpty && !draft.vehicles.contains(where: \.isPrimary) {
            draft.vehicles[0].isPrimary = true
        }
    }

    private func deleteVehicles(at offsets: IndexSet) {
        draft.vehicles.remove(atOffsets: offsets)
        if !draft.vehicles.isEmpty && !draft.vehicles.contains(where: \.isPrimary) {
            draft.vehicles[0].isPrimary = true
        }
    }
}

private struct EditVehicleView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Vehicle
    @State private var selectedPhoto: PhotosPickerItem?
    let onSave: (Vehicle) -> Void

    init(vehicle: Vehicle, onSave: @escaping (Vehicle) -> Void) {
        _draft = State(initialValue: vehicle)
        self.onSave = onSave
    }

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var isValid: Bool {
        !draft.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (1950...(currentYear + 1)).contains(draft.year)
    }

    var body: some View {
        Form {
            Section("Фото техники") {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    HStack(spacing: 14) {
                        Group {
                            if let data = draft.imageData, let image = UIImage(data: data) {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                Image(draft.imageName).resizable().scaledToFill()
                            }
                        }
                        .frame(width: 80, height: 60).clipShape(RoundedRectangle(cornerRadius: 10))
                        Text("Выбрать фотографию")
                    }
                }
            }
            Section("Квадроцикл") {
                LabeledContent("Марка и модель") { TextField("Марка и модель", text: $draft.model).multilineTextAlignment(.trailing) }
                LabeledContent("Год выпуска") {
                    TextField("Год выпуска", value: $draft.year, format: .number.grouping(.never))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
                Toggle("Основной", isOn: $draft.isPrimary)
            }
        }
        .navigationTitle("Редактировать технику")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") {
                    onSave(draft)
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
        .onChange(of: selectedPhoto) { _, photo in
            Task {
                guard let photo, let data = try? await photo.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                draft.imageData = image.jpegData(compressionQuality: 0.72)
            }
        }
    }
}
