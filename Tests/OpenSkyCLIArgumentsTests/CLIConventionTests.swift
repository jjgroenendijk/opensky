// The command-line conventions, checked over the whole command tree from the parser's
// own help dump. tools/lint/cli-conventions.sh checks the rules that need the source.

import ArgumentParser
import Foundation
import OpenSkyCLIArguments
import Testing

struct CLIConventionTests {
    private let commands = CommandTree.load()

    @Test func theHelpDumpDescribesTheWholeTree() {
        #expect(commands.count > 60)
        #expect(commands.contains { $0.path == "record find" })
    }

    @Test func commandAndOptionNamesAreLowercaseKebabCase() {
        for command in commands {
            #expect(isKebabCase(command.info.commandName), "\(command.path)")
            for name in command.options.flatMap(\.longNames) {
                #expect(isKebabCase(name), "\(command.path): --\(name)")
            }
            #expect(
                command.options.flatMap(\.shortNames).isEmpty,
                "\(command.path): a short option; spell options out in full"
            )
        }
    }

    @Test func everyCommandHasOneNameAndNoAlias() {
        for command in commands {
            #expect(command.info.aliases?.isEmpty ?? true, "\(command.path) has an alias")
        }
    }

    @Test func everyCommandAndArgumentHasASentenceOfHelp() {
        for command in commands where command.info.shouldDisplay {
            #expect(isSentence(command.info.abstract), "\(command.path): abstract")
            for argument in command.arguments where argument.shouldDisplay {
                #expect(
                    isSentence(argument.abstract),
                    "\(command.path): \(argument.displayName) needs a help sentence"
                )
            }
        }
    }

    @Test func aGroupTakesNoArgumentsAndALeafHasNoSubcommands() {
        for command in commands {
            let isGroup = !(command.info.subcommands ?? []).isEmpty
            let own = command.arguments
                .filter { $0.shouldDisplay && $0.displayName != "--data-root" }
            #expect(!isGroup || own.isEmpty, "\(command.path) is a group with its own arguments")
        }
    }

    @Test func choicesAreTypedNotSpelledIntoTheValueName() {
        for command in commands {
            for argument in command.arguments {
                let valueName = argument.valueName ?? ""
                #expect(
                    !valueName.contains("|"),
                    Comment(rawValue: "\(command.path): \(argument.displayName) <\(valueName)> "
                        + "is a choice; use an enum or a subcommand")
                )
            }
        }
    }

    @Test func optionValuesMayStartWithADash() {
        for command in commands {
            for option in command.options where option.kind == "option" {
                #expect(
                    option.parsingStrategy == "unconditional",
                    Comment(rawValue: "\(command.path): \(option.displayName) needs "
                        + "parsing: .unconditional, so --y -2 works")
                )
            }
        }
    }

    private func isKebabCase(_ text: String) -> Bool {
        text.range(of: #"^[a-z][a-z0-9]*(-[a-z0-9]+)*$"#, options: .regularExpression) != nil
    }

    private func isSentence(_ text: String?) -> Bool {
        guard let text, let first = text.first, first.isUppercase || first.isNumber else {
            return false
        }
        return text.hasSuffix(".")
    }
}
