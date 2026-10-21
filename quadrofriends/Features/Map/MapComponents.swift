import SwiftUI
import MapKit
import PhotosUI
import UIKit

enum MapControlLayout {
    static let size: CGFloat = 58
    static let edgeInset: CGFloat = 16
}

struct MapControlButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: MapControlLayout.size, height: MapControlLayout.size)
                .background(tint, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.18), radius: 8, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct SelectedRouteMarker: View {
    let route: TrailRoute

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(route.imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 54, height: 54)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(Color.brandOrange, lineWidth: 4)
                }
                .shadow(color: Color.black.opacity(0.2), radius: 7, y: 3)

            Image(systemName: "checkmark")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(Color.white)
                .frame(width: 20, height: 20)
                .background(Color.brandOlive, in: Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Выбран маршрут: \(route.title)")
    }
}

struct RouteMapMarker: Identifiable {
    let id = UUID()
    let title: String
    let details: String
    let coordinate: CLLocationCoordinate2D
    let photoData: Data?
}

struct RouteMapMarkerBadge: View {
    let marker: RouteMapMarker

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.brandOlive)

            if let photoData = marker.photoData,
               let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Image(systemName: "mappin.and.ellipse")
                    .font(.title3)
                    .foregroundStyle(Color.white)
            }
        }
        .frame(width: 46, height: 46)
        .overlay(Circle().stroke(Color.white, lineWidth: 3))
        .shadow(color: Color.black.opacity(0.2), radius: 6, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(marker.title)
        .accessibilityHint(marker.details)
    }
}

struct AddRouteMarkerView: View {
    @Binding var markerCoordinate: CLLocationCoordinate2D
    let onSave: (String, String, CLLocationCoordinate2D, Data?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section {
                Label("Перетащите метку на основной карте", systemImage: "hand.draw.fill")
                    .foregroundStyle(Color.brandOlive)

                HStack {
                    Text("Координаты")
                    Spacer()
                    Text(coordinateText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Положение")
            } footer: {
                Text("Начальная точка — ваша текущая геопозиция. Карта остаётся активной над этой панелью.")
            }

            Section("Метка") {
                TextField("Название", text: $title)
                TextField("Описание", text: $details, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("Фото") {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    HStack(spacing: 12) {
                        photoPreview
                        VStack(alignment: .leading, spacing: 3) {
                            Text(photoData == nil ? "Добавить фото" : "Заменить фото")
                                .font(.headline)
                            Text("Фото поможет другим узнать это место")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Новая метка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть", systemImage: "xmark") {
                    dismiss()
                }
                .labelStyle(.iconOnly)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить", systemImage: "checkmark") {
                    onSave(
                        trimmedTitle,
                        details.trimmingCharacters(in: .whitespacesAndNewlines),
                        markerCoordinate,
                        photoData
                    )
                    dismiss()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .disabled(trimmedTitle.isEmpty)
            }
        }
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            photoData = try? await selectedPhoto.loadTransferable(type: Data.self)
        }
    }

    private var coordinateText: String {
        String(
            format: "%.5f, %.5f",
            markerCoordinate.latitude,
            markerCoordinate.longitude
        )
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let photoData, let image = UIImage(data: photoData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Image(systemName: "photo.badge.plus")
                .font(.title2)
                .foregroundStyle(Color.brandOlive)
                .frame(width: 64, height: 52)
                .background(Color.brandOlive.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

struct RecordingRouteSummary: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let elapsed = max(0, Int(context.date.timeIntervalSince(startedAt)))
            let distance = Double(elapsed) * 0.0032
            let elevationGain = Int(distance * 28)

            HStack(spacing: 0) {
                RecordingMetric(
                    icon: "clock.fill",
                    value: duration(elapsed),
                    label: "Время"
                )

                Divider()
                    .frame(height: 38)

                RecordingMetric(
                    icon: "point.topleft.down.to.point.bottomright.curvepath",
                    value: String(format: "%.2f км", distance),
                    label: "Дистанция"
                )

                Divider()
                    .frame(height: 38)

                RecordingMetric(
                    icon: "arrow.up.forward",
                    value: "+\(elevationGain) м",
                    label: "Набор"
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 13)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .padding(12)
            }
            .shadow(color: Color.black.opacity(0.14), radius: 14, y: 5)
        }
    }

    private func duration(_ elapsed: Int) -> String {
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}

struct RecordingMetric: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
