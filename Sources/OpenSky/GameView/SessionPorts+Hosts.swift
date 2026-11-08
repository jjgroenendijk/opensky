// The session ports answer every adapter's host protocol, so each adapter sees
// only the part of the session it reads.

import OpenSkyMenus

extension SessionPorts: AIWorldHost {}
extension SessionPorts: ActivationRefusalWorldHost {}
extension SessionPorts: ActorGraphWorldHost {}
extension SessionPorts: ActorWorldHost {}
extension SessionPorts: AgentWorldHost {}
extension SessionPorts: AnimationEventWorldHost {}
extension SessionPorts: AudioWorldHost {}
extension SessionPorts: BeastFormWorldHost {}
extension SessionPorts: BenchmarkWorldHost {}
extension SessionPorts: CinematicCameraWorldHost {}
extension SessionPorts: CombatWorldHost {}
extension SessionPorts: ContainerMenuHost {}
extension SessionPorts: CrimeWorldHost {}
extension SessionPorts: DialogueCameraHost {}
extension SessionPorts: DialogueMenuHost {}
extension SessionPorts: DialogueWorldHost {}
extension SessionPorts: DragonFlightWorldHost {}
extension SessionPorts: EffectGraphWorldHost {}
extension SessionPorts: EffectsWorldHost {}
extension SessionPorts: FollowerCommandWorldHost {}
extension SessionPorts: IdleWorldHost {}
extension SessionPorts: InventoryMenuHost {}
extension SessionPorts: InventoryWorldHost {}
extension SessionPorts: JournalMenuHost {}
extension SessionPorts: LoadingScreenWorldHost {}
extension SessionPorts: LockWorldHost {}
extension SessionPorts: LockpickingMenuHost {}
extension SessionPorts: MagicWorldHost {}
extension SessionPorts: MapWorldHost {}
extension SessionPorts: MenuRouterHost {}
extension SessionPorts: MenuScreensHost {}
extension SessionPorts: MenuScreensWorldHost {}
extension SessionPorts: MenuSoundHost {}
extension SessionPorts: MenuWorldHost {}
extension SessionPorts: MessageWorldHost {}
extension SessionPorts: MountWorldHost {}
extension SessionPorts: MovieWorldHost {}
extension SessionPorts: ObjectAnimationWorldHost {}
extension SessionPorts: PerkActivationWorldHost {}
extension SessionPorts: PlayerWorldHost {}
extension SessionPorts: ProgressionWorldHost {}
extension SessionPorts: RagdollWorldHost {}
extension SessionPorts: RuntimeStateWorldHost {}
extension SessionPorts: SaveGameWorldHost {}
extension SessionPorts: ScriptWorldHost {}
extension SessionPorts: SkyrimSaveExportHost {}
extension SessionPorts: SkyrimSaveImportHost {}
extension SessionPorts: StoryWorldHost {}
extension SessionPorts: VehicleWorldHost {}
extension SessionPorts: SystemMenuWorld {}
