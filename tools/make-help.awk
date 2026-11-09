# Prints `make help` from the Makefile: each `##@ Group` heading and each target
# with a `## text` comment, then the shared options.
BEGIN { FS = ":.*## "; print "Usage: make <target> [OPTION=value]" }
/^##@/ { printf "\n%s\n", substr($0, 5) }
/^[a-z-]+:.*## / { printf "  %-16s %s\n", $1, $2 }
END {
    print "\nOptions"
    print "  PLAN             test plan: Quick UnitTests GPU AgentControl UITests RealData"
    print "                   RealDataAll Perf Sanitizers (docs/tools/test-runs.md)"
    print "  CONFIG           Debug or Release          T    comma list of Target[/Suite[/test()]]"
    print "  N                rerun until a failure     COVERAGE=1   coverage and its floors"
    print "  SAN              thread or address         CAP  memory cap in MB of a guarded plan"
    print "  DIFF_BASE        changed-lines base        ARGS the script's own arguments"
    print "  XCODEBUILD_FLAGS more xcodebuild flags"
}
