import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import RemoMacrosPlugin

// Note: Uses XCTest (not Swift Testing) because SwiftSyntaxMacrosTestSupport
// only provides assertMacroExpansion as an XCTest-style API.

let testMacros: [String: Macro.Type] = ["remo": RemoInlineMacro.self]
let testMacrosScoped: [String: Macro.Type] = ["remo": RemoScopedMacro.self]
let testMacrosBlock: [String: Macro.Type] = ["remo": RemoBlockMacro.self]
let testMacrosBlockAsync: [String: Macro.Type] = ["remo": RemoBlockAsyncMacro.self]
// Note: SwiftSyntaxMacrosTestSupport uses [String: Macro.Type], which cannot hold two
// implementations under the same key. The sync and async block forms are therefore tested
// in separate dictionaries above. Real-world overload dispatch (sync `#remo {}` vs
// `await #remo {}`) is validated by the example app, which uses both forms and builds
// successfully.

final class RemoMacrosTests: XCTestCase {
    func testInlineFormWithParams() {
        assertMacroExpansion(
            """
            #remo("counter.increment") { params in
                let amount: Int = params["amount", default: 1]
                return ["status": "ok"]
            }
            """,
            expandedSource: """
            {
                #if DEBUG
                RemoSwift.Remo.register("counter.increment") { (__rawParams: [String: Any]) -> [String: Any] in
                    let params = RemoSwift.RemoParams(__rawParams)

                        let amount: Int = params["amount", default: 1]
                        return ["status": "ok"]
                }
                #endif
            }()
            """,
            macros: testMacros
        )
    }

    func testInlineFormNoParams() {
        assertMacroExpansion(
            """
            #remo("items.clear") { _ in
                return ["status": "ok"]
            }
            """,
            expandedSource: """
            {
                #if DEBUG
                RemoSwift.Remo.register("items.clear") { (__rawParams: [String: Any]) -> [String: Any] in
                    let _ = RemoSwift.RemoParams(__rawParams)

                        return ["status": "ok"]
                }
                #endif
            }()
            """,
            macros: testMacros
        )
    }

    func testInlineFormMultipleBodyLines() {
        assertMacroExpansion(
            """
            #remo("state.set") { params in
                let key: String = params["key", default: ""]
                let value: String = params["value", default: ""]
                return ["status": "ok"]
            }
            """,
            expandedSource: """
            {
                #if DEBUG
                RemoSwift.Remo.register("state.set") { (__rawParams: [String: Any]) -> [String: Any] in
                    let params = RemoSwift.RemoParams(__rawParams)

                        let key: String = params["key", default: ""]
                        let value: String = params["value", default: ""]
                        return ["status": "ok"]
                }
                #endif
            }()
            """,
            macros: testMacros
        )
    }

    func testScopedForm() {
        assertMacroExpansion(
            """
            #remo("detail.getInfo", scopedTo: self) { params in
                return ["item": "test"]
            }
            """,
            expandedSource: """
            {
                #if DEBUG
                RemoSwift._RemoLifecycle.registerScoped(owner: self, name: "detail.getInfo") { (__rawParams: [String: Any]) -> [String: Any] in
                    let params = RemoSwift.RemoParams(__rawParams)

                        return ["item": "test"]
                }
                #endif
            }()
            """,
            macros: testMacrosScoped
        )
    }

    func testBlockForm() {
        assertMacroExpansion(
            """
            #remo {
                Remo.register("navigate") { _ in [:] }
                Remo.register("state.get") { _ in [:] }
            }
            """,
            expandedSource: """
            {
                #if DEBUG

                    Remo.register("navigate") { _ in
                    [:]
                }
                    Remo.register("state.get") { _ in
                    [:]
                }
                #endif
            }()
            """,
            macros: testMacrosBlock
        )
    }

    func testBlockAsyncForm() {
        assertMacroExpansion(
            """
            #remo {
                Remo.register("navigate") { _ in [:] }
                await Remo.keepAlive("navigate")
            }
            """,
            expandedSource: """
            { () async in
                #if DEBUG

                    Remo.register("navigate") { _ in
                    [:]
                }
                    await Remo.keepAlive("navigate")
                #endif
            }()
            """,
            macros: testMacrosBlockAsync
        )
    }
}
