# Project collaboration rules

## iOS release work

Delegate the IPA building and testing process to a **Sol** sub-agent
(`gpt-6.2-sol`). This includes running/monitoring GitHub Actions, diagnosing iOS
build or packaging failures, checking the IPA and its version, and fetching the
verified release artifacts. When the workflow produces a paired Windows build,
the same agent should verify that both artifacts come from the same commit.

The primary agent owns implementation and review, then hands the finished commit
and relevant test results to Sol. Avoid duplicating checks that already passed
unless changes or failures justify another run. Give the build agent explicit
scope and report any physical-device checks that remain untested.

Keep account information, tokens, network-share paths and local IPA-copy
configuration out of tracked files and tool output. Use the existing ignored
local release-copy configuration when available.
