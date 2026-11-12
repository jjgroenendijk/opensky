// The places and targets a package names: locations, aliases, and patrol paths.

import OpenSkyActorPresentation
import OpenSkyActorsInterface
public import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyNavigation
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
public import OpenSkyWorldState
import simd

extension AIPackageMovesAdapter {
    public var places: Places {
        Places(owner: self, game: game)
    }

    public struct Places {
        let owner: AIPackageMovesAdapter
        let game: any AIPackageMovesHost

        public static func placedPosition(_ entry: RuntimeReferenceEntry) -> SIMD3<Float>? {
            entry.placedActor?.placement.position ?? entry.placedReference?.placement.position
        }

        /// Places OpenSky can name: a reference, a reference alias, and the actor itself.
        public func packagePlace(
            of location: Package.Location, actor: ReferenceKey, aliasQuest: FormID?
        ) -> PackagePlace? {
            let point: SIMD3<Float>? = switch location.kind {
            case .nearReference, .inCell:
                location.formID
                    .flatMap { game.streamer.residentReferenceIndex().entry(for: $0) }
                    .flatMap(Self.placedPosition)
            case .referenceAlias:
                aliasQuest
                    .flatMap {
                        game.scripts.bridge?.questRuntime?.aliasResolution()
                            .reference(alias: location.value, in: $0)
                    }
                    .flatMap(owner.packageActorPosition)
            case .nearSelf, .nearPackageStart:
                owner.packageActorPosition(actor)
            case .nearEditorLocation:
                game.streamer.referenceEntry(key: actor).flatMap(Self.placedPosition)
            default:
                nil
            }
            return point.map { PackagePlace(point: $0, radius: location.radius) }
        }

        /// Each running quest's alias packages, the higher-priority quest first.
        public func packageAliasStacks() -> [ReferenceKey: PackageAliasStack] {
            guard let quests = game.scripts.bridge?.questRuntime else { return [:] }
            var stacks: [ReferenceKey: PackageAliasStack] = [:]
            let running = quests.runningQuests().map(\.quest).sorted { $0.priority > $1.priority }
            for quest in running where quest.aliases.contains(where: { !$0.packages.isEmpty }) {
                guard let table = attempt({ try quests.aliasState(of: quest.formID) })
                else { continue }
                for alias in quest.aliases where !alias.packages.isEmpty {
                    guard
                        let actor = table.reference(forAlias: alias.id),
                        stacks[actor] == nil
                    else {
                        continue
                    }
                    stacks[actor] = PackageAliasStack(packages: alias.packages, quest: quest.formID)
                }
            }
            return stacks
        }

        public func packagePatrolPath(
            from start: Package.Target, actor _: ReferenceKey, aliasQuest: FormID?
        ) -> [SIMD3<Float>]? {
            guard
                let key = packageTargetKey(start, aliasQuest: aliasQuest),
                let lookup = game.streamer.placedRecords
            else { return nil }
            let path = lookup.linkedChain(from: key)
            return path.isEmpty ? nil : path
        }

        /// The reference a package's single-reference input names.
        public func packageTargetKey(
            _ target: Package.Target,
            aliasQuest: FormID?
        ) -> ReferenceKey? {
            switch target.kind {
            case .specificReference:
                game.scripts.bridge?.formIDResolver.flatMap {
                    ReferenceKey.resolve(FormID(target.value), using: $0)
                }
            case .referenceAlias:
                aliasQuest.flatMap {
                    game.scripts.bridge?.questRuntime?.aliasResolution()
                        .reference(alias: target.value, in: $0)
                }
            default:
                nil
            }
        }
    }
}

extension AIPackageMovesAdapter {
    func packagePlace(
        of location: Package.Location, actor: ReferenceKey, aliasQuest: FormID?
    ) -> PackagePlace? {
        places.packagePlace(of: location, actor: actor, aliasQuest: aliasQuest)
    }

    func packageAliasStacks() -> [ReferenceKey: PackageAliasStack] {
        places.packageAliasStacks()
    }

    func packagePatrolPath(
        from start: Package.Target, actor: ReferenceKey, aliasQuest: FormID?
    ) -> [SIMD3<Float>]? {
        places.packagePatrolPath(from: start, actor: actor, aliasQuest: aliasQuest)
    }
}
