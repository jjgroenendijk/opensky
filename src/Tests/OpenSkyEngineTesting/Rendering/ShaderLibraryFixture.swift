// The shader library a test hands to `Renderer`, loaded once per device so each suite
// does not reload it.

import Foundation
public import Metal
import OpenSkyShaders

@MainActor
public enum ShaderLibraryFixture {
    private static var libraries: [UInt64: any MTLLibrary] = [:]

    public static func library(device: any MTLDevice) throws -> any MTLLibrary {
        if let library = libraries[device.registryID] {
            return library
        }
        let library = try ShaderLibrary.make(device: device)
        libraries[device.registryID] = library
        return library
    }
}
