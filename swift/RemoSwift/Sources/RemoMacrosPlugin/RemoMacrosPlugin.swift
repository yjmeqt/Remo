import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct RemoMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        RemoContainerStmtMacro.self,
        RemoContainerAsyncStmtMacro.self,
        RemoCapTypedMacro.self,
        RemoScopeAsyncMacro.self,
        RemoScopeSyncMacro.self,
    ]
}

// MARK: - Error

enum RemoMacroError: Error, CustomStringConvertible {
    case missingTypeArgument
    case missingScopedToArgument
    case missingHandler
    case missingBody

    var description: String {
        switch self {
        case .missingTypeArgument: return "#remoCap typed form requires a `Type.self` first argument"
        case .missingScopedToArgument: return "#remoScope scoped form requires a `scopedTo:` argument"
        case .missingHandler: return "#remoCap requires a trailing closure handler"
        case .missingBody: return "#remoScope requires a trailing closure body"
        }
    }
}

// MARK: - Helpers

func extractTypeName(from node: some FreestandingMacroExpansionSyntax) throws -> String {
    guard let firstArg = node.arguments.first else {
        throw RemoMacroError.missingTypeArgument
    }

    let text = firstArg.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.hasSuffix(".self") else {
        throw RemoMacroError.missingTypeArgument
    }
    return String(text.dropLast(".self".count))
}

func extractHandler(from node: some FreestandingMacroExpansionSyntax) throws -> ClosureExprSyntax {
    if let trailing = node.trailingClosure {
        return trailing
    }
    if let last = node.arguments.last,
       let closure = last.expression.as(ClosureExprSyntax.self) {
        return closure
    }
    throw RemoMacroError.missingHandler
}

func extractParamName(from closure: ClosureExprSyntax) -> String {
    if let params = closure.signature?.parameterClause?.as(ClosureParameterClauseSyntax.self),
       let first = params.parameters.first {
        return first.firstName.text
    }
    if let shorthand = closure.signature?.parameterClause?.as(ClosureShorthandParameterListSyntax.self),
       let first = shorthand.first {
        return first.name.text
    }
    return "_"
}

/// Walk the syntax tree to find `#remoCap(Type.self)` expressions and return emitted name refs.
func collectCapabilityRefs(from syntax: Syntax, into refs: inout [String]) {
    if let macro = syntax.as(MacroExpansionExprSyntax.self),
       macro.macroName.text == "remoCap",
       let firstArg = macro.arguments.first,
       firstArg.label == nil {
        let text = firstArg.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix(".self") {
            refs.append("\(String(text.dropLast(".self".count))).name")
            return
        }
    }
    for child in syntax.children(viewMode: .sourceAccurate) {
        collectCapabilityRefs(from: child, into: &refs)
    }
}

func wrapDebugIIFE(body: CodeBlockItemListSyntax) -> ExprSyntax {
    """
    {
        #if DEBUG
        \(body)
        #endif
    }()
    """
}

func wrapDebugAsyncIIFE(body: CodeBlockItemListSyntax) -> ExprSyntax {
    """
    { () async in
        #if DEBUG
        \(body)
        #endif
    }()
    """
}

// MARK: - RemoContainer macros

public struct RemoContainerStmtMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let closure = node.trailingClosure else {
            throw RemoMacroError.missingBody
        }
        return wrapDebugIIFE(body: closure.statements)
    }
}

public struct RemoContainerAsyncStmtMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let closure = node.trailingClosure else {
            throw RemoMacroError.missingBody
        }
        return wrapDebugAsyncIIFE(body: closure.statements)
    }
}

// MARK: - RemoCap macros

/// `#remoCap(Type.self) { handler }` — register a typed capability, stripped in release.
public struct RemoCapTypedMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        let typeName = try extractTypeName(from: node)
        let handler = try extractHandler(from: node)
        let paramName = extractParamName(from: handler)
        let body = handler.statements

        return """
        {
            #if DEBUG
            _RemoRuntime.register(\(raw: typeName).name) { (__rawParams: [String: Any]) -> [String: Any] in
                let __request: \(raw: typeName).Request
                do {
                    let __data = try Foundation.JSONSerialization.data(withJSONObject: __rawParams)
                    __request = try Foundation.JSONDecoder().decode(\(raw: typeName).Request.self, from: __data)
                } catch {
                    return ["error": "decode failed: \\(error.localizedDescription)"]
                }
                let __response = { \(raw: paramName) in
                    \(body)
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
        """
    }
}

/// Check if a syntax node contains a `.keepAlive(...)` member access.
func containsKeepAlive(_ syntax: Syntax) -> Bool {
    if let memberAccess = syntax.as(MemberAccessExprSyntax.self),
       memberAccess.declName.baseName.text == "keepAlive" {
        return true
    }
    for child in syntax.children(viewMode: .sourceAccurate) {
        if containsKeepAlive(child) { return true }
    }
    return false
}

// MARK: - RemoScopeAsyncMacro

/// `await #remoScope { ... }` — async lifecycle scope for SwiftUI `.task {}`.
///
/// Extracts capability names from nested `#remoCap(Type.self)` calls, strips
/// any explicit `keepAlive(...)` call, and auto-generates the runtime lifetime
/// helper at the end.
public struct RemoScopeAsyncMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let closure = node.trailingClosure else {
            throw RemoMacroError.missingBody
        }
        let body = closure.statements

        var names: [String] = []
        for item in body {
            collectCapabilityRefs(from: Syntax(item), into: &names)
        }

        guard !names.isEmpty else {
            return """
            { () async in
                #if DEBUG
                \(body)
                #endif
            }()
            """
        }

        // Strip explicit keepAlive calls — auto-generated below.
        let cleanedBody = body.filter { !containsKeepAlive(Syntax($0)) }
        let namesLiteral = names.joined(separator: ", ")

        return """
        { () async in
            #if DEBUG
            \(cleanedBody)
            await _RemoRuntime.keepAlive(\(raw: namesLiteral))
            #endif
        }()
        """
    }
}

// MARK: - RemoScopeSyncMacro

/// `#remoScope(scopedTo: self) { ... }` — UIKit lifecycle scope.
///
/// Extracts capability names from nested `#remoCap(Type.self)` calls and
/// auto-generates `_RemoLifecycle.trackNames(...)` to unregister them on
/// `viewDidDisappear`.
public struct RemoScopeSyncMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let ownerArg = node.arguments.first(where: { $0.label?.text == "scopedTo" }) else {
            throw RemoMacroError.missingScopedToArgument
        }
        let ownerExpr = ownerArg.expression

        guard let closure = node.trailingClosure else {
            throw RemoMacroError.missingBody
        }
        let body = closure.statements

        var names: [String] = []
        for item in body {
            collectCapabilityRefs(from: Syntax(item), into: &names)
        }

        let namesArray = names.joined(separator: ", ")

        if names.isEmpty {
            return """
            {
                #if DEBUG
                \(body)
                #endif
            }()
            """
        }

        return """
        {
            #if DEBUG
            \(body)
            _RemoLifecycle.trackNames([\(raw: namesArray)], owner: \(ownerExpr))
            #endif
        }()
        """
    }
}
