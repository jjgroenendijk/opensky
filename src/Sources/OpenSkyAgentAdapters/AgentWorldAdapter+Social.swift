// `state social`: NPC conversations, watchers, finders, timers, and the speech state.

import OpenSkyAgentControl
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyQuestsInterface
public import OpenSkySessionInterface

/// What `state social` reads from the session.
@MainActor
public protocol AgentSocialHost: AnyObject, SendableMetatype {
    var dialogue: any DialoguePort { get }
    var faceMorphs: any FaceMorphPort { get }
    var storyManager: any StoryManagerPort { get }
}

extension AgentWorldAdapter {
    /// The answer to `openskycli game state social`: each conversation and its phase,
    /// the fight watchers, the checked bodies, the social timers, and the events sent.
    func socialState() -> AgentJSON {
        SocialReads(owner: self).socialState()
    }

    private func socialExtras() -> [String: AgentJSON] {
        SocialReads(owner: self).socialExtras()
    }
}

extension AgentWorldAdapter {
    /// Builds the agent's readout of the social and dialogue state.
    struct SocialReads {
        let owner: AgentWorldAdapter

        func socialState() -> AgentJSON {
            let hub = owner.hub
            let social = hub.hosts.storyManager.social
            let state = social.state
            func key(_ key: ReferenceKey?) -> AgentJSON {
                key.map { .string($0.description) } ?? .null
            }
            func keyed(_ values: [ReferenceKey: Double]) -> AgentJSON {
                let pairs = values.map { ($0.key.description, AgentJSON.number($0.value)) }
                return .object(Dictionary(uniqueKeysWithValues: pairs))
            }
            let conversations = state.conversations.map { talk -> AgentJSON in
                let phase = switch talk.phase {
                case .waitingForAnswer: "waitingForAnswer"
                case .approaching: "approaching"
                case .talking: "talking"
                }
                return [
                    "speaker": key(talk.speaker), "partner": key(talk.partner),
                    "phase": .string(phase), "startedAt": .number(talk.startedAt)
                ]
            }
            let watchers = state.spectators.sorted { $0.key < $1.key }.map { watcher -> AgentJSON in
                [
                    "watcher": key(watcher.key),
                    "threats": .array(watcher.value.threats.map { key($0.attacker) }),
                    "commentTimer": .number(watcher.value.commentTimer),
                    "backsOff": .bool(watcher.value.backOffGoal != nil)
                ]
            }
            let finders = state.finders.sorted { $0.key < $1.key }.map { finder -> AgentJSON in
                ["finder": key(finder.key), "body": key(finder.value.body)]
            }
            var sent: [String: AgentJSON] = [:]
            for (code, count) in social.sentCounts {
                sent[code.description] = .number(Double(count))
            }
            let main: [String: AgentJSON] = [
                "conversations": .array(conversations),
                "watchers": .array(watchers),
                "finders": .array(finders),
                "bodyChecks": keyed(state.bodyChecks),
                "socialTimers": keyed(state.socialTimers),
                "recentPartners": .object(Dictionary(uniqueKeysWithValues: state.recentPartners
                        .map {
                            (
                                $0.key.description,
                                .array($0.value.sorted().map { .string($0.description) })
                            )
                        })),
                "lookTargets": .object(Dictionary(
                    uniqueKeysWithValues: state.looks.compactMap { look in
                        look.value.target.map { (look.key.description, .string($0.description)) }
                    }
                )),
                "sent": .object(sent)
            ]
            return .object(main.merging(owner.socialExtras()) { first, _ in first })
        }

        func socialExtras() -> [String: AgentJSON] {
            let hub = owner.hub
            return [
                "emotions": .object(Dictionary(
                    uniqueKeysWithValues: hub.hosts.faceMorphs.emotionValues.map {
                        ($0.key.description, .number(Double($0.value)))
                    }
                )),
                "dialogueMode": .object(Dictionary(
                    uniqueKeysWithValues: hub.hosts.dialogue.dialogueMode.countdowns.map {
                        ($0.key.description, .number(Double($0.value)))
                    }
                )),
                "detection": .object(Dictionary(
                    uniqueKeysWithValues: hub.hosts.dialogue.detectionRecords.map {
                        ($0.key.description, .string($0.value.rawValue))
                    }
                ))
            ]
        }
    }
}
