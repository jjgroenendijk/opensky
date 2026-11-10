// The runtime most tests build: the standard natives over a fresh context.

public import OpenSkyFormatsPEX
public import OpenSkyScripting

extension PapyrusRuntime {
    public convenience init(files: [PexFile], limits: PapyrusLimits = .standard) {
        self.init(
            files: files,
            nativeDispatch: PapyrusNativeFunctions.standardRegistry,
            limits: limits
        )
    }
}
