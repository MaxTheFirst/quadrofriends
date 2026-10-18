import SwiftUI

private struct VehicleEditorTarget: Identifiable {
    let vehicle: Vehicle
    let isNew: Bool
    var id: UUID { vehicle.id }
}

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: UserProfile
    @State private var vehicleEditor: VehicleEditorTarget?
    let onSave: (UserProfile) -> Void

    init(profile: UserProfile, onSave: @escaping (UserProfile) -> Void) {
        _draft = State(initialValue: profile)
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
            Section("Основное") {
                TextField("Имя", text: $draft.firstName)
                TextField("Фамилия", text: $draft.lastName)
                TextField("Юзернейм", text: $draft.username)
                    .textInputAutocapitalization(.never)
                TextField("Год рождения", value: $draft.birthYear, format: .number.grouping(.never))
                    .keyboardType(.numberPad)
                TextField("Город", text: $draft.city)
            }

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
        .navigationTitle("Редактировать профиль")
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
            Section("Квадроцикл") {
                TextField("Марка и модель", text: $draft.model)
                TextField("Год выпуска", value: $draft.year, format: .number.grouping(.never))
                    .keyboardType(.numberPad)
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
    }
}
