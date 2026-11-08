import Foundation
import OpenSkyFormatsESM

/// One script change to an interior's fog. Colours are 0...1.
public enum PapyrusFogChange: Equatable, Sendable {
    case colours(near: SIMD3<Float>, far: SIMD3<Float>)
    case planes(near: Float, far: Float)
    case power(Float)
}
