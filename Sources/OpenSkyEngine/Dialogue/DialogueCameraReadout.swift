// Dialogue-camera readout text (issue #427): the device-free half of the
// camera's verification surface.
//
// Every line is a pure function of one `DialogueCameraSnapshot`, exactly as
// `DialogueReadout` is of one `DialogueControlSnapshot`, so the wording is
// asserted without AppKit, without a Metal device and without a game install.

import simd

nonisolated enum DialogueCameraReadout {
    /// Who the camera is framing, from where, and what it hands back when it
    /// lets go — the three things the acceptance question "did entering and
    /// leaving a conversation restore the previous camera" is answered from.
    static func cameraText(for snapshot: DialogueCameraSnapshot) -> String {
        guard snapshot.isAvailable else {
            return "Dialogue camera: unavailable (no renderer)"
        }
        let subject = snapshot.speakerName.map { name in
            name + (snapshot.speakerKey.map { " (\($0))" } ?? "")
        } ?? "nobody"
        let header = snapshot.isEngaged
            ? "Dialogue camera: engaged on \(subject)"
            : "Dialogue camera: released"
        let forced = "Forced: " + (snapshot.isForced
            ? "yes, on \(snapshot.target.label.lowercased())"
            : "no, follows the conversation")
        let restore = "Restores: \(snapshot.restoreMode) at "
            + "\(rounded(snapshot.restoreFOVYDegrees)) degrees"
        return ([header, forced] + framingLines(snapshot) + [restore]).joined(separator: "\n")
    }

    /// Where the eye ended up, or the one line that says it has not resolved.
    private static func framingLines(_ snapshot: DialogueCameraSnapshot) -> [String] {
        guard let pose = snapshot.pose else {
            return ["Framing: not resolved"]
        }
        let squeeze = pose.isCollisionLimited ? "pulled in by geometry" : "clear"
        return [
            "Pivot: \(point(pose.target)) · eye: \(point(pose.eye))",
            "Framing: \(rounded(pose.distance)) units, \(squeeze) · "
                + "yaw \(rounded(MatrixMath.degrees(fromRadians: pose.yaw))) · "
                + "pitch \(rounded(MatrixMath.degrees(fromRadians: pose.pitch)))",
            "Field of view: \(rounded(MatrixMath.degrees(fromRadians: DialogueCamera.fovYRadians)))"
                + " degrees while engaged"
        ]
    }

    /// What the speaker focus did: the turn, and the package it is holding.
    static func speakerText(for snapshot: DialogueCameraSnapshot) -> String {
        guard snapshot.isAvailable else {
            return "Speaker focus: unavailable (no renderer)"
        }
        guard let focus = snapshot.speakerFocus else {
            return "Speaker focus: nobody held"
        }
        let turn = focus.isSettled
            ? "facing the player"
            : "turning to face the player"
        let package = focus.isPackageSuspended
            ? "package \(focus.packageEditorID ?? "none") suspended"
            : "package running"
        return """
        Speaker focus: \(turn) · movement \(focus.movementState)
        Yaw: \(rounded(focus.yawDegrees)) of \(rounded(focus.targetYawDegrees)) degrees
        Package: \(package)
        """
    }

    /// Result of the last control, or the standing instruction when none has
    /// run.
    static func outcomeText(for snapshot: DialogueCameraSnapshot) -> String {
        snapshot.lastOutcome
            ?? "Open a conversation, or force the camera onto the selected actor."
    }

    /// One world-space point, rounded to whole units: the readout is for
    /// telling one framing from another, not for measuring one.
    private static func point(_ value: SIMD3<Float>) -> String {
        "(\(rounded(value.x)), \(rounded(value.y)), \(rounded(value.z)))"
    }

    /// One number at whole-unit precision, which is the resolution every
    /// quantity in these lines is read at.
    private static func rounded(_ value: Float) -> String {
        value.isFinite ? String(Int(value.rounded())) : "-"
    }
}
