#if canImport(UIKit)
import UIKit

final class UIKitDemoFeedPageViewController: UIViewController {
    private enum Section { case main }

    private let cellRegistration = UICollectionView.CellRegistration<UICollectionViewCell, UIKitDemoCard> {
        cell, _, card in
        var content = UIListContentConfiguration.cell()
        content.text = card.title
        content.secondaryText = card.subtitle
        content.textProperties.font = .preferredFont(forTextStyle: .headline)
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
        cell.contentConfiguration = content

        var background = UIBackgroundConfiguration.listGroupedCell()
        background.cornerRadius = 20
        cell.backgroundConfiguration = background
    }

    private(set) lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(0.5),
                heightDimension: .estimated(120)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(120)
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: groupSize,
                subitems: [item, item]
            )
            group.interItemSpacing = .fixed(12)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 12
            section.contentInsets = NSDirectionalEdgeInsets(top: 20, leading: 16, bottom: 32, trailing: 16)
            return section
        }
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.alwaysBounceVertical = true
        return cv
    }()

    private lazy var dataSource = UICollectionViewDiffableDataSource<Section, UIKitDemoCard>(
        collectionView: collectionView
    ) { [cellRegistration] collectionView, indexPath, card in
        collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: card)
    }

    var onVerticalOffsetChange: ((CGFloat) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
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

    func apply(cards: [UIKitDemoCard], restoringOffset: CGFloat) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, UIKitDemoCard>()
        snapshot.appendSections([.main])
        snapshot.appendItems(cards)
        dataSource.apply(snapshot, animatingDifferences: true)
        collectionView.layoutIfNeeded()
        let clamped = max(-collectionView.adjustedContentInset.top, restoringOffset)
        collectionView.setContentOffset(.init(x: 0, y: clamped), animated: false)
    }

    func visibleCards() -> [UIKitDemoCard] {
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

extension UIKitDemoFeedPageViewController: UICollectionViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onVerticalOffsetChange?(scrollView.contentOffset.y)
    }
}
#endif
