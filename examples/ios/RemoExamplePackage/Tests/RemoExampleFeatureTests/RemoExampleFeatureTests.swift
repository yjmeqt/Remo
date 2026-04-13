import Testing
import RemoSwift
@testable import RemoExampleFeature

private func requireSendable<T: Sendable>(_: T.Type) {}

@Test func appStoreRemainsSendableForBackgroundCapabilityClosures() async throws {
    requireSendable(AppStore.self)
}

@Test func registerRequiresASendableHandlerContract() async throws {
    let register: (String, @Sendable @escaping ([String: Any]) -> [String: Any]) -> Void = Remo.register
    _ = register
}

@Test func gridTabCasesAreFeedAndItems() {
    #expect(UIKitDemoTab.allCases == [.feed, .items])
}

@Test func gridTabIDsMatchExpected() {
    #expect(UIKitDemoTab.feed.id == "feed")
    #expect(UIKitDemoTab.items.id == "items")
}

@Test func appStoreItemsSeedHasTwentyEntries() {
    #expect(AppStore().items.count == 20)
}

@Test func capabilityNamesUseGridPrefix() {
    let names = [
        GridCapabilityNames.tabSelect,
        GridCapabilityNames.feedAppend,
        GridCapabilityNames.feedReset,
        GridCapabilityNames.scrollVertical,
        GridCapabilityNames.scrollHorizontal,
        GridCapabilityNames.visible,
    ]
    for name in names {
        #expect(name.hasPrefix("grid."), "\(name) must start with 'grid.'")
    }
}

@Test func gridTabSelectParsingSupportsIndexAndIdentifierTargets() throws {
    #expect(try GridTabSelectPayload(index: 1, id: nil).selection() == .index(1))
    #expect(try GridTabSelectPayload(index: nil, id: "feed").selection() == .tab(.feed))
}

@Test func gridHorizontalScrollRejectsAmbiguousTargets() {
    do {
        _ = try GridScrollHorizontalPayload(direction: "next", index: nil, id: "items").target()
        Issue.record("expected parseHorizontalScroll to reject multiple target selectors")
    } catch let error as UIKitDemoCapabilityError {
        #expect(error == .missingScrollTarget)
    } catch {
        Issue.record("expected UIKitDemoCapabilityError, got \(error)")
    }
}

@Test func tabSelectResponseAlwaysIncludesStatusField() {
    let response = GridTabSelectResponse(selectedTab: .init(for: .feed))

    #expect(response.status == "ok")
    #expect(response.selectedTab == .init(for: .feed))
    #expect(response.error == nil)
}
