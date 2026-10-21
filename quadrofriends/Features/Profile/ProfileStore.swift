import Combine

@MainActor
final class ProfileStore: ObservableObject {
    @Published var profile: UserProfile {
        didSet { dataSource.saveProfile(profile) }
    }

    private let dataSource: any DemoProfileDataSource

    init(dataSource: (any DemoProfileDataSource)? = nil) {
        let source = dataSource ?? DemoRepository.shared
        self.dataSource = source
        profile = source.profile()
    }
}
