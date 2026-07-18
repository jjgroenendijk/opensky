// `vfs ls` / `vfs cat`: list and extract resources through the engine VFS —
// same resolution the renderer sees (loose over archives, archive priority).
// ls enumerates archives only (docs/formats/vfs.md); cat resolves loose
// files too. Extraction writes wherever the user points --out: their own
// data, their disk — nothing lands in the repo (AGENTS.md Legal & IP).

import Foundation

enum VFSCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let subcommand = try scanner.positional("ls|cat")
        switch subcommand {
        case "ls":
            try list(context: context, scanner: &scanner)
        case "cat":
            try cat(context: context, scanner: &scanner)
        default:
            throw CLIError.usage("unknown vfs subcommand: \(subcommand)")
        }
    }

    /// Prints "path<tab>archive" per entry. Optional pattern: fnmatch(3)
    /// wildcards (* ? [...]) when present, else substring match. Patterns
    /// are matched against canonical keys (lowercase, backslashes); "/" in
    /// the pattern is accepted and converted.
    private static func list(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let pattern = scanner.next()
        try scanner.finish()
        let entries = context.makeFileSystem().archiveEntries()
        guard !entries.isEmpty else {
            throw CLIError.failure("no archive entries — no readable .bsa in Data/?")
        }
        let matched = entries.filter { matches($0.path, pattern: pattern) }
        for entry in matched {
            print("\(entry.path)\t\(entry.archive)")
        }
        printError("[INFO] \(matched.count) of \(entries.count) archive entries")
    }

    private static func matches(_ path: String, pattern: String?) -> Bool {
        guard let pattern else { return true }
        let canonical = pattern.lowercased().replacingOccurrences(of: "/", with: "\\")
        guard canonical.contains(where: { "*?[".contains($0) }) else {
            return path.contains(canonical)
        }
        // FNM_NOESCAPE: canonical keys use backslash separators, so "\" must
        // stay a literal, not an escape.
        return fnmatch(canonical, path, FNM_NOESCAPE) == 0
    }

    private static func cat(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let output = try scanner.requiredOption("--out")
        let key = try scanner.positional("key")
        try scanner.finish()
        let data: Data
        do {
            data = try context.makeFileSystem().contents(forPath: key)
        } catch {
            throw CLIError.failure("cannot resolve \(key): \(String(describing: error))")
        }
        let url = URL(filePath: output)
        do {
            try data.write(to: url)
        } catch {
            throw CLIError.failure(
                "cannot write \(url.path(percentEncoded: false)): \(String(describing: error))"
            )
        }
        print("[INFO] wrote \(data.count) bytes -> \(url.path(percentEncoded: false))")
    }
}
