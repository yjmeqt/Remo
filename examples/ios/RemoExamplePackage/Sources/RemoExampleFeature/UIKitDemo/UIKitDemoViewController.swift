#if canImport(UIKit)
import UIKit

final class UIKitDemoViewController: UIViewController, UIScrollViewDelegate {
    let store = UIKitDemoStore()
    private let rootScrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let headerStack = UIStackView()
    private let activeTabLabel = UILabel()
    private let tabStripView = UIKitDemoTabStripView()
    private let pagerScrollView = UIScrollView()
    private let pagerStackView = UIStackView()
    private var pagerHeightConstraint: NSLayoutConstraint?

    var feedPage: UIKitDemoFeedPageViewController?
    var itemsPage: UIKitDemoItemsPageViewController?
    var currentItems: [String] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        buildHierarchy()
        configurePages()
        refreshFeedPage()
        syncSelection(animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if DEBUG
        registerCapabilities()
        #endif
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let targetHeight = max(420, view.bounds.height - 220)
        pagerHeightConstraint?.constant = targetHeight
    }

    func updateItems(_ items: [String]) {
        currentItems = items
        itemsPage?.apply(items: items, restoringOffset: store.verticalOffset(for: .items))
    }

    private func buildHierarchy() {
        rootScrollView.alwaysBounceVertical = true
        rootScrollView.showsVerticalScrollIndicator = true

        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.layoutMargins = .init(top: 24, left: 20, bottom: 24, right: 20)
        contentStack.isLayoutMarginsRelativeArrangement = true

        headerStack.axis = .vertical
        headerStack.spacing = 10

        let titleLabel = UILabel()
        titleLabel.text = "Grid"
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle).bold()

        let subtitleLabel = UILabel()
        subtitleLabel.text = "A UIKit Remo demo with Feed and Items tabs, horizontal paging, and explicit main-thread UI updates."
        subtitleLabel.font = .preferredFont(forTextStyle: .body)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        activeTabLabel.font = .preferredFont(forTextStyle: .subheadline)
        activeTabLabel.textColor = .secondaryLabel

        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(subtitleLabel)
        headerStack.addArrangedSubview(activeTabLabel)

        tabStripView.onSelection = { [weak self] tab in
            self?.select(tab: tab, animated: true)
        }

        pagerScrollView.isPagingEnabled = true
        pagerScrollView.showsHorizontalScrollIndicator = false
        pagerScrollView.alwaysBounceHorizontal = true
        pagerScrollView.delegate = self

        pagerStackView.axis = .horizontal
        pagerStackView.spacing = 0
        pagerStackView.distribution = .fillEqually

        view.addSubview(rootScrollView)
        rootScrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rootScrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            rootScrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            rootScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            rootScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        rootScrollView.addSubview(contentStack)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: rootScrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: rootScrollView.contentLayoutGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: rootScrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: rootScrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: rootScrollView.frameLayoutGuide.widthAnchor),
        ])

        contentStack.addArrangedSubview(headerStack)

        let tabContainer = UIView()
        tabContainer.addSubview(tabStripView)
        tabStripView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tabStripView.leadingAnchor.constraint(equalTo: tabContainer.leadingAnchor),
            tabStripView.trailingAnchor.constraint(equalTo: tabContainer.trailingAnchor),
            tabStripView.topAnchor.constraint(equalTo: tabContainer.topAnchor),
            tabStripView.bottomAnchor.constraint(equalTo: tabContainer.bottomAnchor),
            tabStripView.heightAnchor.constraint(equalToConstant: 44),
        ])
        contentStack.addArrangedSubview(tabContainer)

        let pagerContainer = UIView()
        pagerContainer.layer.cornerRadius = 28
        pagerContainer.layer.masksToBounds = true
        pagerContainer.backgroundColor = .systemBackground

        pagerContainer.addSubview(pagerScrollView)
        pagerScrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pagerScrollView.leadingAnchor.constraint(equalTo: pagerContainer.leadingAnchor),
            pagerScrollView.trailingAnchor.constraint(equalTo: pagerContainer.trailingAnchor),
            pagerScrollView.topAnchor.constraint(equalTo: pagerContainer.topAnchor),
            pagerScrollView.bottomAnchor.constraint(equalTo: pagerContainer.bottomAnchor),
        ])

        pagerScrollView.addSubview(pagerStackView)
        pagerStackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pagerStackView.leadingAnchor.constraint(equalTo: pagerScrollView.contentLayoutGuide.leadingAnchor),
            pagerStackView.trailingAnchor.constraint(equalTo: pagerScrollView.contentLayoutGuide.trailingAnchor),
            pagerStackView.topAnchor.constraint(equalTo: pagerScrollView.contentLayoutGuide.topAnchor),
            pagerStackView.bottomAnchor.constraint(equalTo: pagerScrollView.contentLayoutGuide.bottomAnchor),
            pagerStackView.heightAnchor.constraint(equalTo: pagerScrollView.frameLayoutGuide.heightAnchor),
        ])

        contentStack.addArrangedSubview(pagerContainer)
        pagerContainer.translatesAutoresizingMaskIntoConstraints = false
        let heightConstraint = pagerContainer.heightAnchor.constraint(equalToConstant: 500)
        heightConstraint.isActive = true
        pagerHeightConstraint = heightConstraint
    }

    private func configurePages() {
        let feed = UIKitDemoFeedPageViewController()
        feed.onVerticalOffsetChange = { [weak self] offset in
            self?.store.updateVerticalOffset(offset, for: .feed)
        }
        addChild(feed)
        pagerStackView.addArrangedSubview(feed.view)
        feed.view.translatesAutoresizingMaskIntoConstraints = false
        feed.view.widthAnchor.constraint(equalTo: pagerScrollView.frameLayoutGuide.widthAnchor).isActive = true
        feed.didMove(toParent: self)
        feedPage = feed

        let items = UIKitDemoItemsPageViewController()
        items.onVerticalOffsetChange = { [weak self] offset in
            self?.store.updateVerticalOffset(offset, for: .items)
        }
        addChild(items)
        pagerStackView.addArrangedSubview(items.view)
        items.view.translatesAutoresizingMaskIntoConstraints = false
        items.view.widthAnchor.constraint(equalTo: pagerScrollView.frameLayoutGuide.widthAnchor).isActive = true
        items.didMove(toParent: self)
        itemsPage = items
    }

    func select(tab: UIKitDemoTab, animated: Bool) {
        store.select(tab)
        syncSelection(animated: animated)
    }

    private func syncSelection(animated: Bool) {
        let selectedTab = store.selectedTab
        activeTabLabel.text = "Active tab: \(selectedTab.title)"
        tabStripView.updateTabs(UIKitDemoTab.allCases, selected: selectedTab)

        if selectedTab == .feed {
            refreshFeedPage()
        } else {
            itemsPage?.apply(items: currentItems, restoringOffset: store.verticalOffset(for: .items))
        }

        let index = CGFloat(UIKitDemoTab.allCases.firstIndex(of: selectedTab) ?? 0)
        let targetOffset = CGPoint(x: index * pagerScrollView.bounds.width, y: 0)
        if pagerScrollView.bounds.width > 0 {
            pagerScrollView.setContentOffset(targetOffset, animated: animated)
        }
    }

    func refreshFeedPage() {
        feedPage?.apply(cards: store.cards(for: .feed), restoringOffset: store.verticalOffset(for: .feed))
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        syncSelectionFromPager()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        syncSelectionFromPager()
    }

    private func syncSelectionFromPager() {
        guard pagerScrollView.bounds.width > 0 else { return }
        let rawIndex = pagerScrollView.contentOffset.x / pagerScrollView.bounds.width
        let index = max(0, min(Int(round(rawIndex)), UIKitDemoTab.allCases.count - 1))
        let tab = UIKitDemoTab.allCases[index]
        store.select(tab)
        activeTabLabel.text = "Active tab: \(tab.title)"
        tabStripView.updateTabs(UIKitDemoTab.allCases, selected: tab)
        if tab == .feed {
            refreshFeedPage()
        } else {
            itemsPage?.apply(items: currentItems, restoringOffset: store.verticalOffset(for: .items))
        }
    }
}

private extension UIFont {
    func bold() -> UIFont {
        let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) ?? fontDescriptor
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
#endif
