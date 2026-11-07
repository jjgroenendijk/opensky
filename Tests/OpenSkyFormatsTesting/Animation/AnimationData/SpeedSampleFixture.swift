// Builds a `speeddatasinglefile.txt` in code: a count line, a name line per project,
// then one binary block per project. Layout: docs/formats/speed-data.md.

import Foundation

public enum SpeedSampleFixture {
    /// One state's directions, each a key and (blend, ground) pairs in file order.
    public struct State {
        public let key: Int32
        public let directions: [(key: Float, pairs: [(blend: Float, ground: Float)])]

        public init(
            key: Int32, directions: [(key: Float, pairs: [(blend: Float, ground: Float)])]
        ) {
            self.key = key
            self.directions = directions
        }
    }

    public static func file(
        projects: [(name: String, states: [State])], version: Int32 = 1
    ) -> Data {
        var data = Data("\(projects.count)\r\n".utf8)
        for project in projects {
            data += Data("\(project.name)\r\n".utf8)
        }
        for project in projects {
            append(version, to: &data)
            append(Int32(project.states.count), to: &data)
            for state in project.states {
                append(state.key, to: &data)
                append(Int32(state.directions.count), to: &data)
                for direction in state.directions {
                    append(direction.key.bitPattern, to: &data)
                    append(Int32(direction.pairs.count), to: &data)
                    for pair in direction.pairs {
                        append(pair.blend.bitPattern, to: &data)
                        append(pair.ground.bitPattern, to: &data)
                    }
                }
            }
        }
        return data
    }

    private static func append(_ value: some FixedWidthInteger, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}
