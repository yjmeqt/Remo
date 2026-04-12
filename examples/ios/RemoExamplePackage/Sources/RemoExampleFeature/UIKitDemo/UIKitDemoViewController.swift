#if canImport(UIKit)
import RemoSwift
import UIKit

final class UIKitDemoViewController: UIViewController, UIScrollViewDelegate {
    private final class CapabilityBridge: @unchecked Sendable {
        weak var controller: UIKitDemoViewController?

        init(controller: UIKitDemoViewController) {
            self.controller = controller
        }

        func run(
            _ work: @escaping @MainActor @Sendable (UIKitDemoViewController) -> UIKitDemoResponse
        ) -> UIKitDemoResponse {
            if Thread.isMainThread {
                return MainActor.assumeIsolated {
                    guard let controller else {
                        return UIKitDemoCapabilityError.controllerDeallocated.response
                    }
                    return work(controller)
                }
            }

            return DispatchQueue.main.sync { [weak self] in
                MainActor.assumeIsolated {
                    guard let controller = self?.controller else {
                        return UIKitDemoCapabilityError.controllerDeallocated.response
                    }
                    return work(controller)
                }
            }
        }
    }

    private let store = UIKitDemoStore()
    private let rootScrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let headerStack = UIStackView()
    private let activeTabLabel = UILabel()
    private let tabStripView = UIKitDemoTabStripView()
    private let pagerScrollView = UIScrollView()
    private let pagerStackView = UIStackView()
    private var pagerHeightConstraint: NSLayoutConstraint?

    private var feedPage: UIKitDemoFeedPageViewController?
    private var itemsPage: UIKitDemoItemsPageViewController?
    private var currentItems: [String] = []

    private var capabilityBridge: CapabilityBridge?

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
        registerCapabilities()
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

    private func registerCapabilities() {
        let bridge = CapabilityBridge(controller: self)
        capabilityBridge = bridge

        #Remo {
            struct GridTabSelectPayload: Decodable {
                let index: Int?
                let id: String?

                var raw: [String: Any] {
                    var raw: [String: Any] = [:]
                    if let index {
                        raw["index"] = index
                    }
                    if let id {
                        raw["id"] = id
                    }
                    return raw
                }
            }

            struct GridFeedAppendPayload: Decodable {
                let tab: String?
                let title: String?
                let subtitle: String?

                var raw: [String: Any] {
                    var raw: [String: Any] = [:]
                    if let tab {
                        raw["tab"] = tab
                    }
                    if let title {
                        raw["title"] = title
                    }
                    if let subtitle {
                        raw["subtitle"] = subtitle
                    }
                    return raw
                }
            }

            struct GridScrollVerticalPayload: Decodable {
                let position: String?

                var raw: [String: Any] {
                    var raw: [String: Any] = [:]
                    if let position {
                        raw["position"] = position
                    }
                    return raw
                }
            }

            struct GridScrollHorizontalPayload: Decodable {
                let direction: String?
                let index: Int?
                let id: String?

                var raw: [String: Any] {
                    var raw: [String: Any] = [:]
                    if let direction {
                        raw["direction"] = direction
                    }
                    if let index {
                        raw["index"] = index
                    }
                    if let id {
                        raw["id"] = id
                    }
                    return raw
                }
            }

            enum GridTabSelect: RemoCapability {
                static let name = "grid.tab.select"
                typealias Request = GridTabSelectPayload
                typealias Response = UIKitDemoResponse
            }

            enum GridFeedAppend: RemoCapability {
                static let name = "grid.feed.append"
                typealias Request = GridFeedAppendPayload
                typealias Response = UIKitDemoResponse
            }

            enum GridFeedReset: RemoCapability {
                static let name = "grid.feed.reset"
                typealias Response = UIKitDemoResponse
            }

            enum GridScrollVertical: RemoCapability {
                static let name = "grid.scroll.vertical"
                typealias Request = GridScrollVerticalPayload
                typealias Response = UIKitDemoResponse
            }

            enum GridScrollHorizontal: RemoCapability {
                static let name = "grid.scroll.horizontal"
                typealias Request = GridScrollHorizontalPayload
                typealias Response = UIKitDemoResponse
            }

            enum GridVisible: RemoCapability {
                static let name = "grid.visible"
                typealias Response = UIKitDemoResponse
            }

            #remoScope(scopedTo: self) {
                #remoCap(GridTabSelect.self) { req in
                    do {
                        let selection = try UIKitDemoCapabilityContract.parseTabSelect(req.raw)
                        return bridge.run { controller in controller.handleTabSelect(selection) }
                    } catch let error as UIKitDemoCapabilityError {
                        return error.response
                    } catch {
                        return UIKitDemoCapabilityError.unexpectedError.response
                    }
                }

                #remoCap(GridFeedAppend.self) { req in
                    do {
                        let request = try UIKitDemoCapabilityContract.parseAppend(req.raw)
                        return bridge.run { controller in controller.handleAppend(request) }
                    } catch let error as UIKitDemoCapabilityError {
                        return error.response
                    } catch {
                        return UIKitDemoCapabilityError.unexpectedError.response
                    }
                }

                #remoCap(GridFeedReset.self) { _ in
                    bridge.run { controller in controller.handleReset() }
                }

                #remoCap(GridScrollVertical.self) { req in
                    do {
                        let request = try UIKitDemoCapabilityContract.parseVerticalScroll(req.raw)
                        return bridge.run { controller in controller.handleVerticalScroll(request) }
                    } catch let error as UIKitDemoCapabilityError {
                        return error.response
                    } catch {
                        return UIKitDemoCapabilityError.unexpectedError.response
                    }
                }

                #remoCap(GridScrollHorizontal.self) { req in
                    do {
                        let request = try UIKitDemoCapabilityContract.parseHorizontalScroll(req.raw)
                        return bridge.run { controller in controller.handleHorizontalScroll(request) }
                    } catch let error as UIKitDemoCapabilityError {
                        return error.response
                    } catch {
                        return UIKitDemoCapabilityError.unexpectedError.response
                    }
                }

                #remoCap(GridVisible.self) { _ in
                    bridge.run { controller in controller.handleVisible() }
                }
            }
        }
    }

    private func handleTabSelect(_ selection: UIKitDemoTabSelection) -> UIKitDemoResponse {
        do {
            let tab = try store.resolveSelection(selection)
            select(tab: tab, animated: true)
            return UIKitDemoCapabilityContract.tabSelectResponse(for: tab)
        } catch let error as UIKitDemoCapabilityError {
            return error.response
        } catch {
            return UIKitDemoCapabilityError.unexpectedError.response
        }
    }

    private func handleAppend(_ request: UIKitDemoAppendRequest) -> UIKitDemoResponse {
        let resolvedTab = store.appendCard(title: request.title, subtitle: request.subtitle)
        refreshFeedPage()
        return UIKitDemoCapabilityContract.appendResponse(tab: resolvedTab, count: store.count(for: resolvedTab))
    }

    private func handleReset() -> UIKitDemoResponse {
        store.resetFeed()
        store.updateVerticalOffset(0, for: .feed)
        feedPage?.apply(cards: store.cards(for: .feed), restoringOffset: 0)
        return UIKitDemoCapabilityContract.resetResponse()
    }

    private func handleVerticalScroll(_ request: UIKitDemoVerticalScrollRequest) -> UIKitDemoResponse {
        let tab = store.selectedTab
        switch tab {
        case .feed: feedPage?.scroll(to: request.position, animated: true)
        case .items: itemsPage?.scroll(to: request.position, animated: true)
        }
        return UIKitDemoCapabilityContract.verticalScrollResponse(position: request.position, tab: tab)
    }

    private func handleHorizontalScroll(_ request: UIKitDemoHorizontalScrollRequest) -> UIKitDemoResponse {
        do {
            let tab = try store.resolveHorizontalTarget(request.target)
            select(tab: tab, animated: true)
            return UIKitDemoCapabilityContract.tabSelectResponse(for: tab)
        } catch let error as UIKitDemoCapabilityError {
            return error.response
        } catch {
            return UIKitDemoCapabilityError.unexpectedError.response
        }
    }

    private func handleVisible() -> UIKitDemoResponse {
        let tab = store.selectedTab
        switch tab {
        case .feed:
            let visible = feedPage?.visibleCards() ?? []
            return UIKitDemoCapabilityContract.visibleResponse(
                tab: tab,
                visible: visible.map { .object(["id": .string($0.id), "title": .string($0.title)]) },
                total: store.count(for: .feed)
            )
        case .items:
            let visible = itemsPage?.visibleItems() ?? []
            return UIKitDemoCapabilityContract.visibleResponse(
                tab: tab,
                visible: visible.map { .string($0) },
                total: currentItems.count
            )
        }
    }

    private func select(tab: UIKitDemoTab, animated: Bool) {
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

    private func refreshFeedPage() {
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
