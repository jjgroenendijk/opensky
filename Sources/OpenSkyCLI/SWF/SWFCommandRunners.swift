// Runs each parsed `swf` command.

import OpenSkyCLIArguments

extension SWFArguments.Sweep: CLIRunnable {
    func execute() throws {
        try SWFCommand.runSweep(context: context())
    }
}

extension SWFArguments.Info: CLIRunnable {
    func execute() throws {
        try SWFCommand.runInfo(context: context(), path: key)
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

extension SWFArguments.InventoryMenu: CLIRunnable {
    func execute() throws {
        try SWFInventoryMenuCommand.run(context: context(), arguments: self)
    }
}

extension SWFArguments.QuestJournal: CLIRunnable {
    func execute() throws {
        try SWFQuestJournalCommand.run(context: context(), arguments: self)
    }
}

extension SWFArguments.ContainerMenu: CLIRunnable {
    func execute() throws {
        try SWFContainerMenuCommand.run(context: context(), arguments: self)
    }
}

extension SWFArguments.SystemMenu: CLIRunnable {
    func execute() throws {
        try SWFSystemMenuCommand.run(context: context(), arguments: self)
    }
}

extension SWFArguments.MovieProbe: CLIRunnable {
    func execute() throws {
        try SWFMovieProbeCommand.run(context: context(), arguments: self)
    }
}

extension SWFArguments.DialogueMenu: CLIRunnable {
    func execute() throws {
        try SWFDialogueMenuCommand.run(context: context(), arguments: self)
    }
}
