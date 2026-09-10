# Claude Code Instructions

Read and follow the repository-wide guide in [AGENTS.md](AGENTS.md). It is the authoritative architecture and safety memory for this project.

In particular, treat the Core Audio process tap and aggregate-device lifecycle as safety-critical: do not create a tap before `AudioEngine.start()`, and preserve every teardown/error path that destroys the tap and aggregate device.
