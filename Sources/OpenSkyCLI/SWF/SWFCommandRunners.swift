// Runs each parsed `swf` command.

import OpenSkyCLIArguments

extension SWFArguments.Sweep: CLIRunnable {
    func execute() throws {
        try SWFCommand.runSweep(context: context())
    }
}

extension SWFArguments.Show: CLIRunnable {
    func execute() throws {
        try SWFCommand.runInfo(context: context(), path: asset.path)
    }
}

extension SWFArguments.RenderSweep: CLIRunnable {
    func execute() throws {
        try SWFRenderSweep.run(context: context(), arguments: self)
    }
}

extension SWFArguments.ActionSweep: CLIRunnable {
    func execute() throws {
        try SWFActionSweep.run(context: context(), arguments: self)
    }
}

extension SWFArguments.ActionList: CLIRunnable {
    func execute() throws {
        try SWFActionListCommand.run(context: context(), arguments: self)
    }
}

extension SWFArguments.ActionRun: CLIRunnable {
    func execute() throws {
        try SWFActionRunCommand.run(context: context(), arguments: self)
    }
}

extension MenuArguments.Inventory: CLIRunnable {
    func execute() throws {
        try SWFInventoryMenuCommand.run(context: context(), arguments: self)
    }
}

extension MenuArguments.QuestJournal: CLIRunnable {
    func execute() throws {
        try SWFQuestJournalCommand.run(context: context(), arguments: self)
    }
}

extension MenuArguments.Container: CLIRunnable {
    func execute() throws {
        try SWFContainerMenuCommand.run(context: context(), arguments: self)
    }
}

extension MenuArguments.System: CLIRunnable {
    func execute() throws {
        try SWFSystemMenuCommand.run(context: context(), arguments: self)
    }
}

extension SWFArguments.MovieProbe: CLIRunnable {
    func execute() throws {
        try SWFMovieProbeCommand.run(context: context(), arguments: self)
    }
}

extension MenuArguments.Dialogue: CLIRunnable {
    func execute() throws {
        try SWFDialogueMenuCommand.run(context: context(), arguments: self)
    }
}
