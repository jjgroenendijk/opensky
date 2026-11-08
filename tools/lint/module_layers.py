"""The engine's module layers, shared by module-graph.sh and app-architecture.sh.

docs/tools/modules.md explains each layer and the import rules between them.
"""

LAYERS = [
    ["OpenSkyShaderTypes", "CFFmpeg", "CASTCEncoder", "OpenSkyImageKernels",
     "OpenSkyCLIArguments"],
    ["OpenSkyFormatsCore"],
    ["OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyFormatsAnimation",
     "OpenSkyFormatsAudio", "OpenSkyFormatsPEX", "OpenSkyFormatsSWF", "OpenSkyFormatsESS"],
    ["OpenSkyGameData"],
    ["OpenSkyBehavior", "OpenSkyLaunch", "OpenSkyAssetCache", "OpenSkyReference"],
    ["OpenSkyPhysics", "OpenSkyDiagnostics", "OpenSkyAgentControl"],
    ["OpenSkyRenderCore", "OpenSkyRenderResources"],
    ["OpenSkyRendering", "OpenSkyAudio", "OpenSkyWorldState"],
    ["OpenSkyConditions"],
]
# Rule 9. The domains of the world feature, lowest first. A domain depends on lower
# modules, interfaces, and earlier domains. Of the features, only the world feature
# may depend on a domain; other features use OpenSkyWorldInterface.
DOMAINS = [
    "OpenSkyWorldConditionFunctions", "OpenSkyWeather", "OpenSkyNavigation", "OpenSkyTerrain",
    "OpenSkyEffects", "OpenSkyCamera", "OpenSkyRuntimeState", "OpenSkyActorPresentation",
    "OpenSkyPlayer", "OpenSkyObjectAnimation", "OpenSkyAIPackages", "OpenSkyCells",
    "OpenSkyWorldConditions", "OpenSkyLoading",
]

FOUNDATION = {name for names in LAYERS for name in names}
# The loaded-data layers: formats and the game data built from them.
DATA = {name for names in LAYERS[:LAYERS.index(["OpenSkyGameData"]) + 1] for name in names}
