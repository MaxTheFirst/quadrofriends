import SwiftUI
import PhotosUI
import UIKit

private struct RouteMarkerPhoto: Identifiable {
    enum Source {
        case asset(String)
        case data(Data)
    }

    let id: UUID
    let source: Source

    init(id: UUID = UUID(), source: Source) {
        self.id = id
        self.source = source
    }

    static let samples = [
        RouteMarkerPhoto(source: .asset("RouteFields")),
        RouteMarkerPhoto(source: .asset("RouteForest")),
        RouteMarkerPhoto(source: .asset("RouteMountain"))
    ]
}

private struct RouteMarkerPhotoThumbnail: View {
    let photo: RouteMarkerPhoto

    var body: some View {
        photoImage
            .resizable()
            .scaledToFill()
            .clipped()
    }

    private var photoImage: Image {
        switch photo.source {
        case .asset(let name):
            return Image(name)
        case .data(let data):
            if let image = UIImage(data: data) {
                return Image(uiImage: image)
            }
            return Image(systemName: "photo")
        }
    }
}

struct RouteMarkerView: View {
    let route: TrailRoute

    @State private var markerTitle = "Смотровая площадка"
    @State private var markerDetails = "Отличное место, чтобы сделать перерыв и насладиться видом на долину. Есть скамейка и стол."
    @State private var markerPhotos = RouteMarkerPhoto.samples
    @State private var showingEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RoutePhoto(imageName: route.imageName, height: 270, cornerRadius: 0)
                VStack(alignment: .leading, spacing: 14) {
                    Text(markerTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                    Label("2,3 км от старта", systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(Color.brandOrange)
                    Text(markerDetails)
                    SectionTitle(title: "Фото")
                    if markerPhotos.isEmpty {
                        Label("Фото не добавлены", systemImage: "photo")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 8) {
                                ForEach(markerPhotos) { photo in
                                    RouteMarkerPhotoThumbnail(photo: photo)
                                        .frame(width: 112, height: 92)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                        .frame(height: 92)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .appBackground()
        .navigationTitle("Метка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Редактировать", systemImage: "pencil") {
                    showingEditor = true
                }
                    .labelStyle(.iconOnly)
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                EditRouteMarkerView(
                    title: $markerTitle,
                    details: $markerDetails,
                    photos: $markerPhotos
                )
            }
            .presentationDetents([.medium, .large])
        }
    }
}

private struct EditRouteMarkerView: View {
    @Binding var title: String
    @Binding var details: String
    @Binding var photos: [RouteMarkerPhoto]

    @Environment(\.dismiss) private var dismiss
    @State private var draftTitle: String
    @State private var draftDetails: String
    @State private var draftPhotos: [RouteMarkerPhoto]
    @State private var selectedPhotos: [PhotosPickerItem] = []

    init(
        title: Binding<String>,
        details: Binding<String>,
        photos: Binding<[RouteMarkerPhoto]>
    ) {
        _title = title
        _details = details
        _photos = photos
        _draftTitle = State(initialValue: title.wrappedValue)
        _draftDetails = State(initialValue: details.wrappedValue)
        _draftPhotos = State(initialValue: photos.wrappedValue)
    }

    var body: some View {
        Form {
            Section("Метка") {
                TextField("Название", text: $draftTitle)
                TextField("Описание", text: $draftDetails, axis: .vertical)
                    .lineLimit(4...8)
            }

            Section("Фото") {
                if draftPhotos.isEmpty {
                    Label("Фото не добавлены", systemImage: "photo")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(draftPhotos) { photo in
                                ZStack(alignment: .topTrailing) {
                                    RouteMarkerPhotoThumbnail(photo: photo)
                                        .frame(width: 112, height: 92)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                    Button("Удалить фото", systemImage: "xmark.circle.fill", role: .destructive) {
                                        draftPhotos.removeAll { $0.id == photo.id }
                                    }
                                    .labelStyle(.iconOnly)
                                    .font(.title3)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(Color.white, Color.red)
                                    .padding(5)
                                }
                            }
                        }
                    }
                    .frame(height: 92)
                }

                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 10,
                    matching: .images
                ) {
                    Label("Добавить фото", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("Редактировать метку")
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
                    title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    details = draftDetails.trimmingCharacters(in: .whitespacesAndNewlines)
                    photos = draftPhotos
                    dismiss()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .task(id: selectedPhotos) {
            guard !selectedPhotos.isEmpty else { return }

            let items = selectedPhotos
            var loadedPhotos: [RouteMarkerPhoto] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    loadedPhotos.append(RouteMarkerPhoto(source: .data(data)))
                }
            }

            draftPhotos.append(contentsOf: loadedPhotos)
            selectedPhotos.removeAll()
        }
    }
}
