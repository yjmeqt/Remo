import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import RemoMacrosPlugin

// Note: Uses XCTest (not Swift Testing) because SwiftSyntaxMacrosTestSupport
// only provides assertMacroExpansion as an XCTest-style API.

let testMacrosScopeAsync: [String: Macro.Type] = ["remoScope": RemoScopeAsyncMacro.self]
let testMacrosScopeSync: [String: Macro.Type] = ["remoScope": RemoScopeSyncMacro.self]
let testMacrosRemoStmt: [String: Macro.Type] = ["RemoStmtTest": RemoContainerStmtMacro.self]
let testMacrosRemoAsync: [String: Macro.Type] = ["RemoAsyncTest": RemoContainerAsyncStmtMacro.self]
let testMacrosCapTyped: [String: Macro.Type] = ["remoCapTyped": RemoCapTypedMacro.self]
// Uses a different key so inner #remoCap(Type.self) calls are not expanded by the test harness,
// while still being detected by collectCapabilityRefs (which looks for macroName == "remoCap").
let testMacrosScopeAsyncAlt: [String: Macro.Type] = ["remoScopeAsync": RemoScopeAsyncMacro.self]
let testMacrosScopeSyncAlt: [String: Macro.Type] = ["remoScopeSync": RemoScopeSyncMacro.self]

final class RemoMacrosTests: XCTestCase {

    // MARK: - #Remo

    func testRemoStatementWrapsDebugOnlyStatements() {
        assertMacroExpansion(
            """
            #RemoStmtTest {
                enum Navigate: RemoCapability {
                    static let name = "navigate"
                    typealias Response = RemoOK
                }
            }
            """,
            expandedSource: """
            {
                #if DEBUG

                    enum Navigate: RemoCapability {
                        static let name = "navigate"
                        typealias Response = RemoOK
                    }
                #endif
            }()
            """,
            macros: testMacrosRemoStmt
        )
    }

    func testRemoAsyncStatementWrapsDebugOnlyStatements() {
        assertMacroExpansion(
            """
            #RemoAsyncTest {
                enum Navigate: RemoCapability {
                    static let name = "navigate"
                    struct Request: Decodable { let route: String? }
                    typealias Response = RemoOK
                }

                await #remoScope {
                    #remoCap(Navigate.self) { req in
                        _ = req.route
                        return RemoOK()
                    }
                }
            }
            """,
            expandedSource: """
            { () async in
                #if DEBUG

                    enum Navigate: RemoCapability {
                        static let name = "navigate"
                        struct Request: Decodable {
                            let route: String?
                        }
                        typealias Response = RemoOK
                    }

                    await #remoScope {
                        #remoCap(Navigate.self) { req in
                            _ = req.route
                            return RemoOK()
                        }
                    }
                #endif
            }()
            """,
            macros: testMacrosRemoAsync
        )
    }

    // MARK: - #remoCap

    func testTypedCapDecodesRequestAndEncodesResponse() {
        assertMacroExpansion(
            """
            #remoCapTyped(Navigate.self) { req in
                _ = req.route
                return RemoOK()
            }
            """,
            expandedSource: """
            {
                #if DEBUG
                _RemoRuntime.register(Navigate.name) { (__rawParams: [String: Any]) -> [String: Any] in
                    let __request: Navigate.Request
                    do {
                        let __data = try Foundation.JSONSerialization.data(withJSONObject: __rawParams)
                        __request = try Foundation.JSONDecoder().decode(Navigate.Request.self, from: __data)
                    } catch {
                        return ["error": "decode failed: \\(error.localizedDescription)"]
                    }
                    let __response = { req in

                            _ = req.route
                            return RemoOK()
                    }(__request)
                    do {
                        let __data = try Foundation.JSONEncoder().encode(__response)
                        guard let __object = try Foundation.JSONSerialization.jsonObject(with: __data) as? [String: Any] else {
                            return ["error": "encode failed: response must be a top-level JSON object"]
                        }
                        return __object
                    } catch {
                        return ["error": "encode failed: \\(error.localizedDescription)"]
                    }
                }
                #endif
            }()
            """,
            macros: testMacrosCapTyped
        )
    }

    // MARK: - #remoScope (async)

    func testScopeAsyncAutoKeepAliveCollectsTypedNames() {
        assertMacroExpansion(
            """
            #remoScopeAsync {
                #remoCap(Navigate.self) { req in
                    return RemoOK()
                }
                #remoCap(StateGet.self) { req in
                    return StateGet.Response(value: req.key)
                }
            }
            """,
            expandedSource: """
            { () async in
                #if DEBUG

                    #remoCap(Navigate.self) { req in
                        return RemoOK()
                    }
                    #remoCap(StateGet.self) { req in
                        return StateGet.Response(value: req.key)
                    }
                await _RemoRuntime.keepAlive(Navigate.name, StateGet.name)
                #endif
            }()
            """,
            macros: testMacrosScopeAsyncAlt
        )
    }

    func testScopeAsyncStripsExplicitKeepAlive() {
        assertMacroExpansion(
            """
            #remoScopeAsync {
                #remoCap(Navigate.self) { req in
                    return RemoOK()
                }
                await Remo.keepAlive("navigate")
            }
            """,
            expandedSource: """
            { () async in
                #if DEBUG

                    #remoCap(Navigate.self) { req in
                        return RemoOK()
                    }
                await _RemoRuntime.keepAlive(Navigate.name)
                #endif
            }()
            """,
            macros: testMacrosScopeAsyncAlt
        )
    }

    func testScopeAsyncWithoutCapabilitiesLeavesBodyUntouched() {
        assertMacroExpansion(
            """
            #remoScope {
                print("noop")
            }
            """,
            expandedSource: """
            { () async in
                #if DEBUG

                    print("noop")
                #endif
            }()
            """,
            macros: testMacrosScopeAsync
        )
    }

    // MARK: - #remoScope(scopedTo:)

    func testScopeSyncAutoTrackNamesCollectsTypedNames() {
        assertMacroExpansion(
            """
            #remoScopeSync(scopedTo: self) {
                #remoCap(GridVisible.self) { _ in
                    return GridVisible.Response(items: [])
                }
                #remoCap(GridScroll.self) { req in
                    return RemoOK()
                }
            }
            """,
            expandedSource: """
            {
                #if DEBUG

                    #remoCap(GridVisible.self) { _ in
                        return GridVisible.Response(items: [])
                    }
                    #remoCap(GridScroll.self) { req in
                        return RemoOK()
                    }
                _RemoLifecycle.trackNames([GridVisible.name, GridScroll.name], owner: self)
                #endif
            }()
            """,
            macros: testMacrosScopeSyncAlt
        )
    }

    func testScopeSyncWithoutCapabilitiesLeavesBodyUntouched() {
        assertMacroExpansion(
            """
            #remoScope(scopedTo: self) {
                print("noop")
            }
            """,
            expandedSource: """
            {
                #if DEBUG

                    print("noop")
                #endif
            }()
            """,
            macros: testMacrosScopeSync
        )
    }
}
