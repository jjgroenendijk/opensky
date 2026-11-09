// The error messages tell the user which make target fixes the problem.

import Foundation
@testable import OpenSkyReference
import Testing

struct ReferenceErrorMessageTests {
    @Test func bridgeNotRunningNamesTheLaunchAndBuildTargets() {
        let message = ReferenceBridgeError.notRunning.errorDescription ?? ""
        #expect(message.contains("make run-cli ARGS='reference launch'"))
        #expect(message.contains("make build-bridge"))
    }

    @Test func launcherErrorsNameTheSetupTarget() {
        let errors: [ReferenceLauncherError] = [
            .noWine, .noWineUser, .noWrapper, .outsidePrefix("/tmp/x")
        ]
        for error in errors {
            #expect(error.errorDescription?.contains("make setup-reference") == true)
        }
    }
}
