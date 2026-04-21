#if canImport(UIKit)
import UIKit

final class UIKitDemoTabStripView: UIView {
    private let rowStack = UIStackView()
    private let separator = UIView()
    private var buttons: [UIKitDemoTab: TabButton] = [:]

    var onSelection: ((UIKitDemoTab) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateTabs(_ tabs: [UIKitDemoTab], selected: UIKitDemoTab) {
        if buttons.isEmpty {
            tabs.forEach { tab in
                let button = TabButton(tab: tab)
                button.addAction(
                    UIAction { [weak self] _ in
                        self?.onSelection?(tab)
                    },
                    for: .touchUpInside
                )
                rowStack.addArrangedSubview(button)
                buttons[tab] = button
            }
        }

        buttons.forEach { tab, button in
            button.setSelected(tab == selected)
        }
    }

    private func configure() {
        backgroundColor = .clear

        rowStack.axis = .horizontal
        rowStack.alignment = .fill
        rowStack.distribution = .fillEqually
        rowStack.spacing = 12
        rowStack.isLayoutMarginsRelativeArrangement = true
        rowStack.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        separator.backgroundColor = UIColor(white: 0, alpha: 0.08)

        addSubview(rowStack)
        addSubview(separator)
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        separator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: separator.topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }
}

private final class TabButton: UIControl {
    private let titleLabel = UILabel()
    private let underline = UIView()
    private let tab: UIKitDemoTab

    init(tab: UIKitDemoTab) {
        self.tab = tab
        super.init(frame: .zero)

        titleLabel.text = tab.title
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)

        underline.backgroundColor = UIColor(white: 29 / 255, alpha: 1)
        underline.isHidden = true

        addSubview(titleLabel)
        addSubview(underline)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        underline.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            titleLabel.bottomAnchor.constraint(equalTo: underline.topAnchor, constant: -12),
            underline.leadingAnchor.constraint(equalTo: leadingAnchor),
            underline.trailingAnchor.constraint(equalTo: trailingAnchor),
            underline.bottomAnchor.constraint(equalTo: bottomAnchor),
            underline.heightAnchor.constraint(equalToConstant: 2),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSelected(_ selected: Bool) {
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: selected ? .bold : .medium)
        titleLabel.textColor = selected
            ? UIColor(white: 29 / 255, alpha: 1)
            : UIColor(white: 29 / 255, alpha: 0.48)
        underline.isHidden = !selected
    }
}
#endif
