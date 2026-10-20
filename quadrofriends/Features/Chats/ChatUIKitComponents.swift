import UIKit

extension UIFont {
    /// Шрифт текстового стиля с заданной насыщенностью, масштабируемый Dynamic Type.
    static func scaledFont(textStyle style: TextStyle, weight: Weight) -> UIFont {
        let defaultTraits = UITraitCollection(preferredContentSizeCategory: .large)
        let pointSize = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style, compatibleWith: defaultTraits).pointSize
        return UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: pointSize, weight: weight))
    }
}

extension UILabel {
    convenience init(textStyle: UIFont.TextStyle, weight: UIFont.Weight? = nil, color: UIColor = .label) {
        self.init()
        font = weight.map { .scaledFont(textStyle: textStyle, weight: $0) } ?? .preferredFont(forTextStyle: textStyle)
        textColor = color
        adjustsFontForContentSizeCategory = true
    }
}

/// UIKit-версия `AvatarView`: фото из ассетов или инициалы на оливковом фоне.
final class ChatAvatarView: UIView {
    private let size: CGFloat
    private let imageView = UIImageView()
    private let initialsLabel = UILabel(textStyle: .headline, color: .brandOlive)

    init(size: CGFloat) {
        self.size = size
        super.init(frame: .zero)

        backgroundColor = UIColor.brandOlive.withAlphaComponent(0.16)
        layer.cornerRadius = size / 2
        layer.borderWidth = 2
        layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor
        clipsToBounds = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)

        imageView.contentMode = .scaleAspectFill
        initialsLabel.textAlignment = .center
        initialsLabel.adjustsFontSizeToFitWidth = true
        initialsLabel.minimumScaleFactor = 0.6

        for subview in [initialsLabel, imageView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
            NSLayoutConstraint.activate([
                subview.topAnchor.constraint(equalTo: topAnchor),
                subview.leadingAnchor.constraint(equalTo: leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: trailingAnchor),
                subview.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: size, height: size)
    }

    func configure(imageName: String?, initials: String) {
        imageView.image = imageName.flatMap { UIImage(named: $0) }
        imageView.isHidden = imageView.image == nil
        initialsLabel.text = initials
        initialsLabel.isHidden = !imageView.isHidden
    }
}
