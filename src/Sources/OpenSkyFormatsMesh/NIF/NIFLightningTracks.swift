// The tracks that feed a lightning controller: its own interpolators, or those a
// controller sequence names by interpolator ID. Layout: docs/formats/nif-controllers.md.

import Foundation
import OpenSkyFormatsCore

nonisolated extension NIFFile {
    struct LightningTrackDecoder {
        let file: NIFFile
        let sequences: [NIFFile.DecodedSequence]

        /// Sets the default tracks and the tracks of each sequence that feeds the controller.
        func fill(
            _ lightning: inout ParticleLightning,
            controller: NIFLightningController,
            index: Int32
        ) {
            var fed: [(sequence: NIFFile.DecodedSequence, tracks: LightningTracks)] = []
            for sequence in sequences {
                guard let feed = sequence.feeds[index] else { continue }
                let tracks = tracks(feed)
                fed.append((sequence, tracks))
                if let name = sequence.name?.lowercased(), lightning.sequenceTracks[name] == nil {
                    lightning.sequenceTracks[name] = tracks
                }
            }
            // A sequence that leaves the generation unset cannot start a bolt.
            let starting = fed.filter { !$0.tracks.generation.isEmpty }
            let chosen = NIFFile.ControllerSequenceDecoder.defaultSequence(starting.map(\.sequence))
            lightning.tracks = starting.first { $0.sequence == chosen }?.tracks ?? own(controller)
        }

        /// The interpolator IDs seen in the vanilla meshes. The other four values
        /// (subdivisions, branches, branch variation, length variation) have none there.
        private func tracks(_ feed: SequenceFeed) -> LightningTracks {
            var tracks = LightningTracks(timing: feed.timing)
            tracks.generation = bools(feed.interpolators["Generation"])
            tracks.mutation = bools(feed.interpolators["Mutation"])
            tracks.length = floats(feed.interpolators["Length"])
            tracks.width = floats(feed.interpolators["Width"])
            tracks.arcOffset = floats(feed.interpolators["ArcOffset"])
            return tracks
        }

        /// The controller's own interpolators, in nif.xml order; nil when none keys the
        /// generation.
        private func own(_ controller: NIFLightningController) -> LightningTracks? {
            let refs = controller.interpolatorRefs
            guard refs.count == 9 else { return nil }
            var tracks = LightningTracks(timing: controller.base.timing)
            tracks.generation = bools(refs[0])
            tracks.mutation = bools(refs[1])
            tracks.subdivisions = floats(refs[2])
            tracks.branches = floats(refs[3])
            tracks.branchVariation = floats(refs[4])
            tracks.length = floats(refs[5])
            tracks.lengthVariation = floats(refs[6])
            tracks.width = floats(refs[7])
            tracks.arcOffset = floats(refs[8])
            return tracks.generation.isEmpty ? nil : tracks
        }

        private func bools(_ ref: Int32?) -> [NIFKey<Bool>] {
            ref.flatMap { ref in
                attempt { try NIFFile.ParticleControllerDecoder.boolKeys(ref, file: file) }
            } ?? []
        }

        private func floats(_ ref: Int32?) -> [NIFKey<Float>] {
            ref.flatMap { ref in
                attempt { try NIFFile.ParticleControllerDecoder.floatKeys(ref, file: file) }
            } ?? []
        }
    }
}

/// What `nif --controllers` prints for one lightning controller.
nonisolated public struct NIFLightningReport: Equatable, Sendable {
    public struct Feed: Equatable, Sendable {
        public let sequence: String
        /// The interpolator ID, the interpolator's block type, and its key count.
        public let id: String
        public let type: String
        public let keys: Int
    }

    public let controller: Int
    public let target: Int
    public let targetType: String
    public let feeds: [Feed]
}

nonisolated extension NIFFile {
    public func lightningReports() throws -> [NIFLightningReport] {
        let sequences = try ControllerSequenceDecoder.sequences(file: self)
        return try blocks.indices.compactMap { index in
            guard let controller = Self.lightningController(blocks[index]) else { return nil }
            let target = Int(controller.base.targetRef)
            var feeds: [NIFLightningReport.Feed] = []
            for sequence in sequences {
                guard let feed = sequence.feeds[Int32(index)] else { continue }
                for (id, ref) in feed.interpolators.sorted(by: { $0.key < $1.key }) {
                    let type = blocks.indices.contains(Int(ref)) ? blocks[Int(ref)].typeName : "-"
                    let keys = try ParticleControllerDecoder.boolKeys(ref, file: self).count
                        + ParticleControllerDecoder.floatKeys(ref, file: self).count
                    feeds.append(NIFLightningReport.Feed(
                        sequence: sequence.name ?? "-", id: id, type: type, keys: keys
                    ))
                }
            }
            return NIFLightningReport(
                controller: index, target: target,
                targetType: blocks.indices.contains(target) ? blocks[target].typeName : "-",
                feeds: feeds
            )
        }
    }
}
