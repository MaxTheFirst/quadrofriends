import Foundation
import UIKit

struct AccountProfileUpdate: Encodable {
    let firstName: String
    let lastName: String
    let username: String
    let birthYear: Int?
    let city: String
    let avatarMediaId: String?
}

struct AccountVehicleWrite: Encodable {
    let model: String
    let year: Int
    let imageMediaId: String?
    let isPrimary: Bool
}

@MainActor
protocol AccountEditingDataSource {
    func saveProfile(_ profile: AccountProfileUpdate, avatar: UIImage?) async throws
    func deleteVehicle(id: String) async throws
    func saveVehicle(_ vehicle: AccountVehicleWrite, id: String?, image: UIImage?) async throws -> AccountVehicleDTO
}

@MainActor
final class RemoteAccountEditingDataSource: AccountEditingDataSource {
    private let session: APISession

    init(session: APISession) { self.session = session }

    func saveProfile(_ profile: AccountProfileUpdate, avatar: UIImage?) async throws {
        var mediaID: String?
        if let avatar { mediaID = try await session.client.uploadImage(avatar).id }
        let request = AccountProfileUpdate(
            firstName: profile.firstName,
            lastName: profile.lastName,
            username: profile.username,
            birthYear: profile.birthYear,
            city: profile.city,
            avatarMediaId: mediaID
        )
        let _: AccountProfileDTO = try await session.client.send(APIRequest(
            method: .patch, path: "users/me", body: request
        ))
    }

    func deleteVehicle(id: String) async throws {
        let _: EmptyResponse = try await session.client.send(APIRequest(
            method: .delete, path: "users/me/vehicles/\(id)"
        ))
    }

    func saveVehicle(_ vehicle: AccountVehicleWrite, id: String?, image: UIImage?) async throws -> AccountVehicleDTO {
        var mediaID: String?
        if let image { mediaID = try await session.client.uploadImage(image).id }
        let request = AccountVehicleWrite(
            model: vehicle.model,
            year: vehicle.year,
            imageMediaId: mediaID ?? vehicle.imageMediaId,
            isPrimary: vehicle.isPrimary
        )
        return try await session.client.send(APIRequest(
            method: id == nil ? .post : .patch,
            path: id.map { "users/me/vehicles/\($0)" } ?? "users/me/vehicles",
            body: request
        ))
    }
}

@MainActor
final class AccountEditingViewModel {
    func saveProfile(_ profile: AccountProfileUpdate, avatar: UIImage?, using dataSource: any AccountEditingDataSource) async throws {
        try await dataSource.saveProfile(profile, avatar: avatar)
    }

    func deleteVehicle(id: String, using dataSource: any AccountEditingDataSource) async throws {
        try await dataSource.deleteVehicle(id: id)
    }

    func saveVehicle(_ vehicle: AccountVehicleWrite, id: String?, image: UIImage?, using dataSource: any AccountEditingDataSource) async throws -> AccountVehicleDTO {
        try await dataSource.saveVehicle(vehicle, id: id, image: image)
    }
}
