// Each app type a host hands out answers its port.

import OpenSkySessionInterface

extension ContainerMenuController: ContainerMenuPort {}
extension ControllerRumble: ControllerRumblePort {}
extension DialogueCameraController: DialogueCameraPort {}
extension DialogueMenuController: DialogueMenuPort {}
extension GamepadMonitor: GamepadMonitorPort {}
extension InventoryMenuController: InventoryMenuPort {}
extension JournalMenuController: JournalMenuPort {}
extension LockpickingMenuController: LockpickingMenuPort {}
extension MenuRouter: MenuRouterPort {}
extension MenuScreens: MenuScreensPort {}
