// `places`: reads the active plugins as the launcher's place picker does, and prints
// the list. A row's first column is a start value `game debug newgame --at` takes.

import OpenSkyCLIArguments
import OpenSkyLaunch

enum PlacesCommand {
    static func run(context: CLIContext, arguments: PlacesArguments) throws {
        let list: StartPlaceList
        do {
            list = try StartPlaceList.load(root: context.root)
        } catch {
            throw CLIError.failure("cannot read the places: \(String(describing: error))")
        }
        if arguments.weathers {
            list.weathers.prefix(arguments.limit ?? .max).forEach { print($0) }
            print("[INFO] \(list.weathers.count) weathers")
            return
        }
        let found = list.search(arguments.search ?? "")
        for place in found.prefix(arguments.limit ?? .max) {
            print("\(place.start.storedValue)\t\(place.name)\t\(place.detail)")
        }
        print("[INFO] \(found.count) of \(list.places.count) places")
    }
}
