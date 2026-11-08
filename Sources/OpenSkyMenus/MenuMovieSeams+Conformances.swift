// The concrete types the menu movies and the input dispatcher drive.

public import OpenSkyMenusInterface
public import OpenSkyRendering

extension SWFMovieSource: MenuMovieLoading {}
extension HUDCoordinator: MenuLayerOwner {}
extension MenuModeController: MenuInputRouting {}
extension CameraInputState: CameraInputReceiving {}
