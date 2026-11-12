public import OpenSkyMagic
public import OpenSkySessionInterface

extension ActiveEffectRuntime: ActiveEffectRuntimePort {}
extension CasterRuntime: CasterRuntimePort {}
extension HazardCoordinator: HazardPort {}
extension HazardRuntime: HazardRuntimePort {}
extension MagicCoordinator: MagicPort {}
extension MagicCoordinator.ArchetypeActions: MagicArchetypeActionsPort {}
extension MagicCoordinator.FrameStep: MagicFrameStepPort {}
extension MagicCoordinator.ItemUse: MagicItemUsePort {}
extension MagicCoordinator.MagicMenu: MagicMenuListPort {}
extension MagicCoordinator.MenuLines: MagicMenuLinesPort {}
extension MagicCoordinator.ShoutVoice: MagicShoutVoicePort {}
extension MagicCoordinator.SoulTrapping: MagicSoulTrappingPort {}
extension MagicCoordinator.WeaponEnchantments: MagicWeaponEnchantmentsPort {}
extension MagicCoordinator.WorldArchetypeActions: MagicWorldArchetypesPort {}
extension ShoutMachine: ShoutMachinePort {}
extension SpellCastState: SpellCastStatePort {}
extension SpellbookRuntime: SpellbookRuntimePort {}
