// The record stores the audio coordinator reads. A port, so an adapter's host can pass
// them without the whole world data.

public import OpenSkyAudio
public import OpenSkyCells
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyWeather

/// The loaded sound, music, and weather records the audio directors resolve against.
nonisolated public protocol AudioRecordsPort {
    var soundStore: SoundRecordStore? { get }
    var footstepStore: FootstepStore? { get }
    var musicStore: MusicRecordStore? { get }
    var aspcStore: AcousticSpaceStore? { get }
    var materialTypes: MaterialTypeIndex? { get }
    var effectRecords: EffectRecordStore? { get }
    var weatherSystem: WeatherSystem? { get }
}

extension WorldDataStores: AudioRecordsPort {}
