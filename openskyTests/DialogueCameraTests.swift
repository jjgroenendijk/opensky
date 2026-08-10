// Dialogue-camera framing, projection policy, and the speaker's turn
// (issue #427, roadmap item 17.4, scope point 6). Synthetic transforms only —
// no install, no device, no window.

@testable import opensky
import simd
import Testing

struct DialogueCameraTests {
    /// A speaker standing at the origin, head at the standard capsule's eye
    /// height, with the player two metres east of them. Every framing
    /// assertion below is against this one arrangement, so a change in the
    /// derivation moves one set of numbers rather than five.
    private static let speakerHead = SIMD3<Float>(0, 0, PlayerCapsule.standard.eyeHeight)
    private static let playerDistance: Float = 140
    private static let playerEye = SIMD3<Float>(
        playerDistance, 0, PlayerCapsule.standard.eyeHeight
    )

    private static var subject: DialogueCameraSubject {
        DialogueCameraSubject(headPosition: speakerHead, playerEyePosition: playerEye)
    }

    // MARK: - Derivation

    /// The framing distance is a derivation and not a stored constant:
    /// recomputing it from the capsule and the field of view has to give the
    /// same answer, which is what makes changing either input move the camera
    /// rather than silently disagree with the documentation.
    @Test
    func framingDistanceFramesHeadAndChestAtTheStatedFill() {
        let halfSpan = DialogueCamera.framedHeight() / 2
        let expected = (halfSpan / DialogueCamera.framingFillFraction)
            / tanf(DialogueCamera.fovYRadians / 2)
        #expect(abs(DialogueCamera.framingDistance() - expected) < 0.001)
        let halfViewHeight = DialogueCamera.framingDistance()
            * tanf(DialogueCamera.fovYRadians / 2)
        #expect(abs(halfSpan / halfViewHeight - DialogueCamera.framingFillFraction) < 0.001)
    }

    /// The span framed is the head and the chest, which is what makes this a
    /// conversation shot rather than the full-body shot third person frames.
    @Test
    func framedHeightIsTighterThanTheWholeCapsule() {
        #expect(DialogueCamera.framedHeight() == 96)
        #expect(DialogueCamera.framedHeight() < PlayerCapsule.standard.height)
        #expect(DialogueCamera.framingDistance() < ThirdPersonCamera.orbitDistance)
    }

    /// A conversation is projected at the world angle, which is the angle the
    /// scene pass projects with. A dialogue camera framed for a different one
    /// would be framed for a camera nobody looks through.
    @Test
    func framingFovIsTheSharedWorldAngle() {
        #expect(DialogueCamera.fovYRadians == FirstPersonCamera.defaultFOVYRadians)
        #expect(abs(DialogueCamera.fovYRadians - MatrixMath.radians(fromDegrees: 65)) < 1e-6)
    }

    // MARK: - Framing

    /// The camera aims at the speaker's head and stands on the side of them the
    /// player is on, one shoulder off the sightline.
    @Test
    func theEyeStandsOnThePlayersSideAndLooksAtTheHead() {
        var camera = DialogueCamera()
        let pose = camera.resolve(subject: Self.subject, collisionQuery: { _ in [] })
        #expect(pose.target == Self.speakerHead)
        // The player is east of the speaker, so the eye is too.
        #expect(pose.eye.x > Self.speakerHead.x)
        // Level with the player's own eye, which is where the shot is taken
        // from rather than from the height of whoever is being talked to.
        #expect(abs(pose.eye.z - Self.playerEye.z) < 0.001)
        // Looking back west at the head — but not dead west: the shoulder
        // offset swings the view about 8 degrees off the axis at this range,
        // which is exactly the three-quarter angle it exists to produce.
        #expect(abs(abs(pose.yaw) - .pi) < 0.2)
        #expect(abs(abs(pose.yaw) - .pi) > 0.05)
        // Level, because both heads are at the same height here.
        #expect(abs(pose.pitch) < 0.001)
        // One shoulder off the sightline, on the camera's right, which for a
        // camera looking west is +Y.
        #expect(abs(pose.eye.y - DialogueCamera.shoulderOffset) < 0.001)
        #expect(!pose.isCollisionLimited)
    }

    /// A player standing closer than the framing distance does not drag the
    /// camera in with them: the shot holds its framing and the camera ends up
    /// behind them.
    @Test
    func aCloseInPlayerLeavesTheFramingDistanceStanding() {
        var camera = DialogueCamera()
        let pose = camera.resolve(
            subject: DialogueCameraSubject(
                headPosition: Self.speakerHead,
                playerEyePosition: SIMD3(60, 0, PlayerCapsule.standard.eyeHeight)
            ),
            collisionQuery: { _ in [] }
        )
        #expect(pose.eye.x > 60)
        // The framing distance is the horizontal stand-off; the eye-to-target
        // distance is longer than it by the shoulder offset's own leg.
        #expect(abs(pose.eye.x - DialogueCamera.framingDistance()) < 0.001)
        #expect(pose.distance > DialogueCamera.framingDistance())
    }

    /// A player who started the conversation from across the room is not left
    /// behind the lens: the camera stands off from *them* instead, by the same
    /// clearance third person never collapses past.
    @Test
    func aDistantPlayerPushesTheCameraBackBehindThem() {
        var camera = DialogueCamera()
        let far: Float = 400
        let pose = camera.resolve(
            subject: DialogueCameraSubject(
                headPosition: Self.speakerHead,
                playerEyePosition: SIMD3(far, 0, PlayerCapsule.standard.eyeHeight)
            ),
            collisionQuery: { _ in [] }
        )
        #expect(pose.eye.x > far)
        #expect(abs(pose.eye.x - (far + DialogueCamera.clearanceBehindPlayer)) < 0.001)
    }

    /// Talking to somebody taller tilts the shot up at them rather than
    /// levelling it out, because the eye stays at the player's own height.
    @Test
    func aTallerSpeakerIsLookedUpAt() {
        var camera = DialogueCamera()
        let pose = camera.resolve(
            subject: DialogueCameraSubject(
                headPosition: Self.speakerHead + SIMD3(0, 0, 40),
                playerEyePosition: Self.playerEye
            ),
            collisionQuery: { _ in [] }
        )
        #expect(pose.pitch > 0)
        #expect(abs(pose.eye.z - Self.playerEye.z) < 0.001)
    }

    /// A player standing exactly inside the speaker names no side to watch
    /// from. The answer has to be finite and the same every frame, or the shot
    /// flickers.
    @Test
    func aDegeneratePlayerPositionStillResolves() {
        var camera = DialogueCamera()
        let subject = DialogueCameraSubject(
            headPosition: Self.speakerHead, playerEyePosition: Self.speakerHead
        )
        var first = camera.resolve(subject: subject, collisionQuery: { _ in [] })
        let second = camera.resolve(subject: subject, collisionQuery: { _ in [] })
        #expect(first == second)
        #expect(first.eye.x.isFinite && first.eye.y.isFinite && first.eye.z.isFinite)
        first = camera.resolve(subject: Self.subject, collisionQuery: { _ in [] })
        #expect(first.eye != second.eye)
    }

    // MARK: - Collision

    /// A wall behind the player pulls the camera in towards the speaker rather
    /// than letting it watch the conversation through a rock.
    @Test
    func aWallBehindThePlayerPullsTheCameraIn() {
        var camera = DialogueCamera()
        let wallX: Float = 80
        let wall = Self.quad(
            SIMD3(wallX, -400, -400), SIMD3(wallX, 400, -400),
            SIMD3(wallX, 400, 400), SIMD3(wallX, -400, 400)
        )
        let pose = camera.resolve(
            subject: Self.subject, collisionQuery: Self.query([wall])
        )
        #expect(pose.isCollisionLimited)
        #expect(pose.distance < DialogueCamera.framingDistance())
        #expect(pose.eye.x < wallX)
        // Still on the pivot-to-eye line, just shorter.
        var unobstructed = DialogueCamera()
        let open = unobstructed.resolve(
            subject: Self.subject, collisionQuery: { _ in [] }
        )
        let direction = simd_normalize(open.eye - open.target)
        #expect(simd_length(pose.eye - (pose.target + direction * pose.distance)) < 0.001)
    }

    /// A speaker backed into a corner never has the camera pushed inside their
    /// head: the pull-in stops one capsule radius out.
    @Test
    func theCameraNeverEndsUpInsideTheSpeaker() {
        var camera = DialogueCamera()
        let wall = Self.quad(
            SIMD3(2, -400, -400), SIMD3(2, 400, -400),
            SIMD3(2, 400, 400), SIMD3(2, -400, 400)
        )
        let pose = camera.resolve(
            subject: Self.subject, collisionQuery: Self.query([wall])
        )
        #expect(pose.distance >= PlayerCapsule.standard.radius)
    }

    /// A conversation must not open reporting where the last one's camera
    /// stood.
    @Test
    func resetForgetsTheLastFrame() {
        var camera = DialogueCamera()
        _ = camera.resolve(subject: Self.subject, collisionQuery: { _ in [] })
        #expect(camera.pose != nil)
        camera.reset()
        #expect(camera.pose == nil)
    }

    // MARK: - Rig visibility

    /// The eye leaves the player's head, so the body appears and the arms do
    /// not — whichever mode the conversation interrupted.
    @Test
    func engagingShowsTheBodyAndHidesTheArmsInFirstPerson() {
        let firstPerson = PlayerRigVisibility.resolve(
            mode: .walk, hasBody: true, hasArms: true
        )
        #expect(!firstPerson.drawsBody)
        #expect(firstPerson.drawsArms)
        let talking = PlayerRigVisibility.resolve(
            mode: .walk, hasBody: true, hasArms: true, dialogueCamera: true
        )
        #expect(talking.drawsBody)
        #expect(!talking.drawsArms)
        #expect(talking.castsBodyShadow)
    }

    /// Third person is unchanged by it: the body was already drawn.
    @Test
    func engagingChangesNothingInThirdPerson() {
        let plain = PlayerRigVisibility.resolve(
            mode: .thirdPerson, hasBody: true, hasArms: true
        )
        let talking = PlayerRigVisibility.resolve(
            mode: .thirdPerson, hasBody: true, hasArms: true, dialogueCamera: true
        )
        #expect(plain == talking)
    }

    // MARK: - Speaker focus

    /// The turn is bounded by the same yaw rate a mover corners at, so an actor
    /// spun to face the player rotates rather than snapping.
    @Test
    func theSpeakerTurnsAtTheMoverYawRateAndSettles() {
        var hold = Self.hold(facing: 0, towards: SIMD3(0, 100, 0))
        #expect(abs(hold.targetYaw - .pi / 2) < 0.001)
        #expect(!hold.isSettled)
        let step: Float = 1 / 60
        let drive = hold.advance(by: step)
        #expect(drive.intent == .still)
        #expect(abs(hold.yaw - NPCMovementRuntime.maximumYawSpeed * step) < 0.001)
        for _ in 0 ..< 120 where !hold.isSettled {
            _ = hold.advance(by: step)
        }
        #expect(hold.isSettled)
        #expect(abs(hold.yaw - .pi / 2) < 0.01)
    }

    /// The turn is a turn: the feet do not move, and the actor's own draw delta
    /// is a rotation about where it stands.
    @Test
    func theSpeakerTurnsWithoutMoving() {
        var hold = Self.hold(facing: 0, towards: SIMD3(0, 100, 0))
        for _ in 0 ..< 120 {
            _ = hold.advance(by: 1 / 60)
        }
        #expect(hold.feetPosition == .zero)
        #expect(hold.transform.position == .zero)
        #expect(abs(hold.transform.rotation.z - hold.yaw) < 0.001)
        #expect(hold.readout.state == .facing)
    }

    /// Re-aiming follows a player who walks around the speaker mid
    /// conversation, without restarting the turn from where it began.
    @Test
    func reaimingFollowsTheMovingPlayer() {
        var hold = Self.hold(facing: 0, towards: SIMD3(100, 0, 0))
        #expect(hold.isSettled)
        hold.aim(at: SIMD3(-100, 0, 0))
        #expect(!hold.isSettled)
        #expect(abs(abs(hold.targetYaw) - .pi) < 0.001)
    }

    /// The short way round: turning from just west of north to just east of it
    /// crosses north rather than going the long way about.
    @Test
    func theTurnTakesTheShortWayRound() {
        let turn = NPCYawMath.shortestTurn(from: .pi - 0.1, to: -.pi + 0.1)
        #expect(turn > 0)
        #expect(abs(turn - 0.2) < 0.001)
    }

    // MARK: - Fixtures

    private static func hold(facing yaw: Float, towards target: SIMD3<Float>) -> NPCFacingHold {
        NPCFacingHold(
            start: NPCFaceStart(
                actor: ReferenceKey.player,
                formID: FormID(1),
                placement: PlacedReference.Placement(
                    position: .zero, rotation: SIMD3(0, 0, yaw)
                ),
                scale: 1,
                target: target
            ),
            feetPosition: .zero,
            yaw: yaw
        )
    }

    private static func query(
        _ shapes: [StaticCollisionShape]
    ) -> WalkController.CollisionQuery {
        StaticCollisionSet(
            location: nil,
            shapes: shapes,
            stats: StaticCollisionStats()
        ).candidates
    }

    private static func quad(
        _ first: SIMD3<Float>,
        _ second: SIMD3<Float>,
        _ third: SIMD3<Float>,
        _ fourth: SIMD3<Float>
    ) -> StaticCollisionShape {
        let vertices = [first, second, third, fourth]
        return StaticCollisionShape(
            reference: FormID(1),
            transform: matrix_identity_float4x4,
            geometry: .triangleSoup(vertices: vertices, indices: [0, 1, 2, 0, 2, 3]),
            bounds: ModelBounds.containing(vertices) ?? ModelBounds(min: .zero, max: .zero)
        )
    }
}
