// Shared footstep half of `AudioControlProviding` for the two panel fakes
// (issue #352). Both `FakeAudioProvider` and `FakeWorldProviders` hold one of
// these and forward to it, which is the same delegation their runtime-state
// and trigger halves already use to stay inside the strict-lint type-body cap.

@testable import opensky

@MainActor
final class FakeFootstepControls {
    var footstepsEnabled = true
    var currentFootstepSetDescription = FootstepStore.defaultSetEditorID
    var currentFootstepTags: [String] = []
    var lastFootstepDescription: String?
    var lastFootstepError: String?
    var footstepCounts: (routed: Int, played: Int) = (0, 0)
    /// Materials the section can pin (issue #358), and the pinned one.
    var footstepMaterialOptions: [(id: FormID, name: String)] = []
    var forcedFootstepMaterial: FormID?
    /// What the ground contact reports when nothing is pinned.
    var groundFootstepMaterialDescription = "none"

    var currentFootstepMaterialDescription: String {
        guard let forcedFootstepMaterial else { return groundFootstepMaterialDescription }
        let name = footstepMaterialOptions
            .first { $0.id == forcedFootstepMaterial }?.name
            ?? forcedFootstepMaterial.description
        return "\(name) (forced)"
    }

    /// Tags the Footsteps section forced, in order.
    private(set) var forcedFootstepTags: [String] = []
    /// Failure the next `forcePlayFootstep(tag:)` reports; nil means success.
    var footstepForceFailure: String?

    /// Mirrors the live bridge: a successful force names the file in the
    /// description the readout shows and moves both counters.
    func forcePlayFootstep(tag: String) -> String? {
        forcedFootstepTags.append(tag)
        guard footstepForceFailure == nil else { return footstepForceFailure }
        lastFootstepDescription = "\(tag): sound\\fx\\fst\\step.wav"
        footstepCounts = (footstepCounts.routed + 1, footstepCounts.played + 1)
        lastFootstepError = nil
        return nil
    }
}

extension FakeAudioProvider {
    var footstepsEnabled: Bool {
        get { footsteps.footstepsEnabled }
        set { footsteps.footstepsEnabled = newValue }
    }

    var currentFootstepSetDescription: String {
        footsteps.currentFootstepSetDescription
    }

    var currentFootstepTags: [String] {
        footsteps.currentFootstepTags
    }

    var lastFootstepDescription: String? {
        footsteps.lastFootstepDescription
    }

    var lastFootstepError: String? {
        footsteps.lastFootstepError
    }

    var footstepCounts: (routed: Int, played: Int) {
        footsteps.footstepCounts
    }

    var currentFootstepMaterialDescription: String {
        footsteps.currentFootstepMaterialDescription
    }

    var footstepMaterialOptions: [(id: FormID, name: String)] {
        footsteps.footstepMaterialOptions
    }

    var forcedFootstepMaterial: FormID? {
        get { footsteps.forcedFootstepMaterial }
        set { footsteps.forcedFootstepMaterial = newValue }
    }

    func forcePlayFootstep(tag: String) -> String? {
        footsteps.forcePlayFootstep(tag: tag)
    }
}

extension FakeWorldProviders {
    var footstepsEnabled: Bool {
        get { footsteps.footstepsEnabled }
        set { footsteps.footstepsEnabled = newValue }
    }

    var currentFootstepSetDescription: String {
        footsteps.currentFootstepSetDescription
    }

    var currentFootstepTags: [String] {
        footsteps.currentFootstepTags
    }

    var lastFootstepDescription: String? {
        footsteps.lastFootstepDescription
    }

    var lastFootstepError: String? {
        footsteps.lastFootstepError
    }

    var footstepCounts: (routed: Int, played: Int) {
        footsteps.footstepCounts
    }

    var currentFootstepMaterialDescription: String {
        footsteps.currentFootstepMaterialDescription
    }

    var footstepMaterialOptions: [(id: FormID, name: String)] {
        footsteps.footstepMaterialOptions
    }

    var forcedFootstepMaterial: FormID? {
        get { footsteps.forcedFootstepMaterial }
        set { footsteps.forcedFootstepMaterial = newValue }
    }

    func forcePlayFootstep(tag: String) -> String? {
        footsteps.forcePlayFootstep(tag: tag)
    }
}
