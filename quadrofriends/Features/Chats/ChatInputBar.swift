import UIKit

/// Нижняя панель чата: вложения, растущее поле ввода (до 4 строк) и кнопка отправки.
final class ChatInputBar: UIView {
    private static let minimumHeight: CGFloat = 44
    private static let maximumLines: CGFloat = 4

    var onSend: ((String) -> Void)?

    var attachmentMenu: UIMenu? {
        get { attachButton.menu }
        set { attachButton.menu = newValue }
    }

    private let attachButton = UIButton(type: .system)
    private let textView = UITextView()
    private let placeholderLabel = UILabel(textStyle: .body, color: .placeholderText)
    private let sendButton = UIButton(type: .system)
    private lazy var textViewHeightConstraint = textView.heightAnchor.constraint(equalToConstant: Self.minimumHeight)

    private var trimmedText: String {
        textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLayout()
        updateState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateTextViewHeight()
    }

    private func configureLayout() {
        var attachConfiguration = UIButton.Configuration.plain()
        attachConfiguration.image = UIImage(systemName: "paperclip")
        attachConfiguration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .title3)
        attachButton.configuration = attachConfiguration
        attachButton.showsMenuAsPrimaryAction = true
        attachButton.accessibilityLabel = "Вложения"

        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 22
        textView.layer.cornerCurve = .continuous
        textView.textContainerInset = UIEdgeInsets(top: 11, left: 14, bottom: 11, right: 14)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.delegate = self
        textView.accessibilityLabel = "Сообщение"

        placeholderLabel.text = "Сообщение"
        placeholderLabel.isAccessibilityElement = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)

        var sendConfiguration = UIButton.Configuration.plain()
        sendConfiguration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .title2)
        sendButton.configuration = sendConfiguration
        sendButton.accessibilityLabel = "Отправить"
        sendButton.addAction(UIAction { [weak self] _ in self?.send() }, for: .primaryActionTriggered)

        let stackView = UIStackView(arrangedSubviews: [attachButton, textView, sendButton])
        stackView.spacing = 8
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            attachButton.widthAnchor.constraint(equalToConstant: 44),
            attachButton.heightAnchor.constraint(equalToConstant: 44),
            sendButton.widthAnchor.constraint(equalToConstant: 44),
            sendButton.heightAnchor.constraint(equalToConstant: 44),
            textViewHeightConstraint,
            placeholderLabel.topAnchor.constraint(equalTo: textView.frameLayoutGuide.topAnchor, constant: 11),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.frameLayoutGuide.leadingAnchor, constant: 14),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.frameLayoutGuide.trailingAnchor, constant: -14),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func updateTextViewHeight() {
        guard textView.bounds.width > 0, let font = textView.font else { return }
        let insets = textView.textContainerInset
        let maximumHeight = ceil(font.lineHeight * Self.maximumLines + insets.top + insets.bottom)
        let fittingHeight = ceil(textView.sizeThatFits(
            CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
        ).height)

        textView.isScrollEnabled = fittingHeight > maximumHeight
        let height = min(max(Self.minimumHeight, fittingHeight), maximumHeight)
        if textViewHeightConstraint.constant != height {
            textViewHeightConstraint.constant = height
        }
    }

    private func updateState() {
        let isEmpty = trimmedText.isEmpty
        sendButton.configuration?.image = UIImage(systemName: isEmpty ? "mic.fill" : "arrow.up.circle.fill")
        sendButton.isEnabled = !isEmpty
        placeholderLabel.isHidden = !textView.text.isEmpty
    }

    private func send() {
        let text = trimmedText
        guard !text.isEmpty else { return }
        textView.text = ""
        updateState()
        setNeedsLayout()
        onSend?(text)
    }
}

extension ChatInputBar: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updateState()
        setNeedsLayout()
    }
}
