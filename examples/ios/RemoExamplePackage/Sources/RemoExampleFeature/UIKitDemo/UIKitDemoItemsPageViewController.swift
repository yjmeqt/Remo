#if canImport(UIKit)
import UIKit

final class UIKitDemoItemsPageViewController: UIViewController {
    private enum Section { case main }

    private let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, String> {
        cell, _, item in
        var content = cell.defaultContentConfiguration()
        content.text = item
        cell.contentConfiguration = content
    }

    private(set) lazy var collectionView: UICollectionView = {
        var listConfig = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        listConfig.showsSeparators = true
        let layout = UICollectionViewCompositionalLayout.list(using: listConfig)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.alwaysBounceVertical = true
        return cv
    }()

    private lazy var dataSource = UICollectionViewDiffableDataSource<Section, String>(
        collectionView: collectionView
    ) { [cellRegistration] collectionView, indexPath, item in
        collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
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

    func apply(items: [String], restoringOffset: CGFloat) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items)
        dataSource.apply(snapshot, animatingDifferences: true)
        collectionView.layoutIfNeeded()
        let clamped = max(-collectionView.adjustedContentInset.top, restoringOffset)
        collectionView.setContentOffset(.init(x: 0, y: clamped), animated: false)
    }

    func visibleItems() -> [String] {
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
#endif
