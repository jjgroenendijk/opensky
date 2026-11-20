// The `menu` commands parse to their argument types.

import OpenSkyCLIArguments
import Testing

extension CommandLineTests {
    @Test func theMenuCommandsParse() throws {
        _ = try command(["menu", "container", "--mode", "barter"], as: MenuArguments.Container.self)
        _ = try command(["menu", "magic", "--ticks", "5"], as: MenuArguments.Magic.self)
    }
}
