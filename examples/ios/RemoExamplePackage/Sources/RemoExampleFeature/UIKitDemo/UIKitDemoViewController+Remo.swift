#if DEBUG
import Foundation

enum GridCapabilityNames {
    static let tabSelect = "grid.tab.select"
    static let feedAppend = "grid.feed.append"
    static let feedReset = "grid.feed.reset"
    static let scrollVertical = "grid.scroll.vertical"
    static let scrollHorizontal = "grid.scroll.horizontal"
    static let visible = "grid.visible"
}

enum UIKitDemoCapabilityError: Error, Equatable, Sendable {
    case missingTabIdentifier
    case invalidTabSelectionCombination
    case unknownTab(String)
    case tabIndexOutOfRange(Int)
    case missingTitle
    case missingScrollTarget
    case unknownPosition(String)
    case alreadyAtLastTab
    case alreadyAtFirstTab
    case controllerDeallocated
    case unexpectedError

    var message: String {
        switch self {
        case .missingTabIdentifier:
            return "missing tab identifier"
        case .invalidTabSelectionCombination:
            return "invalid target combination"
        case .unknownTab(let value):
            return "unknown tab: \(value)"
        case .tabIndexOutOfRange(let value):
            return "tab index out of range: \(value)"
        case .missingTitle:
            return "missing title"
        case .missingScrollTarget:
            return "missing scroll target"
        case .unknownPosition(let value):
            return "unknown position: \(value)"
        case .alreadyAtLastTab:
            return "already at last tab"
        case .alreadyAtFirstTab:
            return "already at first tab"
        case .controllerDeallocated:
            return "controller deallocated"
        case .unexpectedError:
            return "unexpected error"
        }
    }
}

enum UIKitDemoTabSelection: Equatable, Sendable {
    case index(Int)
    case tab(UIKitDemoTab)
}

enum UIKitDemoHorizontalTarget: Equatable, Sendable {
    case next
    case previous
    case index(Int)
    case tab(UIKitDemoTab)
}

enum UIKitDemoScrollPosition: String, Equatable, Sendable {
    case top
    case middle
    case bottom
}

struct GridTabSelectPayload: Decodable, Equatable, Sendable {
    let index: Int?
    let id: String?

    func selection() throws -> UIKitDemoTabSelection {
        if index == nil, id == nil {
            throw UIKitDemoCapabilityError.missingTabIdentifier
        }
        if index != nil, id != nil {
            throw UIKitDemoCapabilityError.invalidTabSelectionCombination
        }

        if let index {
            guard UIKitDemoTab.allCases.indices.contains(index) else {
                throw UIKitDemoCapabilityError.tabIndexOutOfRange(index)
            }
            return .index(index)
        }

        guard let id, !id.isEmpty else {
            throw UIKitDemoCapabilityError.missingTabIdentifier
        }
        guard let tab = UIKitDemoTab(rawValue: id) else {
            throw UIKitDemoCapabilityError.unknownTab(id)
        }
        return .tab(tab)
    }
}

struct GridFeedAppendPayload: Decodable, Equatable, Sendable {
    let title: String?
    let subtitle: String?

    func validatedTitle() throws -> String {
        guard let title, !title.isEmpty else {
            throw UIKitDemoCapabilityError.missingTitle
        }
        return title
    }
}

struct GridScrollVerticalPayload: Decodable, Equatable, Sendable {
    let position: String?

    func resolvedPosition() throws -> UIKitDemoScrollPosition {
        guard let position else {
            throw UIKitDemoCapabilityError.unknownPosition("")
        }
        guard let parsed = UIKitDemoScrollPosition(rawValue: position) else {
            throw UIKitDemoCapabilityError.unknownPosition(position)
        }
        return parsed
    }
}

struct GridScrollHorizontalPayload: Decodable, Equatable, Sendable {
    let direction: String?
    let index: Int?
    let id: String?

    func target() throws -> UIKitDemoHorizontalTarget {
        let providedCount = [direction != nil, index != nil, id != nil].filter { $0 }.count
        guard providedCount > 0 else {
            throw UIKitDemoCapabilityError.missingScrollTarget
        }
        guard providedCount == 1 else {
            throw UIKitDemoCapabilityError.missingScrollTarget
        }

        if let direction {
            switch direction {
            case "next":
                return .next
            case "previous":
                return .previous
            default:
                throw UIKitDemoCapabilityError.missingScrollTarget
            }
        }

        if let index {
            guard UIKitDemoTab.allCases.indices.contains(index) else {
                throw UIKitDemoCapabilityError.tabIndexOutOfRange(index)
            }
            return .index(index)
        }

        guard let id, !id.isEmpty else {
            throw UIKitDemoCapabilityError.missingScrollTarget
        }
        guard let tab = UIKitDemoTab(rawValue: id) else {
            throw UIKitDemoCapabilityError.unknownTab(id)
        }
        return .tab(tab)
    }
}

struct GridTabReference: Encodable, Equatable, Sendable {
    let index: Int
    let id: String

    init(index: Int, id: String) {
        self.index = index
        self.id = id
    }

    init(for tab: UIKitDemoTab) {
        self.init(index: UIKitDemoTab.allCases.firstIndex(of: tab) ?? 0, id: tab.id)
    }
}

struct GridFeedCardSummary: Encodable, Equatable, Sendable {
    let id: String
    let title: String
}

enum GridVisibleItem: Encodable, Equatable, Sendable {
    case item(String)
    case card(GridFeedCardSummary)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .item(let value):
            try container.encode(value)
        case .card(let value):
            try container.encode(value)
        }
    }
}

private protocol GridCapabilityResponse: Encodable, Sendable {
    init(error: String)
}

struct GridTabSelectResponse: GridCapabilityResponse, Encodable, Equatable, Sendable {
    let status: String?
    let selectedTab: GridTabReference?
    let error: String?

    init(selectedTab: GridTabReference) {
        status = "ok"
        self.selectedTab = selectedTab
        error = nil
    }

    init(error: String) {
        status = nil
        selectedTab = nil
        self.error = error
    }
}

struct GridFeedAppendResponse: GridCapabilityResponse, Encodable, Equatable, Sendable {
    let status: String?
    let tab: String?
    let count: Int?
    let error: String?

    init(tab: UIKitDemoTab, count: Int) {
        status = "ok"
        self.tab = tab.id
        self.count = count
        error = nil
    }

    init(error: String) {
        status = nil
        tab = nil
        count = nil
        self.error = error
    }
}

struct GridFeedResetResponse: GridCapabilityResponse, Encodable, Equatable, Sendable {
    let status: String?
    let tab: String?
    let error: String?

    init(tab: UIKitDemoTab) {
        status = "ok"
        self.tab = tab.id
        error = nil
    }

    init(error: String) {
        status = nil
        tab = nil
        self.error = error
    }
}

struct GridScrollVerticalResponse: GridCapabilityResponse, Encodable, Equatable, Sendable {
    let status: String?
    let position: String?
    let tab: String?
    let error: String?

    init(position: UIKitDemoScrollPosition, tab: UIKitDemoTab) {
        status = "ok"
        self.position = position.rawValue
        self.tab = tab.id
        error = nil
    }

    init(error: String) {
        status = nil
        position = nil
        tab = nil
        self.error = error
    }
}

struct GridVisibleResponse: GridCapabilityResponse, Encodable, Equatable, Sendable {
    let status: String?
    let tab: String?
    let visible: [GridVisibleItem]?
    let count: Int?
    let total: Int?
    let error: String?

    init(tab: UIKitDemoTab, visible: [GridVisibleItem], total: Int) {
        status = "ok"
        self.tab = tab.id
        self.visible = visible
        count = visible.count
        self.total = total
        error = nil
    }

    init(error: String) {
        status = nil
        tab = nil
        visible = nil
        count = nil
        total = nil
        self.error = error
    }
}

private func handleGridCapability<Response: GridCapabilityResponse>(_ body: () throws -> Response) -> Response {
    do {
        return try body()
    } catch let error as UIKitDemoCapabilityError {
        return .init(error: error.message)
    } catch {
        return .init(error: UIKitDemoCapabilityError.unexpectedError.message)
    }
}

#if canImport(UIKit)
import RemoSwift
import UIKit

private final class UIKitDemoCapabilityBridge: @unchecked Sendable {
    weak var controller: UIKitDemoViewController?

    init(controller: UIKitDemoViewController) {
        self.controller = controller
    }

    func run<Response: Sendable>(
        _ work: @escaping @MainActor @Sendable (UIKitDemoViewController) throws -> Response
    ) rethrows -> Response {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated {
                guard let controller else {
                    throw UIKitDemoCapabilityError.controllerDeallocated
                }
                return try work(controller)
            }
        }

        return try DispatchQueue.main.sync { [weak self] in
            try MainActor.assumeIsolated {
                guard let controller = self?.controller else {
                    throw UIKitDemoCapabilityError.controllerDeallocated
                }
                return try work(controller)
            }
        }
    }
}

extension UIKitDemoViewController {
    func registerCapabilities() {
        let bridge = UIKitDemoCapabilityBridge(controller: self)

        #Remo {
            enum GridTabSelect: RemoCapability {
                static let name = GridCapabilityNames.tabSelect
                typealias Request = GridTabSelectPayload
                typealias Response = GridTabSelectResponse
            }

            enum GridFeedAppend: RemoCapability {
                static let name = GridCapabilityNames.feedAppend
                typealias Request = GridFeedAppendPayload
                typealias Response = GridFeedAppendResponse
            }

            enum GridFeedReset: RemoCapability {
                static let name = GridCapabilityNames.feedReset
                typealias Response = GridFeedResetResponse
            }

            enum GridScrollVertical: RemoCapability {
                static let name = GridCapabilityNames.scrollVertical
                typealias Request = GridScrollVerticalPayload
                typealias Response = GridScrollVerticalResponse
            }

            enum GridScrollHorizontal: RemoCapability {
                static let name = GridCapabilityNames.scrollHorizontal
                typealias Request = GridScrollHorizontalPayload
                typealias Response = GridTabSelectResponse
            }

            enum GridVisible: RemoCapability {
                static let name = GridCapabilityNames.visible
                typealias Response = GridVisibleResponse
            }

            #remoScope(scopedTo: self) {
                #remoCap(GridTabSelect.self) { req in
                    handleGridCapability {
                        try bridge.run { controller in
                            try controller.handleTabSelect(req.selection())
                        }
                    }
                }

                #remoCap(GridFeedAppend.self) { req in
                    handleGridCapability {
                        try bridge.run { controller in
                            controller.handleAppend(title: try req.validatedTitle(), subtitle: req.subtitle)
                        }
                    }
                }

                #remoCap(GridFeedReset.self) { _ in
                    handleGridCapability {
                        try bridge.run { controller in
                            controller.handleReset()
                        }
                    }
                }

                #remoCap(GridScrollVertical.self) { req in
                    handleGridCapability {
                        try bridge.run { controller in
                            controller.handleVerticalScroll(position: try req.resolvedPosition())
                        }
                    }
                }

                #remoCap(GridScrollHorizontal.self) { req in
                    handleGridCapability {
                        try bridge.run { controller in
                            try controller.handleHorizontalScroll(try req.target())
                        }
                    }
                }

                #remoCap(GridVisible.self) { _ in
                    handleGridCapability {
                        try bridge.run { controller in
                            controller.handleVisible()
                        }
                    }
                }
            }
        }
    }

    private func handleTabSelect(_ selection: UIKitDemoTabSelection) throws -> GridTabSelectResponse {
        let tab = try store.resolveSelection(selection)
        select(tab: tab, animated: true)
        return .init(selectedTab: .init(for: tab))
    }

    private func handleAppend(title: String, subtitle: String?) -> GridFeedAppendResponse {
        let resolvedTab = store.appendCard(title: title, subtitle: subtitle)
        refreshFeedPage()
        return .init(tab: resolvedTab, count: store.count(for: resolvedTab))
    }

    private func handleReset() -> GridFeedResetResponse {
        store.resetFeed()
        store.updateVerticalOffset(0, for: .feed)
        feedPage?.apply(cards: store.cards(for: .feed), restoringOffset: 0)
        return .init(tab: .feed)
    }

    private func handleVerticalScroll(position: UIKitDemoScrollPosition) -> GridScrollVerticalResponse {
        let tab = store.selectedTab
        switch tab {
        case .feed:
            feedPage?.scroll(to: position, animated: true)
        case .items:
            itemsPage?.scroll(to: position, animated: true)
        }
        return .init(position: position, tab: tab)
    }

    private func handleHorizontalScroll(_ target: UIKitDemoHorizontalTarget) throws -> GridTabSelectResponse {
        let tab = try store.resolveHorizontalTarget(target)
        select(tab: tab, animated: true)
        return .init(selectedTab: .init(for: tab))
    }

    private func handleVisible() -> GridVisibleResponse {
        let tab = store.selectedTab
        switch tab {
        case .feed:
            let visible = (feedPage?.visibleCards() ?? []).map {
                GridVisibleItem.card(.init(id: $0.id, title: $0.title))
            }
            return .init(tab: tab, visible: visible, total: store.count(for: .feed))
        case .items:
            let visible = (itemsPage?.visibleItems() ?? []).map(GridVisibleItem.item)
            return .init(tab: tab, visible: visible, total: currentItems.count)
        }
    }
}
#endif
#endif
