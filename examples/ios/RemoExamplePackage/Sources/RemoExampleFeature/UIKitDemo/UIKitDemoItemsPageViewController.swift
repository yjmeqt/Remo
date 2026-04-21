#if canImport(UIKit)
import UIKit

final class UIKitDemoItemsPageViewController: UIViewController {
    private enum Section { case main }

    private let cellRegistration = UICollectionView.CellRegistration<ContactCell, UIKitDemoContact> {
        cell, _, contact in
        cell.configure(with: contact)
    }

    private(set) lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(72)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(72)
            )
            let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 0
            section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 24, trailing: 8)
            return section
        }
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.alwaysBounceVertical = true
        cv.showsVerticalScrollIndicator = false
        return cv
    }()

    private lazy var dataSource = UICollectionViewDiffableDataSource<Section, UIKitDemoContact>(
        collectionView: collectionView
    ) { [cellRegistration] collectionView, indexPath, contact in
        collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: contact)
    }

    var onVerticalOffsetChange: ((CGFloat) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        collectionView.delegate = self
    }

    func apply(contacts: [UIKitDemoContact], restoringOffset: CGFloat) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, UIKitDemoContact>()
        snapshot.appendSections([.main])
        snapshot.appendItems(contacts)
        dataSource.apply(snapshot, animatingDifferences: true)
        collectionView.layoutIfNeeded()
        let clamped = max(-collectionView.adjustedContentInset.top, restoringOffset)
        collectionView.setContentOffset(.init(x: 0, y: clamped), animated: false)
    }

    func visibleContacts() -> [UIKitDemoContact] {
        collectionView.indexPathsForVisibleItems
            .sorted()
            .compactMap { dataSource.itemIdentifier(for: $0) }
    }

    @discardableResult
    func scroll(to position: UIKitDemoScrollPosition, animated: Bool) -> CGFloat {
        let inset = collectionView.adjustedContentInset
        let visibleHeight = collectionView.bounds.height - inset.top - inset.bottom
        let contentHeight = collectionView.contentSize.height
        let maxOffset = max(-inset.top, contentHeight - visibleHeight)

        let y: CGFloat
        switch position {
        case .top: y = -inset.top
        case .middle: y = max(-inset.top, maxOffset / 2)
        case .bottom: y = maxOffset
        }
        collectionView.setContentOffset(.init(x: 0, y: y), animated: animated)
        return y
    }
}

extension UIKitDemoItemsPageViewController: UICollectionViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onVerticalOffsetChange?(scrollView.contentOffset.y)
    }
}

private final class ContactCell: UICollectionViewCell {
    private let avatarView = AvatarCircleView()
    private let nameLabel = UILabel()
    private let handleLabel = UILabel()
    private let textStack = UIStackView()
    private let rowStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear

        nameLabel.font = UIFont.systemFont(ofSize: 15, weight: .bold)
        nameLabel.textColor = UIColor(white: 29 / 255, alpha: 1)
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail

        handleLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        handleLabel.textColor = UIColor(white: 29 / 255, alpha: 0.48)
        handleLabel.numberOfLines = 1

        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.addArrangedSubview(nameLabel)
        textStack.addArrangedSubview(handleLabel)

        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 12
        rowStack.isLayoutMarginsRelativeArrangement = true
        rowStack.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        rowStack.addArrangedSubview(avatarView)
        rowStack.addArrangedSubview(textStack)

        contentView.addSubview(rowStack)
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 56),
            avatarView.heightAnchor.constraint(equalToConstant: 56),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with contact: UIKitDemoContact) {
        nameLabel.text = contact.name
        handleLabel.text = contact.handle
        avatarView.configure(hue: contact.avatarHue, initial: String(contact.name.prefix(1)).uppercased())
    }
}

private final class AvatarCircleView: UIView {
    private let initialLabel = UILabel()
    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerCurve = .circular
        layer.masksToBounds = true

        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(gradientLayer)

        initialLabel.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        initialLabel.textColor = .white
        initialLabel.textAlignment = .center
        addSubview(initialLabel)
        initialLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            initialLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            initialLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
        gradientLayer.frame = bounds
    }

    func configure(hue: Double, initial: String) {
        let base = UIColor(hue: CGFloat(hue), saturation: 0.52, brightness: 0.78, alpha: 1)
        let top = UIColor(hue: CGFloat(hue), saturation: 0.45, brightness: 0.92, alpha: 1)
        gradientLayer.colors = [top.cgColor, base.cgColor]
        initialLabel.text = initial.isEmpty ? "?" : initial
    }
}
#endif
