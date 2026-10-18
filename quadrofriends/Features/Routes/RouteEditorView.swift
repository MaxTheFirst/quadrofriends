import SwiftUI
import MapKit

struct RouteEditorView: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Покатушка выходного дня"
    @State private var description = "Классный кольцевой маршрут недалеко от города. Много грязи и отличные виды!"
    @State private var isPrivate = true
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 60.011, longitude: 30.254),
            span: MKCoordinateSpan(latitudeDelta: 0.11, longitudeDelta: 0.11)
        )
    )

    private let points = [
        CLLocationCoordinate2D(latitude: 59.979, longitude: 30.211),
        CLLocationCoordinate2D(latitude: 60.005, longitude: 30.236),
        CLLocationCoordinate2D(latitude: 60.027, longitude: 30.251),
        CLLocationCoordinate2D(latitude: 60.011, longitude: 30.292),
        CLLocationCoordinate2D(latitude: 59.985, longitude: 30.274)
    ]

    var body: some View {
        Form {
            Section {
                routeMap
                HStack {
                    Button("Добавить точку", systemImage: "plus") { }
                    Spacer()
                    Button("Отменить", systemImage: "arrow.uturn.backward") { }
                }
            } header: {
                Text("Трек")
            }

            Section {
                TextField("Название", text: $name)
                TextEditor(text: $description)
                    .frame(minHeight: 90)
            } header: {
                Text("О маршруте")
            }

            Section {
                photoPicker
            } header: {
                Text("Фото")
            }

            Section {
                Toggle(isOn: $isPrivate) {
                    Label(isPrivate ? "Приватный маршрут" : "Публичный маршрут", systemImage: isPrivate ? "lock.fill" : "globe")
                }
            } header: {
                Text("Доступ")
            } footer: {
                Text(isPrivate ? "Маршрут виден только вам и тем, с кем вы им поделитесь." : "Маршрут смогут найти все пользователи.")
            }
        }
        .navigationTitle(title)
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
                    dismiss()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var routeMap: some View {
        Map(position: $camera) {
            MapPolyline(coordinates: points + [points[0]])
                .stroke(Color.brandOrange, style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [3, 7]))
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                Annotation("\(index + 1)", coordinate: point) {
                    Text("\(index + 1)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.white)
                        .frame(width: 24, height: 24)
                        .background(Color.brandOrange, in: Circle())
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var photoPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(["RouteForest", "RouteMud", "RouteFields"], id: \.self) { image in
                    Image(image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 92, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                Button("Добавить", systemImage: "plus") { }
                    .labelStyle(.iconOnly)
                    .frame(width: 72, height: 72)
                    .background(Color(.quaternarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}
