import CoreLocation
import MapKit
import UIKit

/// Пузырь сообщения: свои справа, чужие слева с именем автора.
final class ChatMessageCell: UICollectionViewCell {
    /// Минимальный отступ пузыря от противоположного края экрана.
    private static let oppositeSideInset: CGFloat = 46

    private let bubbleView = UIView()
    private let authorLabel = UILabel(textStyle: .caption2, weight: .semibold, color: .brandOlive)
    private let messageLabel = UILabel(textStyle: .body)
    private let photoView = UIImageView()
    private let locationCard = ChatLocationCardView()
    private let timeLabel = UILabel(textStyle: .caption2, color: .secondaryLabel)
    private let checkmarkView = UIImageView(image: UIImage(systemName: "checkmark"))

    private var padding: CGFloat = 11
    private var paddingConstraints: [NSLayoutConstraint] = []
    private var incomingConstraints: [NSLayoutConstraint] = []
    private var outgoingConstraints: [NSLayoutConstraint] = []
    private var photoTask: Task<Void, Never>?
    private var photoURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        photoTask?.cancel()
        photoTask = nil
        photoURL = nil
        photoView.image = nil
    }

    func configure(with message: ChatMessage) {
        photoTask?.cancel()
        photoTask = nil
        photoURL = nil
        photoView.image = nil
        authorLabel.text = message.author
        authorLabel.isHidden = message.isMine
        timeLabel.text = message.status == .failed ? "Не отправлено" : message.time
        timeLabel.textColor = message.status == .failed ? .systemRed : .secondaryLabel
        configureStatusIcon(for: message)
        bubbleView.backgroundColor = message.isMine ? UIColor.brandOlive.withAlphaComponent(0.14) : .surfaceCream

        let content: String
        switch message.kind {
        case .text(let text):
            messageLabel.text = text
            messageLabel.isHidden = false
            photoView.isHidden = true
            locationCard.isHidden = true
            setPadding(11)
            content = text
        case .photo(let url, let image, let caption):
            photoURL = url
            photoView.image = image
            photoView.isHidden = false
            messageLabel.text = caption
            messageLabel.isHidden = caption?.isEmpty != false
            locationCard.isHidden = true
            setPadding(6)
            content = "Фото"
            if let url, image == nil {
                photoTask = Task { [weak self] in
                    let loaded = await RemoteImageLoader.shared.image(for: url)
                    guard let self, !Task.isCancelled, self.photoURL == url else { return }
                    self.photoView.image = loaded
                }
            }
        case .location(let coordinate):
            locationCard.configure(coordinate: coordinate)
            messageLabel.isHidden = true
            photoView.isHidden = true
            locationCard.isHidden = false
            setPadding(6)
            content = "Геопозиция"
        }

        NSLayoutConstraint.deactivate(message.isMine ? incomingConstraints : outgoingConstraints)
        NSLayoutConstraint.activate(message.isMine ? outgoingConstraints : incomingConstraints)

        let author = message.isMine ? "Вы" : message.author
        let status = Self.statusDescription(message.status).map { ", \($0)" } ?? ""
        accessibilityLabel = "\(author): \(content), \(message.time)\(status)"
        accessibilityHint = message.status == .failed ? "Нажмите, чтобы отправить ещё раз" : nil
    }

    private func configureStatusIcon(for message: ChatMessage) {
        guard message.isMine, let status = message.status else {
            checkmarkView.isHidden = true
            return
        }
        checkmarkView.isHidden = false
        switch status {
        case .sending:
            checkmarkView.image = UIImage(systemName: "clock")
            checkmarkView.tintColor = .secondaryLabel
        case .sent:
            checkmarkView.image = UIImage(systemName: "checkmark")
            checkmarkView.tintColor = .brandOlive
        case .read:
            checkmarkView.image = UIImage(systemName: "checkmark.circle.fill")
            checkmarkView.tintColor = .brandOlive
        case .failed:
            checkmarkView.image = UIImage(systemName: "exclamationmark.circle.fill")
            checkmarkView.tintColor = .systemRed
        }
    }

    private static func statusDescription(_ status: ChatMessage.DeliveryStatus?) -> String? {
        switch status {
        case .sending: return "отправляется"
        case .sent: return "отправлено"
        case .read: return "прочитано"
        case .failed: return "не отправлено"
        case nil: return nil
        }
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        // Многострочному тексту нужна известная максимальная ширина, иначе пузырь посчитается по одной строке.
        let maxTextWidth = layoutAttributes.size.width - Self.oppositeSideInset - padding * 2
        if maxTextWidth > 0, messageLabel.preferredMaxLayoutWidth != maxTextWidth {
            messageLabel.preferredMaxLayoutWidth = maxTextWidth
        }
        return super.preferredLayoutAttributesFitting(layoutAttributes)
    }

    private func setPadding(_ value: CGFloat) {
        padding = value
        for constraint in paddingConstraints {
            constraint.constant = constraint.firstAttribute == .top || constraint.firstAttribute == .leading ? value : -value
        }
    }

    private func configureLayout() {
        isAccessibilityElement = true

        bubbleView.layer.cornerRadius = 16
        bubbleView.layer.cornerCurve = .continuous
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubbleView)

        messageLabel.numberOfLines = 0
        photoView.contentMode = .scaleAspectFill
        photoView.clipsToBounds = true
        photoView.layer.cornerRadius = 10
        photoView.backgroundColor = .secondarySystemFill
        photoView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .caption2)
        checkmarkView.tintColor = .brandOlive

        let footerSpacer = UIView()
        footerSpacer.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
        footerSpacer.setContentCompressionResistancePriority(UILayoutPriority(1), for: .horizontal)
        let footerStack = UIStackView(arrangedSubviews: [footerSpacer, timeLabel, checkmarkView])
        footerStack.spacing = 3
        footerStack.alignment = .center

        let stackView = UIStackView(arrangedSubviews: [authorLabel, photoView, messageLabel, locationCard, footerStack])
        stackView.axis = .vertical
        stackView.spacing = 5
        stackView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(stackView)

        paddingConstraints = [
            stackView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: padding),
            stackView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: padding),
            stackView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -padding),
            stackView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -padding)
        ]

        let bubbleBottom = bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        bubbleBottom.priority = .defaultHigh

        incomingConstraints = [
            bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bubbleView.trailingAnchor.constraint(
                lessThanOrEqualTo: contentView.trailingAnchor, constant: -Self.oppositeSideInset
            )
        ]
        outgoingConstraints = [
            bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bubbleView.leadingAnchor.constraint(
                greaterThanOrEqualTo: contentView.leadingAnchor, constant: Self.oppositeSideInset
            )
        ]

        NSLayoutConstraint.activate(paddingConstraints + incomingConstraints + [
            photoView.widthAnchor.constraint(equalToConstant: 240),
            photoView.heightAnchor.constraint(equalToConstant: 180),
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor),
            bubbleBottom
        ])
    }
}

/// Превью геопозиции в сообщении: статичный снимок карты с меткой и координаты.
final class ChatLocationCardView: UIView {
    private static let mapSize = CGSize(width: 245, height: 130)
    private static let snapshotCache = NSCache<NSString, UIImage>()

    private let mapImageView = UIImageView()
    private let coordinateLabel = UILabel(textStyle: .caption2, color: .secondaryLabel)
    private var coordinate: CLLocationCoordinate2D?
    private var snapshotTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLayout()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ChatLocationCardView, _: UITraitCollection) in
            view.loadSnapshot()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        coordinateLabel.text = String(format: "%.3f, %.3f", coordinate.latitude, coordinate.longitude)
        loadSnapshot()
    }

    private func configureLayout() {
        mapImageView.contentMode = .scaleAspectFill
        mapImageView.backgroundColor = .secondarySystemFill
        mapImageView.layer.cornerRadius = 12
        mapImageView.layer.cornerCurve = .continuous
        mapImageView.clipsToBounds = true

        let titleIcon = UIImageView(image: UIImage(systemName: "location.fill"))
        titleIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .caption1)
        titleIcon.tintColor = .brandOlive
        let titleLabel = UILabel(textStyle: .caption1, weight: .semibold, color: .brandOlive)
        titleLabel.text = "Координаты старта"
        let titleRow = UIStackView(arrangedSubviews: [titleIcon, titleLabel])
        titleRow.spacing = 4
        titleRow.alignment = .center

        let textStack = UIStackView(arrangedSubviews: [titleRow, coordinateLabel])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 7

        let stackView = UIStackView(arrangedSubviews: [mapImageView, textStack])
        stackView.axis = .vertical
        stackView.spacing = 7
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            mapImageView.widthAnchor.constraint(equalToConstant: Self.mapSize.width),
            mapImageView.heightAnchor.constraint(equalToConstant: Self.mapSize.height),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func loadSnapshot() {
        snapshotTask?.cancel()
        guard let coordinate else { return }

        let traits = UITraitCollection(userInterfaceStyle: traitCollection.userInterfaceStyle)
        let cacheKey = "\(coordinate.latitude),\(coordinate.longitude),\(traits.userInterfaceStyle.rawValue)" as NSString
        if let cached = Self.snapshotCache.object(forKey: cacheKey) {
            mapImageView.image = cached
            return
        }
        mapImageView.image = nil

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
        )
        options.size = Self.mapSize
        options.traitCollection = traits

        snapshotTask = Task { [weak self] in
            guard let snapshot = try? await MKMapSnapshotter(options: options).start(),
                  !Task.isCancelled else { return }
            let image = Self.drawMarker(on: snapshot, at: coordinate, traits: traits)
            Self.snapshotCache.setObject(image, forKey: cacheKey)
            self?.mapImageView.image = image
        }
    }

    private static func drawMarker(
        on snapshot: MKMapSnapshotter.Snapshot,
        at coordinate: CLLocationCoordinate2D,
        traits: UITraitCollection
    ) -> UIImage {
        let markerConfiguration = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
            .applying(UIImage.SymbolConfiguration(paletteColors: [.white, UIColor.brandOlive.resolvedColor(with: traits)]))
        let marker = UIImage(systemName: "mappin.circle.fill", withConfiguration: markerConfiguration)
        let point = snapshot.point(for: coordinate)

        return UIGraphicsImageRenderer(size: snapshot.image.size).image { _ in
            snapshot.image.draw(at: .zero)
            guard let marker else { return }
            marker.draw(in: CGRect(
                x: point.x - marker.size.width / 2,
                y: point.y - marker.size.height / 2,
                width: marker.size.width,
                height: marker.size.height
            ))
        }
    }
}

/// Заголовок дня над сообщениями.
final class ChatDayHeaderView: UICollectionReusableView {
    private let label = UILabel(textStyle: .caption1, color: .secondaryLabel)

    var title: String? {
        get { label.text }
        set { label.text = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
