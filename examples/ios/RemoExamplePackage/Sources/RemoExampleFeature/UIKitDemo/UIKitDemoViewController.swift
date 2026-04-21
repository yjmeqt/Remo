#if canImport(UIKit)
import UIKit

final class UIKitDemoViewController: UIViewController, UIScrollViewDelegate {
    let store = UIKitDemoStore()
    private let tabStripView = UIKitDemoTabStripView()
    private let pagerScrollView = UIScrollView()
    private let pagerStackView = UIStackView()
    private var lastPagerWidth: CGFloat = 0

    var feedPage: UIKitDemoFeedPageViewController?
    var itemsPage: UIKitDemoItemsPageViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 242 / 255, green: 242 / 255, blue: 242 / 255, alpha: 1)
        buildHierarchy()
        configurePages()
        syncSelection(animated: false)
        #if DEBUG
        registerCapabilities()
        #endif
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = pagerScrollView.bounds.width
        guard width > 0, width != lastPagerWidth else { return }
        lastPagerWidth = width
        let index = CGFloat(UIKitDemoTab.allCases.firstIndex(of: store.selectedTab) ?? 0)
        let targetOffset = CGPoint(x: index * width, y: 0)
        if pagerScrollView.contentOffset.x != targetOffset.x {
            pagerScrollView.setContentOffset(targetOffset, animated: false)
        }
    }

    func updateItems(_ items: [String]) {
        // Items tab is driven by seeded contacts to match the Figma design.
        // The shared `store.items` (strings) is no longer rendered here, but
        // is still exposed through the top-level state.get/state.set Remo
        // capabilities for parity with the other demos.
    }

    private func buildHierarchy() {
        tabStripView.onSelection = { [weak self] tab in
            self?.select(tab: tab, animated: true)
        }

        pagerScrollView.isPagingEnabled = true
        pagerScrollView.showsHorizontalScrollIndicator = false
        pagerScrollView.alwaysBounceHorizontal = false
        pagerScrollView.delegate = self
        pagerScrollView.backgroundColor = .clear

        pagerStackView.axis = .horizontal
        pagerStackView.spacing = 0
        pagerStackView.distribution = .fillEqually

        view.addSubview(tabStripView)
        view.addSubview(pagerScrollView)
        tabStripView.translatesAutoresizingMaskIntoConstraints = false
        pagerScrollView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            tabStripView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabStripView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabStripView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tabStripView.heightAnchor.constraint(equalToConstant: 50),

            pagerScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pagerScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pagerScrollView.topAnchor.constraint(equalTo: tabStripView.bottomAnchor),
            pagerScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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

        refreshFeedPage()
        refreshItemsPage()
    }

    func select(tab: UIKitDemoTab, animated: Bool) {
        store.select(tab)
        syncSelection(animated: animated)
    }

    private func syncSelection(animated: Bool) {
        let selectedTab = store.selectedTab
        tabStripView.updateTabs(UIKitDemoTab.allCases, selected: selectedTab)

        if selectedTab == .feed {
            refreshFeedPage()
        } else {
            refreshItemsPage()
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

    func refreshItemsPage() {
        itemsPage?.apply(
            contacts: store.contacts(for: .items),
            restoringOffset: store.verticalOffset(for: .items)
        )
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
        tabStripView.updateTabs(UIKitDemoTab.allCases, selected: tab)
        if tab == .feed {
            refreshFeedPage()
        } else {
            refreshItemsPage()
        }
    }
}
#endif
