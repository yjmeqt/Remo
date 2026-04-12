#if DEBUG
import Foundation

private struct UIKitDemoCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

indirect enum UIKitDemoResponseValue: Equatable, Sendable, Encodable {
    case string(String)
    case int(Int)
    case array([UIKitDemoResponseValue])
    case object([String: UIKitDemoResponseValue])

    var foundationValue: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .array(let values): return values.map(\.foundationValue)
        case .object(let value): return value.mapValues(\.foundationValue)
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .int(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .array(let values):
            var container = encoder.unkeyedContainer()
            for value in values {
                try container.encode(value)
            }
        case .object(let value):
            var container = encoder.container(keyedBy: UIKitDemoCodingKey.self)
            for (key, value) in value {
                guard let codingKey = UIKitDemoCodingKey(stringValue: key) else { continue }
                try container.encode(value, forKey: codingKey)
            }
        }
    }
}

struct UIKitDemoResponse: Equatable, Sendable, Encodable {
    let payload: [String: UIKitDemoResponseValue]

    var dictionary: [String: Any] {
        payload.mapValues(\.foundationValue)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: UIKitDemoCodingKey.self)
        for (key, value) in payload {
            guard let codingKey = UIKitDemoCodingKey(stringValue: key) else { continue }
            try container.encode(value, forKey: codingKey)
        }
    }
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

    var response: UIKitDemoResponse {
        .init(payload: ["error": .string(message)])
    }
}

enum UIKitDemoTabSelection: Equatable, Sendable {
    case index(Int)
    case tab(UIKitDemoTab)
}

enum UIKitDemoTabTarget: Equatable, Sendable {
    case active
    case all
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

struct UIKitDemoAppendRequest: Equatable, Sendable {
    let tab: UIKitDemoTabTarget
    let title: String
    let subtitle: String?
}

struct UIKitDemoResetRequest: Equatable, Sendable {
    let tab: UIKitDemoTabTarget
}

struct UIKitDemoVerticalScrollRequest: Equatable, Sendable {
    let position: UIKitDemoScrollPosition
}

struct UIKitDemoHorizontalScrollRequest: Equatable, Sendable {
    let target: UIKitDemoHorizontalTarget
}

enum UIKitDemoCapabilityContract {
    enum Names {
        static let tabSelect = "grid.tab.select"
        static let feedAppend = "grid.feed.append"
        static let feedReset = "grid.feed.reset"
        static let scrollVertical = "grid.scroll.vertical"
        static let scrollHorizontal = "grid.scroll.horizontal"
        static let visible = "grid.visible"
    }

    static func parseTabSelect(_ params: [String: Any]) throws -> UIKitDemoTabSelection {
        let index = intValue(params["index"])
        let id = stringValue(params["id"])

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

    static func parseAppend(_ params: [String: Any]) throws -> UIKitDemoAppendRequest {
        guard let title = stringValue(params["title"]), !title.isEmpty else {
            throw UIKitDemoCapabilityError.missingTitle
        }
        return .init(
            tab: try parseTabTarget(params["tab"], defaultingTo: .active),
            title: title,
            subtitle: stringValue(params["subtitle"])
        )
    }

    static func parseReset(_ params: [String: Any]) throws -> UIKitDemoResetRequest {
        return .init(tab: try parseTabTarget(params["tab"], defaultingTo: .active, allowAll: true))
    }

    static func parseVerticalScroll(_ params: [String: Any]) throws -> UIKitDemoVerticalScrollRequest {
        guard let positionName = stringValue(params["position"]) else {
            throw UIKitDemoCapabilityError.unknownPosition("")
        }
        guard let position = UIKitDemoScrollPosition(rawValue: positionName) else {
            throw UIKitDemoCapabilityError.unknownPosition(positionName)
        }
        return .init(position: position)
    }

    static func parseHorizontalScroll(_ params: [String: Any]) throws -> UIKitDemoHorizontalScrollRequest {
        let direction = stringValue(params["direction"])
        let index = intValue(params["index"])
        let id = stringValue(params["id"])

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
                return .init(target: .next)
            case "previous":
                return .init(target: .previous)
            default:
                throw UIKitDemoCapabilityError.missingScrollTarget
            }
        }

        if let index {
            guard UIKitDemoTab.allCases.indices.contains(index) else {
                throw UIKitDemoCapabilityError.tabIndexOutOfRange(index)
            }
            return .init(target: .index(index))
        }

        guard let id, !id.isEmpty else {
            throw UIKitDemoCapabilityError.missingScrollTarget
        }
        guard let tab = UIKitDemoTab(rawValue: id) else {
            throw UIKitDemoCapabilityError.unknownTab(id)
        }
        return .init(target: .tab(tab))
    }

    static func tabSelectResponse(for tab: UIKitDemoTab) -> UIKitDemoResponse {
        .init(payload: [
            "status": .string("ok"),
            "selectedTab": .object(tab.responseValuePayload),
        ])
    }

    static func appendResponse(tab: UIKitDemoTab, count: Int) -> UIKitDemoResponse {
        .init(payload: [
            "status": .string("ok"),
            "tab": .string(tab.id),
            "count": .int(count),
        ])
    }

    static func resetResponse() -> UIKitDemoResponse {
        .init(payload: ["status": .string("ok"), "tab": .string(UIKitDemoTab.feed.id)])
    }

    static func visibleResponse(
        tab: UIKitDemoTab,
        visible: [UIKitDemoResponseValue],
        total: Int
    ) -> UIKitDemoResponse {
        .init(payload: [
            "status": .string("ok"),
            "tab": .string(tab.id),
            "visible": .array(visible),
            "count": .int(visible.count),
            "total": .int(total),
        ])
    }

    static func verticalScrollResponse(position: UIKitDemoScrollPosition, tab: UIKitDemoTab) -> UIKitDemoResponse {
        .init(payload: [
            "status": .string("ok"),
            "position": .string(position.rawValue),
            "tab": .string(tab.id),
        ])
    }
}

private func stringValue(_ value: Any?) -> String? {
    value as? String
}

private func intValue(_ value: Any?) -> Int? {
    switch value {
    case let number as Int:
        return number
    case let number as NSNumber:
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return nil
        }
        let doubleValue = number.doubleValue
        guard doubleValue.isFinite, floor(doubleValue) == doubleValue else {
            return nil
        }
        guard doubleValue >= Double(Int.min), doubleValue <= Double(Int.max) else {
            return nil
        }
        return Int(doubleValue)
    default:
        return nil
    }
}

private func parseTabTarget(
    _ value: Any?,
    defaultingTo defaultTarget: UIKitDemoTabTarget,
    allowAll: Bool = false
) throws -> UIKitDemoTabTarget {
    guard let raw = stringValue(value) else {
        return defaultTarget
    }

    if raw == "active" {
        return .active
    }
    if allowAll, raw == "all" {
        return .all
    }
    guard let tab = UIKitDemoTab(rawValue: raw) else {
        throw UIKitDemoCapabilityError.unknownTab(raw)
    }
    return .tab(tab)
}

#if canImport(UIKit)
import RemoSwift
import UIKit

private final class UIKitDemoCapabilityBridge: @unchecked Sendable {
    weak var controller: UIKitDemoViewController?

    init(controller: UIKitDemoViewController) {
        self.controller = controller
    }

    func run(_ work: @escaping @MainActor @Sendable (UIKitDemoViewController) -> UIKitDemoResponse) -> UIKitDemoResponse {
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

extension UIKitDemoViewController {
    func registerCapabilities() {
        let bridge = UIKitDemoCapabilityBridge(controller: self)

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
                static let name = UIKitDemoCapabilityContract.Names.tabSelect
                typealias Request = GridTabSelectPayload
                typealias Response = UIKitDemoResponse
            }

            enum GridFeedAppend: RemoCapability {
                static let name = UIKitDemoCapabilityContract.Names.feedAppend
                typealias Request = GridFeedAppendPayload
                typealias Response = UIKitDemoResponse
            }

            enum GridFeedReset: RemoCapability {
                static let name = UIKitDemoCapabilityContract.Names.feedReset
                typealias Response = UIKitDemoResponse
            }

            enum GridScrollVertical: RemoCapability {
                static let name = UIKitDemoCapabilityContract.Names.scrollVertical
                typealias Request = GridScrollVerticalPayload
                typealias Response = UIKitDemoResponse
            }

            enum GridScrollHorizontal: RemoCapability {
                static let name = UIKitDemoCapabilityContract.Names.scrollHorizontal
                typealias Request = GridScrollHorizontalPayload
                typealias Response = UIKitDemoResponse
            }

            enum GridVisible: RemoCapability {
                static let name = UIKitDemoCapabilityContract.Names.visible
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
        case .feed:
            feedPage?.scroll(to: request.position, animated: true)
        case .items:
            itemsPage?.scroll(to: request.position, animated: true)
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
}
#endif
#endif
