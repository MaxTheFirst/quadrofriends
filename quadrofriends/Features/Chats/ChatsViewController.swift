import Combine
import SwiftUI
import UIKit

/// Вкладка «Чаты»: UIKit-навигация внутри SwiftUI `TabView`.
struct ChatsTab: View {
    @EnvironmentObject private var locationStore: ChatLocationSharingStore
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var apiSession: APISession
    @EnvironmentObject private var realtime: RealtimeClient
    @AppStorage("sessionKind") private var sessionKind = "none"

    var body: some View {
        ChatsNavigationView(
            isDemo: sessionKind == "demo",
            apiSession: apiSession,
            realtime: realtime,
            locationStore: locationStore,
            profileStore: profileStore
        )
        // При смене режима экран создаётся заново с другим источником данных.
        .id(sessionKind)
        .ignoresSafeArea()
    }
}

private struct ChatsNavigationView: UIViewControllerRepresentable {
    let isDemo: Bool
    let apiSession: APISession
    let realtime: RealtimeClient
    let locationStore: ChatLocationSharingStore
    let profileStore: ProfileStore

    func makeUIViewController(context: Context) -> UINavigationController {
        let repository: any ChatsRepository = isDemo
            ? DemoChatsRepository()
            : RemoteChatsRepository(session: apiSession, realtime: realtime)
        let chatsController = ChatsViewController(
            repository: repository,
            locationStore: locationStore,
            profileStore: profileStore,
            apiSession: isDemo ? nil : apiSession
        )
        let navigationController = UINavigationController(rootViewController: chatsController)
        navigationController.view.tintColor = .brandOlive
        return navigationController
    }

    func updateUIViewController(_ navigationController: UINavigationController, context: Context) { }
}

final class ChatsViewController: UIViewController {
    private enum LoadState {
        case idle
        case loading
        case failed(String)
    }

    private static let searchDebounce: Duration = .milliseconds(350)
    private static let prefetchDistance = 5

    private let repository: any ChatsRepository
    private let locationStore: ChatLocationSharingStore
    private let profileStore: ProfileStore
    private let apiSession: APISession?
    private var cancellables = Set<AnyCancellable>()

    private var chats: [ChatPreview] = []
    private var foundUsers: [UserSummaryDTO] = []
    /// Данные, по которым настроены ячейки: нужны, чтобы перенастраивать только изменившиеся.
    private var renderedChats: [ChatPreview.ID: ChatPreview] = [:]
    private var nextCursor: String?
    private var query = ""
    private var loadState = LoadState.idle
    private var reloadTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Int, ChatPreview.ID>!

    init(repository: any ChatsRepository, locationStore: ChatLocationSharingStore, profileStore: ProfileStore, apiSession: APISession?) {
        self.repository = repository
        self.locationStore = locationStore
        self.profileStore = profileStore
        self.apiSession = apiSession
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Чаты"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .warmBackground

        configureNavigationItem()
        configureCollectionView()
        configureDataSource()
        reload()

        locationStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reconfigureAllChats() }
            .store(in: &cancellables)
        repository.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        deselectSelectedChat(animated: animated)
    }

    override func updateContentUnavailableConfiguration(using state: UIContentUnavailableConfigurationState) {
        guard chats.isEmpty && foundUsers.isEmpty else {
            contentUnavailableConfiguration = nil
            return
        }

        switch loadState {
        case .loading:
            contentUnavailableConfiguration = UIContentUnavailableConfiguration.loading()
        case .failed(let message):
            var configuration = UIContentUnavailableConfiguration.empty()
            configuration.image = UIImage(systemName: "wifi.exclamationmark")
            configuration.text = "Не удалось загрузить чаты"
            configuration.secondaryText = message
            var button = UIButton.Configuration.borderedProminent()
            button.title = "Повторить"
            configuration.button = button
            configuration.buttonProperties.primaryAction = UIAction { [weak self] _ in self?.reload() }
            contentUnavailableConfiguration = configuration
        case .idle where !query.isEmpty:
            var configuration = UIContentUnavailableConfiguration.search()
            configuration.text = "Ничего не найдено"
            configuration.secondaryText = "Попробуйте изменить запрос"
            contentUnavailableConfiguration = configuration
        case .idle:
            var configuration = UIContentUnavailableConfiguration.empty()
            configuration.image = UIImage(systemName: "bubble.left.and.bubble.right")
            configuration.text = "Пока нет чатов"
            configuration.secondaryText = "Напишите первым — кнопка справа вверху"
            contentUnavailableConfiguration = configuration
        }
    }

    // MARK: - Настройка

    private func configureNavigationItem() {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Поиск по чатам и пользователям"
        navigationItem.searchController = searchController
        definesPresentationContext = true

        let composeItem = UIBarButtonItem(
            title: "Новое сообщение",
            image: UIImage(systemName: "square.and.pencil"),
            primaryAction: UIAction { [weak self] _ in self?.presentNewChat() },
            menu: nil
        )
        navigationItem.rightBarButtonItem = composeItem
    }

    private func makeLayout() -> UICollectionViewLayout {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.showsSeparators = false
        configuration.backgroundColor = .warmBackground
        return UICollectionViewCompositionalLayout.list(using: configuration)
    }

    private func configureCollectionView() {
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        if repository.isRemote {
            let refreshControl = UIRefreshControl()
            refreshControl.addAction(UIAction { [weak self] _ in self?.reload() }, for: .valueChanged)
            collectionView.refreshControl = refreshControl
        }
    }

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<ChatListCell, ChatPreview.ID> { [weak self] cell, _, chatID in
            guard let self, let chat = self.renderedChats[chatID] else { return }
            let sharesLocation = chat.sharesLocation || !self.locationStore.shares(in: chat.id).isEmpty
            cell.configure(with: chat, sharesLocation: sharesLocation)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, chatID in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: chatID)
        }
    }

    // MARK: - Загрузка

    /// Первая страница: при открытии, поиске, pull-to-refresh и после переподключения.
    private func reload(debounced: Bool = false) {
        reloadTask?.cancel()
        loadMoreTask?.cancel()
        loadMoreTask = nil
        if chats.isEmpty {
            loadState = .loading
            setNeedsUpdateContentUnavailableConfiguration()
        }

        let query = query
        reloadTask = Task { [weak self] in
            if debounced {
                try? await Task.sleep(for: Self.searchDebounce)
            }
            guard let self, !Task.isCancelled else { return }
            do {
                let page = try await self.repository.chats(query: query, cursor: nil)
                var users: [UserSummaryDTO] = []
                if let session = self.apiSession, !query.isEmpty {
                    let normalized = query.replacingOccurrences(of: "^@", with: "", options: .regularExpression)
                    let people: Page<UserSummaryDTO> = try await session.client.send(APIRequest(
                        method: .get,
                        path: "users",
                        query: [URLQueryItem(name: "query", value: normalized), URLQueryItem(name: "limit", value: "30")]
                    ))
                    users = people.items.filter { $0.id != session.currentUserID }
                }
                guard !Task.isCancelled else { return }
                self.chats = Self.uniqued(page.items)
                self.foundUsers = users
                self.nextCursor = page.nextCursor
                self.loadState = .idle
            } catch {
                guard !Task.isCancelled else { return }
                self.loadState = .failed(error.localizedDescription)
                if !self.chats.isEmpty {
                    self.presentError(error)
                }
            }
            self.collectionView.refreshControl?.endRefreshing()
            self.applySnapshot(animated: true)
        }
    }

    private func loadMoreIfNeeded(at indexPath: IndexPath) {
        guard indexPath.item < chats.count,
              indexPath.item >= chats.count - Self.prefetchDistance,
              let cursor = nextCursor, loadMoreTask == nil else { return }

        let query = query
        loadMoreTask = Task { [weak self] in
            guard let self else { return }
            defer { self.loadMoreTask = nil }
            guard let page = try? await self.repository.chats(query: query, cursor: cursor),
                  !Task.isCancelled else { return }
            self.chats = Self.uniqued(self.chats + page.items)
            self.nextCursor = page.nextCursor
            self.applySnapshot(animated: false)
        }
    }

    // MARK: - События

    private func handle(_ event: ChatEvent) {
        switch event {
        case .chatUpdated(let chat):
            if let index = chats.firstIndex(where: { $0.id == chat.id }) {
                chats.remove(at: index)
                chats.insert(chat, at: 0)
            } else if query.isEmpty {
                chats.insert(chat, at: 0)
            }
            applySnapshot(animated: true)

        case .messageCreated(let message, let chatID):
            guard let index = chats.firstIndex(where: { $0.id == chatID }) else {
                // Сообщение в чате, которого ещё нет в списке, — например, новый чат.
                if query.isEmpty { reload() }
                return
            }
            var chat = chats.remove(at: index)
            let text = Self.previewText(for: message)
            chat.subtitle = message.isMine ? "Вы: \(text)" : text
            chat.time = ChatDateFormatting.listTime(message.sentAt)
            if !message.isMine && openedChatID != chatID {
                chat.unread += 1
            }
            chats.insert(chat, at: 0)
            applySnapshot(animated: true)

        case .resync:
            reload()

        case .messageDeleted, .readStateUpdated:
            break
        }
    }

    private func markChatRead(_ chatID: String) {
        guard let index = chats.firstIndex(where: { $0.id == chatID }), chats[index].unread > 0 else { return }
        chats[index].unread = 0
        applySnapshot(animated: false)
    }

    // MARK: - Снимок

    private func applySnapshot(animated: Bool) {
        let userPreviews = foundUsers.map { user in
            ChatPreview(
                id: "user:\(user.id)",
                title: user.displayName,
                subtitle: "@\(user.username) · Начать чат",
                time: "",
                unread: 0,
                avatarImage: nil,
                initials: user.initials,
                avatarURL: user.avatar?.thumbnailUrl
            )
        }
        let displayed = chats + userPreviews
        var snapshot = NSDiffableDataSourceSnapshot<Int, ChatPreview.ID>()
        snapshot.appendSections([0])
        snapshot.appendItems(displayed.map(\.id))

        let changedIDs = displayed.compactMap { chat -> ChatPreview.ID? in
            guard let rendered = renderedChats[chat.id], rendered != chat else { return nil }
            return chat.id
        }
        snapshot.reconfigureItems(changedIDs)
        renderedChats = Dictionary(displayed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        dataSource.apply(snapshot, animatingDifferences: animated)
        setNeedsUpdateContentUnavailableConfiguration()
    }

    /// Обновляет значки геопозиции без пересоздания ячеек.
    private func reconfigureAllChats() {
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private static func uniqued(_ chats: [ChatPreview]) -> [ChatPreview] {
        var seen = Set<ChatPreview.ID>()
        return chats.filter { seen.insert($0.id).inserted }
    }

    private static func previewText(for message: ChatMessage) -> String {
        switch message.kind {
        case .text(let text): return text
        case .photo: return "Фото"
        case .location: return "Геопозиция"
        }
    }

    // MARK: - Навигация

    private var openedChatID: String? {
        (navigationController?.topViewController as? ChatViewController)?.chatID
    }

    private func presentNewChat() {
        let controller = UIHostingController(
            rootView: NavigationStack {
                NewChatView(session: apiSession) { [weak self] chat in
                    self?.dismiss(animated: true) { [weak self] in
                        self?.navigationItem.searchController?.searchBar.text = ""
                        self?.reload()
                        self?.openChat(chat)
                    }
                }
            }
                .tint(Color.brandOlive)
        )
        present(controller, animated: true)
    }

    private func openChat(_ chat: ChatPreview) {
        let controller = ChatViewController(
            chat: chat,
            repository: repository,
            locationStore: locationStore,
            profileStore: profileStore
        )
        controller.onRead = { [weak self] chatID in self?.markChatRead(chatID) }
        navigationController?.pushViewController(controller, animated: true)
    }

    private func startDirectChat(with user: UserSummaryDTO) {
        guard let apiSession else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let chat: ChatSummaryDTO = try await apiSession.client.send(APIRequest(
                    method: .post,
                    path: "chats",
                    body: ChatCreateRequest(kind: "direct", participantUserIds: [user.id], title: nil),
                    idempotencyKey: UUID().uuidString
                ))
                self.navigationItem.searchController?.searchBar.text = ""
                self.reload()
                self.openChat(ChatPreview(
                    id: chat.id,
                    title: chat.title,
                    subtitle: "Нет сообщений",
                    time: "Сейчас",
                    unread: chat.unreadCount,
                    avatarImage: nil,
                    initials: user.initials,
                    avatarURL: chat.avatar?.thumbnailUrl,
                    sharesLocation: chat.sharesLocation
                ))
            } catch {
                self.presentError(error)
            }
        }
    }

    private func presentError(_ error: Error) {
        let alert = UIAlertController(title: "Чаты", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Понятно", style: .cancel))
        present(alert, animated: true)
    }

    private func deselectSelectedChat(animated: Bool) {
        guard let indexPath = collectionView.indexPathsForSelectedItems?.first else { return }
        guard let coordinator = transitionCoordinator else {
            collectionView.deselectItem(at: indexPath, animated: animated)
            return
        }
        coordinator.animate { [weak self] _ in
            self?.collectionView.deselectItem(at: indexPath, animated: true)
        } completion: { [weak self] context in
            if context.isCancelled {
                self?.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
            }
        }
    }
}

extension ChatsViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let chatID = dataSource.itemIdentifier(for: indexPath), let chat = renderedChats[chatID] else { return }
        if let user = foundUsers.first(where: { "user:\($0.id)" == chatID }) {
            startDirectChat(with: user)
        } else {
            openChat(chat)
        }
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        loadMoreIfNeeded(at: indexPath)
    }
}

extension ChatsViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let newQuery = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard newQuery != query else { return }
        query = newQuery
        reload(debounced: repository.isRemote)
    }
}

// MARK: - Ячейка чата

private final class ChatListCell: UICollectionViewListCell {
    private let avatarView = ChatAvatarView(size: 54)
    private let avatarBadge = LocationBadgeView()
    private let titleLabel = UILabel(textStyle: .headline)
    private let subtitleIcon = UIImageView()
    private let subtitleLabel = UILabel(textStyle: .subheadline, color: .secondaryLabel)
    private let timeLabel = UILabel(textStyle: .caption2, color: .secondaryLabel)
    private let unreadBadge = UnreadBadgeView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessories = [.disclosureIndicator()]
        configureLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with chat: ChatPreview, sharesLocation: Bool) {
        avatarView.configure(imageName: chat.avatarImage, imageURL: chat.avatarURL, initials: chat.initials)
        avatarBadge.isHidden = !sharesLocation
        titleLabel.text = chat.title
        subtitleIcon.isHidden = !sharesLocation
        subtitleLabel.text = chat.subtitle
        timeLabel.text = chat.time
        unreadBadge.count = chat.unread

        var accessibilityParts = [chat.title, chat.subtitle, chat.time]
        if sharesLocation { accessibilityParts.append("делится геопозицией") }
        if chat.unread > 0 { accessibilityParts.append("непрочитанных: \(chat.unread)") }
        accessibilityLabel = accessibilityParts.joined(separator: ", ")
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        super.updateConfiguration(using: state)
        var background = UIBackgroundConfiguration.listCell().updated(for: state)
        if !state.isHighlighted && !state.isSelected {
            background.backgroundColor = .warmBackground
        }
        backgroundConfiguration = background
    }

    private func configureLayout() {
        isAccessibilityElement = true
        accessibilityTraits = .button
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 12)

        let avatarContainer = UIView()
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarBadge.translatesAutoresizingMaskIntoConstraints = false
        avatarContainer.addSubview(avatarView)
        avatarContainer.addSubview(avatarBadge)

        subtitleIcon.image = UIImage(systemName: "location.fill")
        subtitleIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .caption2)
        subtitleIcon.tintColor = .brandOlive
        subtitleIcon.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail

        let subtitleRow = UIStackView(arrangedSubviews: [subtitleIcon, subtitleLabel])
        subtitleRow.spacing = 4
        subtitleRow.alignment = .center

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleRow])
        textStack.axis = .vertical
        textStack.spacing = 3
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        subtitleRow.setContentCompressionResistancePriority(.required, for: .vertical)

        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let trailingStack = UIStackView(arrangedSubviews: [timeLabel, unreadBadge])
        trailingStack.axis = .vertical
        trailingStack.alignment = .trailing
        trailingStack.spacing = 8

        let rowStack = UIStackView(arrangedSubviews: [avatarContainer, textStack, trailingStack])
        rowStack.spacing = 12
        rowStack.alignment = .center
        rowStack.setCustomSpacing(8, after: textStack)
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rowStack)

        let margins = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: avatarContainer.topAnchor),
            avatarView.leadingAnchor.constraint(equalTo: avatarContainer.leadingAnchor),
            avatarView.trailingAnchor.constraint(equalTo: avatarContainer.trailingAnchor),
            avatarView.bottomAnchor.constraint(equalTo: avatarContainer.bottomAnchor),
            avatarBadge.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 2),
            avatarBadge.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 2),

            avatarContainer.widthAnchor.constraint(equalToConstant: 54),
            avatarContainer.heightAnchor.constraint(equalToConstant: 54),
            rowStack.topAnchor.constraint(equalTo: margins.topAnchor),
            rowStack.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            rowStack.bottomAnchor.constraint(equalTo: margins.bottomAnchor)
        ])
    }
}

/// Оливковый кружок с иконкой геопозиции и обводкой цвета фона.
private final class LocationBadgeView: UIView {
    private static let outerSize: CGFloat = 24
    private static let borderWidth: CGFloat = 2

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .warmBackground
        layer.cornerRadius = Self.outerSize / 2

        let innerView = UIView()
        innerView.backgroundColor = .brandOlive
        innerView.layer.cornerRadius = Self.outerSize / 2 - Self.borderWidth

        let iconView = UIImageView(image: UIImage(systemName: "location.fill"))
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        iconView.tintColor = .white

        for subview in [innerView, iconView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.outerSize),
            heightAnchor.constraint(equalToConstant: Self.outerSize),
            innerView.topAnchor.constraint(equalTo: topAnchor, constant: Self.borderWidth),
            innerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.borderWidth),
            innerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.borderWidth),
            innerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.borderWidth),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Счётчик непрочитанных: круг для одной цифры, капсула для нескольких.
private final class UnreadBadgeView: UIView {
    private static let height: CGFloat = 20
    private let label = UILabel(textStyle: .caption2, weight: .bold, color: .white)

    var count = 0 {
        didSet {
            label.text = "\(count)"
            isHidden = count == 0
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .brandOlive
        layer.cornerRadius = Self.height / 2
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            widthAnchor.constraint(greaterThanOrEqualToConstant: Self.height),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
