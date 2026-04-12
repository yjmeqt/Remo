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
        UIKitDemoCapabilityContract.Names.tabSelect,
        UIKitDemoCapabilityContract.Names.feedAppend,
        UIKitDemoCapabilityContract.Names.feedReset,
        UIKitDemoCapabilityContract.Names.scrollVertical,
        UIKitDemoCapabilityContract.Names.scrollHorizontal,
        UIKitDemoCapabilityContract.Names.visible,
    ]
    for name in names {
        #expect(name.hasPrefix("grid."), "\(name) must start with 'grid.'")
    }
}

@Test func gridTabSelectParsingSupportsIndexAndIdentifierTargets() throws {
    #expect(try UIKitDemoCapabilityContract.parseTabSelect(["index": 1]) == .index(1))
    #expect(try UIKitDemoCapabilityContract.parseTabSelect(["id": "feed"]) == .tab(.feed))
}

@Test func gridHorizontalScrollRejectsAmbiguousTargets() {
    do {
        _ = try UIKitDemoCapabilityContract.parseHorizontalScroll(["direction": "next", "id": "items"])
        Issue.record("expected parseHorizontalScroll to reject multiple target selectors")
    } catch let error as UIKitDemoCapabilityError {
        #expect(error == .missingScrollTarget)
    } catch {
        Issue.record("expected UIKitDemoCapabilityError, got \(error)")
    }
}
