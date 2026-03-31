import Foundation

indirect enum UIKitDemoResponseValue: Equatable, Sendable {
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
}

struct UIKitDemoResponse: Equatable, Sendable {
    let payload: [String: UIKitDemoResponseValue]

    var dictionary: [String: Any] {
        payload.mapValues(\.foundationValue)
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
        .init(payload: ["status": .string("ok"), "tab": .string("feed")])
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
