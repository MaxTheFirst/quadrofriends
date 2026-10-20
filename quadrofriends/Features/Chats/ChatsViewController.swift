import Combine
import SwiftUI
import UIKit

/// Вкладка «Чаты»: UIKit-навигация внутри SwiftUI `TabView`.
struct ChatsTab: View {
    @EnvironmentObject private var locationStore: ChatLocationSharingStore
    @EnvironmentObject private var profileStore: ProfileStore

    var body: some View {
        ChatsNavigationView(locationStore: locationStore, profileStore: profileStore)
            .ignoresSafeArea()
    }
}

private struct ChatsNavigationView: UIViewControllerRepresentable {
    let locationStore: ChatLocationSharingStore
    let profileStore: ProfileStore

    func makeUIViewController(context: Context) -> UINavigationController {
        let chatsController = ChatsViewController(locationStore: locationStore, profileStore: profileStore)
        let navigationController = UINavigationController(rootViewController: chatsController)
        navigationController.view.tintColor = .brandOlive
        return navigationController
    }

    func updateUIViewController(_ navigationController: UINavigationController, context: Context) { }
}

final class ChatsViewController: UIViewController {
    private enum Section {
        case main
    }

    private let locationStore: ChatLocationSharingStore
    private let profileStore: ProfileStore
    private let chats = MockData.chats
    private var query = ""
    private var cancellables = Set<AnyCancellable>()

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, ChatPreview.ID>!

    private var filteredChats: [ChatPreview] {
        guard !query.isEmpty else { return chats }
        return chats.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    init(locationStore: ChatLocationSharingStore, profileStore: ProfileStore) {
        self.locationStore = locationStore
        self.profileStore = profileStore
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
        applySnapshot(animated: false)

        locationStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reconfigureVisibleChats() }
            .store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        deselectSelectedChat(animated: animated)
    }

    override func updateContentUnavailableConfiguration(using state: UIContentUnavailableConfigurationState) {
        guard !query.isEmpty, filteredChats.isEmpty else {
            contentUnavailableConfiguration = nil
            return
        }
        var configuration = UIContentUnavailableConfiguration.search()
        configuration.text = "Ничего не найдено"
        configuration.secondaryText = "Попробуйте изменить запрос"
        contentUnavailableConfiguration = configuration
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
    }

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<ChatListCell, ChatPreview.ID> { [weak self] cell, _, chatID in
            guard let self, let chat = self.chat(with: chatID) else { return }
            cell.configure(with: chat, sharesLocation: !self.locationStore.shares(in: chat.id).isEmpty)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, chatID in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: chatID)
        }
    }

    // MARK: - Данные

    private func chat(with id: ChatPreview.ID) -> ChatPreview? {
        chats.first { $0.id == id }
    }

    private func applySnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, ChatPreview.ID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(filteredChats.map(\.id))
        dataSource.apply(snapshot, animatingDifferences: animated)
        setNeedsUpdateContentUnavailableConfiguration()
    }

    /// Обновляет значки геопозиции без пересоздания ячеек.
    private func reconfigureVisibleChats() {
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: - Навигация

    private func presentNewChat() {
        let controller = UIHostingController(
            rootView: NavigationStack { NewChatView() }
                .tint(Color.brandOlive)
        )
        present(controller, animated: true)
    }

    private func openChat(_ chat: ChatPreview) {
        let controller = ChatViewController(chat: chat, locationStore: locationStore, profileStore: profileStore)
        navigationController?.pushViewController(controller, animated: true)
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
        guard let chatID = dataSource.itemIdentifier(for: indexPath), let chat = chat(with: chatID) else { return }
        openChat(chat)
    }
}

extension ChatsViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let newQuery = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard newQuery != query else { return }
        query = newQuery
        applySnapshot(animated: true)
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
        avatarView.configure(imageName: chat.avatarImage, initials: chat.initials)
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

        let avatarContainer = UIView()
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarBadge.translatesAutoresizingMaskIntoConstraints = false
        avatarContainer.addSubview(avatarView)
        avatarContainer.addSubview(avatarBadge)

        subtitleIcon.image = UIImage(systemName: "location.fill")
        subtitleIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .caption2)
        subtitleIcon.tintColor = .brandOlive
        subtitleIcon.setContentHuggingPriority(.required, for: .horizontal)
        subtitleLabel.numberOfLines = 2

        let subtitleRow = UIStackView(arrangedSubviews: [subtitleIcon, subtitleLabel])
        subtitleRow.spacing = 4
        subtitleRow.alignment = .firstBaseline

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleRow])
        textStack.axis = .vertical
        textStack.spacing = 5
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let trailingStack = UIStackView(arrangedSubviews: [timeLabel, unreadBadge])
        trailingStack.axis = .vertical
        trailingStack.alignment = .trailing
        trailingStack.spacing = 8

        let rowStack = UIStackView(arrangedSubviews: [avatarContainer, textStack, trailingStack])
        rowStack.spacing = 12
        rowStack.alignment = .center
        rowStack.setCustomSpacing(16, after: textStack)
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rowStack)

        let margins = contentView.layoutMarginsGuide
        let bottomConstraint = rowStack.bottomAnchor.constraint(equalTo: margins.bottomAnchor, constant: -6)
        bottomConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: avatarContainer.topAnchor),
            avatarView.leadingAnchor.constraint(equalTo: avatarContainer.leadingAnchor),
            avatarView.trailingAnchor.constraint(equalTo: avatarContainer.trailingAnchor),
            avatarView.bottomAnchor.constraint(equalTo: avatarContainer.bottomAnchor),
            avatarBadge.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 2),
            avatarBadge.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 2),

            rowStack.topAnchor.constraint(equalTo: margins.topAnchor, constant: 6),
            rowStack.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            bottomConstraint
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
