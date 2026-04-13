#if canImport(UIKit)
import UIKit

final class UIKitDemoTabStripView: UIView {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var buttons: [UIKitDemoTab: UIButton] = [:]
    
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
                let button = UIButton(type: .system)
                var configuration = UIButton.Configuration.filled()
                configuration.cornerStyle = .capsule
                configuration.contentInsets = .init(top: 8, leading: 14, bottom: 8, trailing: 14)
                configuration.title = tab.title
                button.configuration = configuration
                button.addAction(
                    UIAction { [weak self] _ in
                        self?.onSelection?(tab)
                    },
                    for: .touchUpInside
                )
                stackView.addArrangedSubview(button)
                buttons[tab] = button
            }
        }
        
        buttons.forEach { tab, button in
            var configuration = button.configuration ?? .filled()
            let isSelected = tab == selected
            configuration.baseBackgroundColor = isSelected ? .label : .secondarySystemFill
            configuration.baseForegroundColor = isSelected ? .systemBackground : .label
            button.configuration = configuration
        }
        
        if let selectedButton = buttons[selected] {
            scrollView.scrollRectToVisible(selectedButton.frame.insetBy(dx: -16, dy: 0), animated: true)
        }
    }
    
    private func configure() {
        scrollView.showsHorizontalScrollIndicator = false
        
        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.spacing = 12
        
        addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        
        scrollView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
    }
}
#endif
