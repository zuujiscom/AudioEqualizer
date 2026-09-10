# Audio Equalizer instructions

Before changing this project, read [the repository agent guide](../AGENTS.md). It describes the SwiftUI structure, Core Audio data flow, build command, and realtime-audio safety rules.

The process tap and aggregate device in `AudioEngine` are safety-critical: create them only after Start, never touch main-actor/UI state from the IOProc, and always retain teardown of both resources so system audio is restored.
