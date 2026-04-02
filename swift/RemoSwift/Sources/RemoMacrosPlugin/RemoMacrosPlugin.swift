import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct RemoMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        RemoInlineMacro.self,
        RemoScopedMacro.self,
        RemoBlockMacro.self,
    ]
}

// MARK: - Error

enum RemoMacroError: Error, CustomStringConvertible {
    case missingNameArgument
    case missingScopedToArgument
    case missingHandler
    case missingBody

    var description: String {
        switch self {
        case .missingNameArgument: return "#remo requires a string literal as its first argument"
        case .missingScopedToArgument: return "#remo scoped form requires a `scopedTo:` argument"
        case .missingHandler: return "#remo requires a trailing closure handler"
        case .missingBody: return "#remo { } requires a trailing closure body"
        }
    }
}

// MARK: - Helpers

func extractName(from node: some FreestandingMacroExpansionSyntax) throws -> String {
    guard let firstArg = node.arguments.first,
          let literal = firstArg.expression.as(StringLiteralExprSyntax.self),
          let segment = literal.segments.first?.as(StringSegmentSyntax.self)
    else {
        throw RemoMacroError.missingNameArgument
    }
    return segment.content.text
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

// MARK: - RemoInlineMacro

public struct RemoInlineMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        let name = try extractName(from: node)
        let handler = try extractHandler(from: node)
        let paramName = extractParamName(from: handler)
        let body = handler.statements

        return """
        {
            #if DEBUG
            RemoSwift.Remo.register(\(literal: name)) { (__rawParams: [String: Any]) -> [String: Any] in
                let \(raw: paramName) = RemoSwift.RemoParams(__rawParams)
                \(body)
            }
            #endif
        }()
        """
    }
}

// MARK: - RemoScopedMacro

public struct RemoScopedMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        let name = try extractName(from: node)
        let handler = try extractHandler(from: node)
        let paramName = extractParamName(from: handler)
        let body = handler.statements

        guard let ownerArg = node.arguments.first(where: { $0.label?.text == "scopedTo" }) else {
            throw RemoMacroError.missingScopedToArgument
        }
        let ownerExpr = ownerArg.expression

        return """
        {
            #if DEBUG
            RemoSwift._RemoLifecycle.registerScoped(owner: \(ownerExpr), name: \(literal: name)) { (__rawParams: [String: Any]) -> [String: Any] in
                let \(raw: paramName) = RemoSwift.RemoParams(__rawParams)
                \(body)
            }
            #endif
        }()
        """
    }
}

// MARK: - RemoBlockMacro

public struct RemoBlockMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let body = node.trailingClosure?.statements else {
            throw RemoMacroError.missingBody
        }

        return """
        {
            #if DEBUG
            \(body)
            #endif
        }()
        """
    }
}
