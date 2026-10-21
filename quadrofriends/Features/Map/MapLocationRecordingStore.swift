import Combine
import CoreLocation
import Foundation

struct MapRecordingDTO: Decodable {
    let id: String
    let status: String
    let startedAt: Date
    let distanceM: Double
    let pointCount: Int
}

private struct MapRecordingCreate: Encodable {
    let mode = "free"
}

private struct MapRecordingStatus: Encodable {
    let status: String
}

private struct MapTrackPoint: Encodable {
    let sequence: Int
    let coordinate: CoordinateDTO
    let recordedAt: Date
    let accuracyM: Double
}

private struct MapTrackBatch: Encodable {
    let points: [MapTrackPoint]
}

private struct MapMarkerWrite: Encodable {
    let title: String
    let description: String
    let coordinate: CoordinateDTO
}

@MainActor
final class MapLocationRecordingStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var isRecording = false
    @Published private(set) var isBusy = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var completedRecording: MapRecordingDTO?
    @Published private(set) var recordedTrack: [CLLocationCoordinate2D] = []
    @Published var error: String?

    private let manager = CLLocationManager()
    private var session: APISession?
    private var recordingID: String?
    private var nextSequence = 1
    private var pendingPoints: [MapTrackPoint] = []
    private var flushTask: Task<Void, Never>?
    private var startWhenAuthorized = false
    private var locateWhenAuthorized = false
    private var isMapVisible = false
    private var locationErrorMessage: String?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
    }

    func connect(_ session: APISession) {
        self.session = session
    }

    func startObservingLocation() {
        isMapVisible = true
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            coordinate = nil
        @unknown default:
            break
        }
    }

    func stopObservingLocation() {
        isMapVisible = false
        if !isRecording { manager.stopUpdatingLocation() }
    }

    func locate() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locateWhenAuthorized = true
            manager.requestLocation()
        case .notDetermined:
            locateWhenAuthorized = true
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            error = "Разрешите доступ к геопозиции в настройках iPhone."
        @unknown default:
            error = "Не удалось получить геопозицию."
        }
    }

    func startRecording() {
        guard !isRecording && !isBusy else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            Task { await beginOnServer() }
        case .notDetermined:
            startWhenAuthorized = true
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            error = "Для записи маршрута разрешите геопозицию в настройках iPhone."
        @unknown default:
            error = "Не удалось получить доступ к геопозиции."
        }
    }

    private func beginOnServer() async {
        guard let session else { return }
        isBusy = true
        error = nil
        do {
            let recording: MapRecordingDTO = try await session.client.send(APIRequest(
                method: .post,
                path: "recordings",
                body: MapRecordingCreate(),
                idempotencyKey: UUID().uuidString
            ))
            recordingID = recording.id
            startedAt = recording.startedAt
            nextSequence = 1
            pendingPoints = []
            recordedTrack = []
            completedRecording = nil
            isRecording = true
            manager.startUpdatingLocation()
        } catch {
            self.error = error.localizedDescription
        }
        isBusy = false
    }

    func finishRecording() async {
        guard isRecording, let session, let recordingID, !isBusy else { return }
        isBusy = true
        manager.stopUpdatingLocation()
        if let flushTask { await flushTask.value }
        if !pendingPoints.isEmpty {
            scheduleFlush()
            if let flushTask { await flushTask.value }
        }
        guard pendingPoints.isEmpty else {
            error = "Точки ещё не отправлены. Проверьте соединение и попробуйте остановить запись снова."
            manager.startUpdatingLocation()
            isBusy = false
            return
        }
        do {
            let finished: MapRecordingDTO = try await session.client.send(APIRequest(
                method: .patch,
                path: "recordings/\(recordingID)",
                body: MapRecordingStatus(status: "finished")
            ))
            completedRecording = finished
            self.recordingID = nil
            isRecording = false
            startedAt = nil
            if isMapVisible { manager.startUpdatingLocation() }
        } catch {
            self.error = error.localizedDescription
            manager.startUpdatingLocation()
        }
        isBusy = false
    }

    func clearCompletedRecording() {
        completedRecording = nil
    }

    func addMarker(title: String, description: String, at coordinate: CLLocationCoordinate2D) async -> Bool {
        guard let session, let recordingID else { return false }
        do {
            let _: EmptyResponse = try await session.client.send(APIRequest(
                method: .post,
                path: "recordings/\(recordingID)/markers",
                body: MapMarkerWrite(title: title, description: description, coordinate: CoordinateDTO(coordinate))
            ))
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if isMapVisible { manager.startUpdatingLocation() }
            if locateWhenAuthorized { manager.requestLocation() }
            if startWhenAuthorized {
                startWhenAuthorized = false
                Task { await beginOnServer() }
            }
        case .denied, .restricted:
            manager.stopUpdatingLocation()
            coordinate = nil
            if locateWhenAuthorized || startWhenAuthorized {
                error = "Разрешите доступ к геопозиции в настройках iPhone."
            }
            locateWhenAuthorized = false
            startWhenAuthorized = false
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        if error == locationErrorMessage { error = nil }
        locationErrorMessage = nil
        coordinate = location.coordinate
        locateWhenAuthorized = false
        guard isRecording, location.horizontalAccuracy <= 100 else { return }
        pendingPoints.append(MapTrackPoint(
            sequence: nextSequence,
            coordinate: CoordinateDTO(location.coordinate),
            recordedAt: location.timestamp,
            accuracyM: location.horizontalAccuracy
        ))
        recordedTrack.append(location.coordinate)
        nextSequence += 1
        scheduleFlush()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .locationUnknown { return }
        locationErrorMessage = error.localizedDescription
        self.error = locationErrorMessage
    }

    private func scheduleFlush() {
        guard flushTask == nil, !pendingPoints.isEmpty, let session, let recordingID else { return }
        flushTask = Task { [weak self] in
            guard let self else { return }
            while !self.pendingPoints.isEmpty {
                let batch = Array(self.pendingPoints.prefix(100))
                do {
                    let _: EmptyResponse = try await session.client.send(APIRequest(
                        method: .post,
                        path: "recordings/\(recordingID)/track-points",
                        body: MapTrackBatch(points: batch),
                        idempotencyKey: UUID().uuidString
                    ))
                    self.pendingPoints.removeFirst(batch.count)
                } catch {
                    self.error = error.localizedDescription
                    break
                }
            }
            self.flushTask = nil
        }
    }
}
