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
