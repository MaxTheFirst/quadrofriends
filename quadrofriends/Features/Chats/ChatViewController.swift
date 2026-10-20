import Combine
import SwiftUI
import UIKit

final class ChatViewController: UIViewController {
    /// Секция — день переписки, элемент — идентификатор сообщения.
    private typealias DataSource = UICollectionViewDiffableDataSource<String, ChatMessage.ID>
    private typealias Snapshot = NSDiffableDataSourceSnapshot<String, ChatMessage.ID>

    private static let todaySection = "Сегодня"

    private let chat: ChatPreview
    private let locationStore: ChatLocationSharingStore
    private let profileStore: ProfileStore
    private var messages = MockData.chatMessages
    private var cancellables = Set<AnyCancellable>()
    private var didScrollToBottomInitially = false

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: Self.makeLayout())
    private var dataSource: DataSource!

    private let topStack = UIStackView()
    private let bannerContainer = UIView()
    private let bannerView = ChatLocationBannerView()
    private let pendingContainer = UIView()
    private let inputBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let inputBar = ChatInputBar()
    private var locationBarButton: UIBarButtonItem!

    private var canStartSharing: Bool {
        !locationStore.isSharing(in: chat.id) && !locationStore.pendingChatIDs.contains(chat.id)
    }

    init(chat: ChatPreview, locationStore: ChatLocationSharingStore, profileStore: ProfileStore) {
        self.chat = chat
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
        title = chat.title
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .warmBackground

        configureNavigationItems()
        configureCollectionView()
        configureTopStack()
        configureInputBar()
        configureDataSource()
        applyInitialSnapshot()
        updateLocationState()

        locationStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateLocationState() }
            .store(in: &cancellables)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showLocationErrorIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCollectionInsets()

        if !didScrollToBottomInitially, collectionView.bounds.height > 0 {
            didScrollToBottomInitially = true
            collectionView.layoutIfNeeded()
            scrollToBottom(animated: false)
        }
    }

    // MARK: - Настройка

    private func configureNavigationItems() {
        locationBarButton = UIBarButtonItem(
            title: "Поделиться геопозицией",
            image: UIImage(systemName: "location.circle"),
            primaryAction: UIAction { [weak self] _ in self?.presentLocationConsent() },
            menu: nil
        )
        let profileBarButton = UIBarButtonItem(
            title: "Профиль участника",
            image: UIImage(systemName: "person.crop.circle"),
            primaryAction: UIAction { [weak self] _ in self?.openMemberProfile() },
            menu: nil
        )
        // В UIKit правые кнопки перечисляются справа налево.
        navigationItem.rightBarButtonItems = [profileBarButton, locationBarButton]
    }

    private static func makeLayout() -> UICollectionViewLayout {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(60))
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 12
        section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 16, bottom: 16, trailing: 16)

        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(28)),
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
        header.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0)
        section.boundarySupplementaryItems = [header]

        return UICollectionViewCompositionalLayout(section: section)
    }

    private func configureCollectionView() {
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.allowsSelection = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// Баннер геопозиции и статус «Определяем местоположение» над списком сообщений.
    private func configureTopStack() {
        bannerContainer.backgroundColor = .warmBackground
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        bannerContainer.addSubview(bannerView)
        bannerView.onOpenMap = { [weak self] in self?.presentLocationMap() }
        bannerView.onStopSharing = { [weak self] in
            guard let self else { return }
            self.locationStore.stopSharing(in: self.chat.id)
        }

        let pendingIcon = UIImageView(image: UIImage(systemName: "location"))
        pendingIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .subheadline)
        pendingIcon.tintColor = .brandOlive
        let pendingLabel = UILabel(textStyle: .subheadline)
        pendingLabel.text = "Определяем ваше местоположение…"
        pendingLabel.numberOfLines = 0
        let pendingStack = UIStackView(arrangedSubviews: [pendingIcon, pendingLabel])
        pendingStack.spacing = 6
        pendingStack.alignment = .center
        pendingStack.translatesAutoresizingMaskIntoConstraints = false
        pendingContainer.backgroundColor = .warmBackground
        pendingContainer.addSubview(pendingStack)

        topStack.axis = .vertical
        topStack.addArrangedSubview(bannerContainer)
        topStack.addArrangedSubview(pendingContainer)
        topStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topStack)

        NSLayoutConstraint.activate([
            bannerView.topAnchor.constraint(equalTo: bannerContainer.topAnchor, constant: 8),
            bannerView.leadingAnchor.constraint(equalTo: bannerContainer.layoutMarginsGuide.leadingAnchor),
            bannerView.trailingAnchor.constraint(equalTo: bannerContainer.layoutMarginsGuide.trailingAnchor),
            bannerView.bottomAnchor.constraint(equalTo: bannerContainer.bottomAnchor, constant: -8),

            pendingStack.topAnchor.constraint(equalTo: pendingContainer.topAnchor, constant: 14),
            pendingStack.bottomAnchor.constraint(equalTo: pendingContainer.bottomAnchor, constant: -14),
            pendingStack.centerXAnchor.constraint(equalTo: pendingContainer.centerXAnchor),
            pendingStack.leadingAnchor.constraint(greaterThanOrEqualTo: pendingContainer.layoutMarginsGuide.leadingAnchor),

            topStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topStack.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func configureInputBar() {
        inputBar.onSend = { [weak self] text in self?.send(text) }
        inputBar.attachmentMenu = makeAttachmentMenu()

        inputBackground.translatesAutoresizingMaskIntoConstraints = false
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputBackground)
        view.addSubview(inputBar)

        NSLayoutConstraint.activate([
            inputBackground.topAnchor.constraint(equalTo: inputBar.topAnchor, constant: -9),
            inputBackground.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBackground.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBackground.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            inputBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            inputBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            // Поднимается вместе с клавиатурой, а без неё стоит над safe area.
            inputBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -9)
        ])
    }

    private func makeAttachmentMenu() -> UIMenu {
        // Пункты собираются при каждом открытии, чтобы доступность геопозиции была актуальной.
        let items = UIDeferredMenuElement.uncached { [weak self] completion in
            let shareLocation = UIAction(
                title: "Поделиться геопозицией",
                image: UIImage(systemName: "location.fill")
            ) { [weak self] _ in
                self?.presentLocationConsent()
            }
            if self?.canStartSharing != true {
                shareLocation.attributes = .disabled
            }
            completion([
                shareLocation,
                UIAction(title: "Поделиться маршрутом", image: UIImage(systemName: "map")) { _ in },
                UIAction(title: "Добавить фото", image: UIImage(systemName: "photo")) { _ in }
            ])
        }
        return UIMenu(children: [items])
    }

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<ChatMessageCell, ChatMessage.ID> { [weak self] cell, _, messageID in
            guard let message = self?.messages.first(where: { $0.id == messageID }) else { return }
            cell.configure(with: message)
        }
        let headerRegistration = UICollectionView.SupplementaryRegistration<ChatDayHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            header.title = self?.dataSource.sectionIdentifier(for: indexPath.section)
        }

        dataSource = DataSource(collectionView: collectionView) { collectionView, indexPath, messageID in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: messageID)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    // MARK: - Сообщения

    private func applyInitialSnapshot() {
        var snapshot = Snapshot()
        snapshot.appendSections([Self.todaySection])
        snapshot.appendItems(messages.map(\.id), toSection: Self.todaySection)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func send(_ text: String) {
        let message = ChatMessage(author: "Вы", isMine: true, time: "Сейчас", kind: .text(text))
        messages.append(message)

        var snapshot = dataSource.snapshot()
        snapshot.appendItems([message.id], toSection: Self.todaySection)
        dataSource.apply(snapshot, animatingDifferences: true) { [weak self] in
            self?.scrollToBottom(animated: true)
        }
    }

    // MARK: - Прокрутка и отступы

    private var isScrolledToBottom: Bool {
        let maxOffset = collectionView.contentSize.height - collectionView.bounds.height
            + collectionView.adjustedContentInset.bottom
        return collectionView.contentOffset.y >= maxOffset - 24
    }

    /// Освобождает место под баннером сверху и под панелью ввода (и клавиатурой) снизу.
    private func updateCollectionInsets() {
        let top = topStack.isHidden ? 0 : topStack.frame.height
        let bottom = max(0, view.bounds.height - inputBackground.frame.minY - view.safeAreaInsets.bottom)
        let insets = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
        guard collectionView.contentInset != insets else { return }

        let shouldStickToBottom = didScrollToBottomInitially && isScrolledToBottom
        collectionView.contentInset = insets
        collectionView.verticalScrollIndicatorInsets = insets
        if shouldStickToBottom {
            scrollToBottom(animated: false)
        }
    }

    private func scrollToBottom(animated: Bool) {
        guard let lastID = dataSource.snapshot().itemIdentifiers.last,
              let indexPath = dataSource.indexPath(for: lastID) else { return }
        collectionView.scrollToItem(at: indexPath, at: .bottom, animated: animated)
    }

    // MARK: - Геопозиция

    private func updateLocationState() {
        let shares = locationStore.shares(in: chat.id)
        let isPending = locationStore.pendingChatIDs.contains(chat.id)

        locationBarButton.isEnabled = canStartSharing
        if !shares.isEmpty {
            bannerView.configure(shares: shares)
        }
        bannerContainer.isHidden = shares.isEmpty
        pendingContainer.isHidden = !shares.isEmpty || !isPending
        topStack.isHidden = bannerContainer.isHidden && pendingContainer.isHidden
        view.setNeedsLayout()

        showLocationErrorIfNeeded()
    }

    private func presentLocationConsent() {
        guard canStartSharing else { return }
        let consentView = ChatLocationConsentView(chatTitle: chat.title) { [weak self] in
            guard let self else { return }
            self.locationStore.startSharing(in: self.chat.id, profile: self.profileStore.profile)
        }
        let controller = UIHostingController(rootView: consentView.tint(Color.brandOlive))
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.custom(identifier: .init("locationConsent")) { _ in 520 }, .large()]
        }
        present(controller, animated: true)
    }

    private func presentLocationMap() {
        let mapView = NavigationStack {
            ChatLiveLocationMapView(chatTitle: chat.title, shares: locationStore.shares(in: chat.id))
        }
        present(UIHostingController(rootView: mapView.tint(Color.brandOlive)), animated: true)
    }

    private func openMemberProfile() {
        navigationController?.pushViewController(UIHostingController(rootView: MemberProfileView()), animated: true)
    }

    private func showLocationErrorIfNeeded() {
        guard locationStore.showingError, viewIfLoaded?.window != nil else { return }

        if let presented = presentedViewController {
            // Ошибка могла прийти, пока закрывается окно согласия: покажем её после анимации.
            if presented.isBeingDismissed, let coordinator = presented.transitionCoordinator {
                coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                    self?.showLocationErrorIfNeeded()
                }
            }
            return
        }

        let alert = UIAlertController(title: "Геопозиция", message: locationStore.errorMessage, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Понятно", style: .cancel) { [weak self] _ in
            self?.locationStore.showingError = false
        })
        present(alert, animated: true)
    }
}
