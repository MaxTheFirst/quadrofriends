import UIKit

/// Плашка над сообщениями: кто сейчас делится геопозицией в чате.
final class ChatLocationBannerView: UIView {
    var onOpenMap: (() -> Void)?
    var onStopSharing: (() -> Void)?

    private let titleLabel = UILabel(textStyle: .subheadline, weight: .semibold)
    private let subtitleLabel = UILabel(textStyle: .caption1, color: .secondaryLabel)
    private let demoLabel = UILabel(textStyle: .caption2, weight: .bold, color: .brandOlive)
    private lazy var openMapButton = makeActionButton(title: "Открыть карту", systemImage: "map", color: .label) { [weak self] in
        self?.onOpenMap?()
    }
    private lazy var stopButton = makeActionButton(title: "Остановить", systemImage: "stop.circle", color: .systemRed) { [weak self] in
        self?.onStopSharing?()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(shares: [ChatLiveLocation]) {
        let ownShare = shares.first(where: \.isMine)
        let otherShares = shares.filter { !$0.isMine }

        if ownShare != nil {
            titleLabel.text = otherShares.isEmpty
                ? "Вы делитесь геопозицией"
                : "Вы и другие участники делитесь геопозицией"
        } else if otherShares.count == 1 {
            titleLabel.text = "\(otherShares[0].name) делится геопозицией"
        } else {
            titleLabel.text = "\(otherShares.count) участников делятся геопозицией"
        }
        subtitleLabel.text = ownShare == nil
            ? "Местоположение видно участникам этого чата"
            : "Ваше местоположение видно всем участникам чата"
        demoLabel.isHidden = !shares.contains(where: \.isDemo)
        stopButton.isHidden = ownShare == nil
    }

    private func configureLayout() {
        backgroundColor = UIColor.brandOlive.withAlphaComponent(0.11)
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous

        let iconView = UIImageView(image: UIImage(systemName: "location.fill"))
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        iconView.tintColor = .white
        iconView.contentMode = .center
        iconView.backgroundColor = .brandOlive
        iconView.layer.cornerRadius = 17
        iconView.isAccessibilityElement = false

        titleLabel.numberOfLines = 0
        subtitleLabel.numberOfLines = 0
        demoLabel.text = "Демо"
        demoLabel.setContentHuggingPriority(.required, for: .horizontal)
        demoLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 3

        let headerRow = UIStackView(arrangedSubviews: [iconView, textStack, demoLabel])
        headerRow.spacing = 10
        headerRow.alignment = .top

        let buttonsSpacer = UIView()
        buttonsSpacer.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
        let buttonsRow = UIStackView(arrangedSubviews: [openMapButton, stopButton, buttonsSpacer])
        buttonsRow.spacing = 16
        buttonsRow.isLayoutMarginsRelativeArrangement = true
        buttonsRow.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 44, bottom: 0, trailing: 0)

        let stackView = UIStackView(arrangedSubviews: [headerRow, buttonsRow])
        stackView.axis = .vertical
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 34),
            iconView.heightAnchor.constraint(equalToConstant: 34),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    private func makeActionButton(
        title: String,
        systemImage: String,
        color: UIColor,
        action: @escaping () -> Void
    ) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: systemImage)
        configuration.imagePadding = 4
        configuration.contentInsets = .zero
        configuration.baseForegroundColor = color
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .caption1)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .scaledFont(textStyle: .caption1, weight: .semibold)
            return attributes
        }
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }
}
