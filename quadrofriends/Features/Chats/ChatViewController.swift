import Combine
import SwiftUI
import UIKit

final class ChatViewController: UIViewController {
    /// Секция — начало дня переписки, элемент — идентификатор сообщения.
    private typealias DataSource = UICollectionViewDiffableDataSource<Date, ChatMessage.ID>
    private typealias Snapshot = NSDiffableDataSourceSnapshot<Date, ChatMessage.ID>

    private enum LoadState {
        case idle
        case loading
        case failed(String)
    }

    /// Расстояние до верха ленты, с которого подгружается более ранняя история.
    private static let olderMessagesThreshold: CGFloat = 400

    /// Вызывается, когда последние сообщения прочитаны: список чатов сбрасывает счётчик.
    var onRead: ((String) -> Void)?
    var chatID: String { chat.id }

    private let chat: ChatPreview
    private let repository: any ChatsRepository
    private let locationStore: ChatLocationSharingStore
    private let profileStore: ProfileStore
    private var cancellables = Set<AnyCancellable>()

    /// Сообщения от старых к новым.
    private var messages: [ChatMessage] = []
    private var messagesByID: [ChatMessage.ID: ChatMessage] = [:]
    private var olderCursor: String?
    private var olderMessagesTask: Task<Void, Never>?
    private var loadState = LoadState.idle
    private var hasLoadedInitialMessages = false
    private var lastMarkedReadID: ChatMessage.ID?

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

    init(
        chat: ChatPreview,
        repository: any ChatsRepository,
        locationStore: ChatLocationSharingStore,
        profileStore: ProfileStore
    ) {
        self.chat = chat
        self.repository = repository
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
        updateLocationState()
        loadInitialMessages()

        locationStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateLocationState() }
            .store(in: &cancellables)
        repository.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &cancellables)
        locationStore.refreshShares(in: chat.id)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showLocationErrorIfNeeded()
        markLatestAsRead()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCollectionInsets()
    }

    override func updateContentUnavailableConfiguration(using state: UIContentUnavailableConfigurationState) {
        guard messages.isEmpty else {
            contentUnavailableConfiguration = nil
            return
        }
        switch loadState {
        case .loading:
            contentUnavailableConfiguration = UIContentUnavailableConfiguration.loading()
        case .failed(let message):
            var configuration = UIContentUnavailableConfiguration.empty()
            configuration.image = UIImage(systemName: "wifi.exclamationmark")
            configuration.text = "Не удалось загрузить сообщения"
            configuration.secondaryText = message
            var button = UIButton.Configuration.borderedProminent()
            button.title = "Повторить"
            configuration.button = button
            configuration.buttonProperties.primaryAction = UIAction { [weak self] _ in self?.loadInitialMessages() }
            contentUnavailableConfiguration = configuration
        case .idle:
            var configuration = UIContentUnavailableConfiguration.empty()
            configuration.image = UIImage(systemName: "bubble.left")
            configuration.text = "Сообщений пока нет"
            configuration.secondaryText = "Напишите первое сообщение"
            contentUnavailableConfiguration = configuration
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
            guard let message = self?.messagesByID[messageID] else { return }
            cell.configure(with: message)
        }
        let headerRegistration = UICollectionView.SupplementaryRegistration<ChatDayHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            header.title = self?.dataSource.sectionIdentifier(for: indexPath.section).map { ChatDateFormatting.dayTitle($0) }
        }

        dataSource = DataSource(collectionView: collectionView) { collectionView, indexPath, messageID in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: messageID)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    // MARK: - Загрузка

    private func loadInitialMessages() {
        loadState = .loading
        setNeedsUpdateContentUnavailableConfiguration()

        Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await self.repository.messages(chatID: self.chat.id, cursor: nil)
                // Неотправленные сообщения остаются в ленте.
                let unsent = self.messages.filter { $0.status == .sending || $0.status == .failed }
                self.messages = Self.sorted(Self.uniqued(page.items + unsent))
                self.olderCursor = page.nextCursor
                self.loadState = .idle
                self.applySnapshot(animated: false)
                self.view.layoutIfNeeded()
                self.collectionView.layoutIfNeeded()
                self.scrollToBottom(animated: false)
                self.hasLoadedInitialMessages = true
                self.markLatestAsRead()
            } catch {
                self.loadState = .failed(error.localizedDescription)
            }
            self.setNeedsUpdateContentUnavailableConfiguration()
        }
    }

    private func loadOlderMessagesIfNeeded() {
        guard hasLoadedInitialMessages, let cursor = olderCursor, olderMessagesTask == nil else { return }

        olderMessagesTask = Task { [weak self] in
            guard let self else { return }
            defer { self.olderMessagesTask = nil }
            guard let page = try? await self.repository.messages(chatID: self.chat.id, cursor: cursor) else { return }
            self.olderCursor = page.nextCursor

            let knownIDs = Set(self.messages.map(\.id))
            let older = page.items.filter { !knownIDs.contains($0.id) }
            guard !older.isEmpty else { return }

            // Сохраняем видимое место: прибавляем к смещению высоту добавленного сверху контента.
            let previousHeight = self.collectionView.contentSize.height
            let previousOffset = self.collectionView.contentOffset.y
            self.messages = Self.sorted(older + self.messages)
            self.applySnapshot(animated: false)
            self.collectionView.layoutIfNeeded()
            self.collectionView.contentOffset.y = previousOffset + self.collectionView.contentSize.height - previousHeight
        }
    }

    /// После переподключения: дочитываем последнюю страницу и сливаем с тем, что уже есть.
    private func resync() {
        Task { [weak self] in
            guard let self, let page = try? await self.repository.messages(chatID: self.chat.id, cursor: nil) else { return }
            let knownIDs = Set(self.messages.map(\.id))
            let overlaps = page.items.contains { knownIDs.contains($0.id) }
            let wasAtBottom = self.isScrolledToBottom

            if overlaps || self.messages.isEmpty {
                self.messages = Self.sorted(Self.uniqued(page.items + self.messages))
            } else {
                // Пропущено больше страницы: начинаем ленту заново с последних сообщений.
                let unsent = self.messages.filter { $0.status == .sending || $0.status == .failed }
                self.messages = Self.sorted(page.items + unsent)
                self.olderCursor = page.nextCursor
            }
            self.applySnapshot(animated: false, reconfiguring: page.items.map(\.id))
            if wasAtBottom { self.scrollToBottom(animated: true) }
            self.markLatestAsRead()
        }
    }

    // MARK: - Отправка

    private func send(_ text: String) {
        let message = ChatMessage(author: "Вы", isMine: true, sentAt: Date(), kind: .text(text), status: .sending)
        messages.append(message)
        applySnapshot(animated: true) { [weak self] in
            self?.scrollToBottom(animated: true)
        }
        deliver(message)
    }

    /// Повторная отправка использует тот же `localID`, поэтому сервер не создаст дубликат.
    private func deliver(_ message: ChatMessage) {
        guard case .text(let text) = message.kind else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let sent = try await self.repository.sendText(text, chatID: self.chat.id, localID: message.id)
                self.messages.removeAll { $0.id == message.id }
                // Сообщение могло уже прийти по WebSocket раньше ответа на POST.
                if !self.messages.contains(where: { $0.id == sent.id }) {
                    self.messages = Self.sorted(self.messages + [sent])
                }
                self.applySnapshot(animated: true, reconfiguring: [sent.id])
            } catch {
                self.updateMessage(id: message.id) { $0.status = .failed }
            }
        }
    }

    private func presentFailedMessageActions(for message: ChatMessage) {
        let sheet = UIAlertController(title: "Сообщение не отправлено", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Отправить ещё раз", style: .default) { [weak self] _ in
            self?.updateMessage(id: message.id) { $0.status = .sending }
            self?.deliver(message)
        })
        sheet.addAction(UIAlertAction(title: "Удалить", style: .destructive) { [weak self] _ in
            self?.messages.removeAll { $0.id == message.id }
            self?.applySnapshot(animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        present(sheet, animated: true)
    }

    // MARK: - События и прочтение

    private func handle(_ event: ChatEvent) {
        switch event {
        case .messageCreated(let message, let chatID):
            guard chatID == chat.id, messagesByID[message.id] == nil else { return }
            let wasAtBottom = isScrolledToBottom
            messages = Self.sorted(messages + [message])
            applySnapshot(animated: true) { [weak self] in
                if wasAtBottom || message.isMine { self?.scrollToBottom(animated: true) }
            }
            markLatestAsRead()

        case .messageDeleted(let chatID, let messageID):
            guard chatID == chat.id, messagesByID[messageID] != nil else { return }
            messages.removeAll { $0.id == messageID }
            applySnapshot(animated: true)

        case .readStateUpdated(let chatID, let userID, let lastReadMessageID):
            // Собеседник прочитал переписку до указанного сообщения — отмечаем свои сообщения прочитанными.
            guard chatID == chat.id, userID != repository.currentUserID,
                  let lastIndex = messages.firstIndex(where: { $0.id == lastReadMessageID }) else { return }
            var changedIDs: [ChatMessage.ID] = []
            for index in messages.indices where index <= lastIndex && messages[index].isMine && messages[index].status == .sent {
                messages[index].status = .read
                changedIDs.append(messages[index].id)
            }
            applySnapshot(animated: false, reconfiguring: changedIDs)

        case .resync:
            resync()

        case .chatUpdated:
            break
        }
    }

    /// Двигает указатель прочтения к последнему сообщению с сервера, пока экран открыт.
    private func markLatestAsRead() {
        guard viewIfLoaded?.window != nil,
              let latest = messages.last(where: { $0.status != .sending && $0.status != .failed }),
              latest.id != lastMarkedReadID else { return }
        lastMarkedReadID = latest.id
        onRead?(chat.id)
        Task { [repository, chatID = chat.id] in
            await repository.markRead(chatID: chatID, messageID: latest.id)
        }
    }

    // MARK: - Снимок

    private func applySnapshot(
        animated: Bool,
        reconfiguring changedIDs: [ChatMessage.ID] = [],
        completion: (() -> Void)? = nil
    ) {
        let calendar = Calendar.current
        var snapshot = Snapshot()
        var currentDay: Date?
        for message in messages {
            let day = calendar.startOfDay(for: message.sentAt)
            if day != currentDay {
                snapshot.appendSections([day])
                currentDay = day
            }
            snapshot.appendItems([message.id], toSection: day)
        }

        let previousIDs = Set(dataSource.snapshot().itemIdentifiers)
        let reconfigured = changedIDs.filter { previousIDs.contains($0) && snapshot.indexOfItem($0) != nil }
        snapshot.reconfigureItems(Array(Set(reconfigured)))
        messagesByID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })

        dataSource.apply(snapshot, animatingDifferences: animated, completion: completion)
        setNeedsUpdateContentUnavailableConfiguration()
    }

    private func updateMessage(id: ChatMessage.ID, _ update: (inout ChatMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        update(&messages[index])
        applySnapshot(animated: false, reconfiguring: [id])
    }

    private static func sorted(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.enumerated()
            .sorted { ($0.element.sentAt, $0.offset) < ($1.element.sentAt, $1.offset) }
            .map(\.element)
    }

    private static func uniqued(_ messages: [ChatMessage]) -> [ChatMessage] {
        var seen = Set<ChatMessage.ID>()
        return messages.filter { seen.insert($0.id).inserted }
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

        let shouldStickToBottom = hasLoadedInitialMessages && isScrolledToBottom
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
        let consentView = ChatLocationConsentView(chatTitle: chat.title, isLocalOnly: !repository.isRemote) { [weak self] in
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

extension ChatViewController: UICollectionViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y + scrollView.adjustedContentInset.top < Self.olderMessagesThreshold {
            loadOlderMessagesIfNeeded()
        }
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return false }
        return messagesByID[id]?.status == .failed
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath), let message = messagesByID[id] else { return }
        presentFailedMessageActions(for: message)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first,
              let id = dataSource.itemIdentifier(for: indexPath),
              case .text(let text)? = messagesByID[id]?.kind else { return nil }
        return UIContextMenuConfiguration(actionProvider: { _ in
            UIMenu(children: [
                UIAction(title: "Скопировать", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = text
                }
            ])
        })
    }
}
