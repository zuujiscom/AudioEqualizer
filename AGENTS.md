# Audio Equalizer — Agent Guide

## Project at a glance

`AudioEqualizer` is a native SwiftUI macOS app that applies a system-wide graphic EQ and master gain to the Mac's current default output. It targets macOS 26.0 and relies on macOS process-tap APIs, AVFoundation, CoreAudio, and Accelerate/vDSP. There are no package dependencies and no automated test target yet.

Open `AudioEqualizer.xcodeproj` in Xcode and build the `AudioEqualizer` scheme. A command-line build can use:

```sh
xcodebuild -project AudioEqualizer.xcodeproj -scheme AudioEqualizer -configuration Debug -derivedDataPath /tmp/AudioEqualizer-derived build
```

Do not lower the deployment target without replacing or conditionally compiling the macOS 15+/26 SDK process-tap APIs (`CATapDescription`, `AudioHardwareTap`, and `AudioHardwareAggregateDevice`).

## Architecture

- `AudioEqualizer/App/AudioEqualizerApp.swift`: app entry point. Creates and injects one `AudioEngine`, `MeterState`, and `PresetManager`.
- `AudioEqualizer/Audio/AudioEngine.swift`: the central audio lifecycle, Core Audio device monitoring, EQ state, route creation, manual AVAudioEngine rendering, realtime renderer, and metering state.
- `AudioEqualizer/Audio/SpectrumAnalyzer.swift`: reusable 2,048-sample FFT and RMS helpers. It returns 64 normalized spectrum bins, spaced logarithmically from 20 Hz to min(20 kHz, Nyquist) and rebuilt whenever the tap's sample rate changes. `SystemAudioRenderer.analysisWindow` must match the FFT size or the tail of each window is zero-padding.
- `AudioEqualizer/Models/`: `EQBand`, built-in `EQPreset` definitions and frequency layouts, plus `AudioDevice`.
- `AudioEqualizer/ViewModels/PresetManager.swift`: custom preset CRUD and JSON import/export. Persistent presets live in the user's Application Support `AudioEqualizer/presets.json`, never in the repository.
- `AudioEqualizer/Views/VisualizerView.swift`: the Visualizer window — a Metal renderer with sixteen modes in three families. Geometric and particle modes build vertices on the CPU each frame; shader modes are full-screen fragment programs that read the spectrum from a buffer and use no CPU geometry at all. All shaders are compiled at runtime from a source string, so there is no `.metal` file to register and no dependency.
- The renderer ping-pongs between two offscreen textures. Each frame the previous one is re-sampled through a zoom/rotate/drift/ripple transform and dimmed (`f_feedback`), this frame's content is drawn over it, and a final pass tone-maps the result onto the drawable. That warped feedback — not the geometry — is what produces the tunnels, spirals and marbling; it is the technique MilkDrop and G-Force are built on, and a plain fade to black does not achieve it. Two textures are required because a pass cannot sample the target it draws into.
- Modes come in five families. Geometric and particle modes are bespoke builders; shader modes are full-screen fragment programs; **replicator** and **simulation** modes are compositional, following Apple Motion's model. A `ReplicatorSpec` is a cell (what to draw) plus a layout (where to place copies: burst, spiral, wave, grid, scatter, ring) plus a sequence offset — Motion's Sequence Replicator — so a wave of change travels across elements instead of all of them pulsing together; element *N* takes spectrum bin *N*. A `ForceField` is Motion's simulation behaviors (vortex, orbit, attractor, repel, gravity, wind, drag, random motion) integrated per particle, attached to the emitter rather than to each particle. Prefer adding a spec over writing another bespoke `buildX()`: the compositional axes multiply, the bespoke ones do not.
- A `VisualizerPreset` is a mode plus its feedback transform, which is where the variety comes from: the same geometry looks entirely different tunnelled, spiralled or smeared. `Auto` cycles `VisualizerPreset.rotation`, holding each preset ~55–100 s and cutting on a detected beat. Long dwells are deliberate — the feedback buffer needs time to build depth. Two struct layouts must stay in step with the shader: `VisualizerVertex` against `VIn` (float2 at 0, float4 at 16, float at 32, 48-byte stride) and `VisualizerUniforms` against `Uniforms` (five floats then an int at offset 20, 24-byte stride).
- `AudioEqualizer/Views/`: SwiftUI presentation. Views mutate the engine through its public control methods or the binding pattern in `BandControlsView`. Presets, the output device readout, and engine status live in `HeaderBar` (`MainView.swift`) rather than a sidebar column; `PresetSectionView.swift` and `DeviceSelectionView.swift` hold those header components despite their historical names.
- `AudioEqualizer/Resources/`: app metadata, assets, and entitlements. The app sandbox is intentionally disabled because system-wide Core Audio routing needs direct hardware access.

## Audio path and lifecycle

When the user presses Start, `AudioEngine`:

1. Gets the current default output device.
2. Creates a private system process tap that excludes this app and uses `.mutedWhenTapped`.
3. Creates a private aggregate device combining that tap with the physical output.
4. Runs an `AudioDeviceIOProc` on the aggregate. Its realtime callback sends captured frames through an `AVAudioEngine` in manual-rendering mode, where `AVAudioUnitEQ` applies the bands and global gain, then writes the rendered frames to the real output buffers.
5. Samples a lock-protected 1,024-frame rendered-audio ring buffer at 20 Hz for the UI meters and spectrum.

The output-device listener updates `selectedOutputDeviceID`; while running, the app tears the route down and rebuilds it from scratch. Do not reintroduce an in-place `setComposition` switch — see the tap-lifetime rule below.

## Critical audio safety rules

- The tap **must not be created at launch**. A live tap mutes the audio it captures; create it only in `start()`.
- **Stopping the aggregate's IOProc permanently deactivates its auto-started tap.** A new IOProc on the same aggregate starts cleanly and reports no error, but the capture buffers stay zeroed while the tap keeps muting the real output — the device just goes silent. Anything that needs to change the graph while running (a band-count change, a preset with a different band count) must call `teardownRenderGraph()`/`buildRenderGraph()` and leave `ioProcID` alone. Only a full stop may call `stopIOProc()`. This is what "changing the band count mutes it" was.
- **The tap is not always buffer 0 of the IOProc's input list.** An aggregate lists each sub-device's own input buffers before the tap's, so an output device that also captures — the Xbox headset bridge publishes a microphone alongside its output — shifts the tap along. `tapBufferOffset(tapChannels:)` computes the offset and `SystemAudioRenderer.inputBufferOffset` applies it. Reading buffer 0 unconditionally feeds the EQ that microphone instead of the system audio, which sounds exactly like the device has been muted.
- Each processing session builds a **fresh `AVAudioEngine`**. Repeatedly enabling and disabling manual rendering mode on one instance leaves the graph alive but rendering silence.
- Always destroy both the aggregate device and process tap on every stopped/error path. `teardownSystemAudioRoute()` is what restores normal system audio.
- Exclude this app from the tap by both process object (when available) and bundle ID. Removing that exclusion can create self-capture/feedback or silence output.
- Keep `AudioEngine` main-actor isolated. `SystemAudioRenderer` deliberately owns data touched by the IOProc and is `@unchecked Sendable`; do not access SwiftUI/`@Published` state from that callback.
- The IOProc and source-node callbacks are realtime paths: no allocations, logging, I/O, actor hops, or locks that may block. The renderer's meter capture only uses `try()` on its lock; metering is best-effort.
- Do not assume a particular channel layout. The renderer handles interleaved and non-interleaved Float PCM and maps/repeats source channels as needed.
- If modifying stop/rebuild logic, verify the engine stops, route resources are destroyed, and audio returns after an error or output-device switch.

## State and UI conventions

- `bands` is the source of truth. Call `applyBandToNode(_:)` after a single-band mutation or `applyAllBands()` after a batch mutation.
- Changing band count replaces the EQ node because `AVAudioUnitEQ` has a fixed band count. Preserve nearest old-band settings, as `setBandCount(_:)` does.
- Gain is clamped to `-24...24 dB`; bandwidth is clamped to `0.1...5.0`; master gain is a multiplier limited to `15.85` (about `+24 dB`) and applied through `AVAudioUnitEQ.globalGain`.
- `isBypassed` changes each EQ filter's bypass state; it does not tear down the system route. `toggleBypass()` has no UI — it is engine-level API only, and the header status popover just reports the flag.
- Meter updates belong on `MeterState`, not `AudioEngine`, to avoid invalidating all slider views ~20 times per second.
- **Everything the visualizer draws must be driven by audio.** One clock (`phase`) feeds every time-based motion — shader patterns, replicator spin, the sequence wave, the feedback ripple — and it advances in proportion to audio energy, so silence freezes the whole renderer. Do not reintroduce a wall-clock increment, and do not give an element a non-zero size or emission rate at zero signal; a visual that animates in silence is decoration. Verify both directions: with the engine stopped, successive captures of the window must be byte-identical, and with audio they must differ.
- `SystemAudioRenderer.clearAnalysisBuffer()` must be called whenever processing stops. `scratchFilled` latches true, so without it the ring keeps serving its last frames and meters and visuals animate from a frozen snapshot long after the engine has stopped.
- `visualizerFrame()` is pulled at display rate, not the 20 Hz meter rate. Its `bass` and `level` come from the newest 512 samples through a ~150 Hz one-pole filter rather than the 2,048-sample FFT window: that window is tuned for frequency resolution and smears the transients a beat-reactive visual has to land on.
- `master gain` persists to `UserDefaults`; band curves do not. `init()` assigns the backing store directly, because the `didSet` would write straight back and `eqNode` does not exist yet.
- SwiftUI rebuilds the whole main menu whenever `.commands` re-evaluates, and the Engine menu title depends on `isRunning`. Anything removed from `NSApp.mainMenu` (View, Help) must therefore be re-stripped, not stripped once at launch — see `AppDelegate`.
- Built-in presets are `EQCurve`s — control points interpolated on a log-frequency axis — not fixed band lists. `applyPreset` resamples the curve onto the current layout, so selecting a preset in 31-band mode keeps 31 bands. Custom and imported presets have `curve == nil` and still set the band list (and therefore the layout).
- Preset curves are written to be roughly tone-neutral in level. A preset that lifts every band is a volume control, and on top of the master gain it only buys clipping.
- Built-in presets are recreated in memory. Only custom presets are persisted. Imported JSON must decode as a single `EQPreset`.
- `BandControlsView.bandRow` sizes band columns to the available width and only falls back to horizontal scrolling once even `minColumnWidth` no longer fits. A SwiftUI `Slider` is always horizontal: it is laid out at full track length and then rotated, so the outer frame must be the transposed size or every band reserves a track-length of horizontal space.

## Validation checklist

- Build the `AudioEqualizer` scheme after Swift or project-setting changes.
- Manually test audio changes on a machine that supports process taps: Start, play system audio, alter a band and master gain, Stop, then confirm ordinary system audio still plays.
- Change the macOS default output while running and verify the app follows it. Test a route-creation failure or Stop after Start to ensure no tap/aggregate is left behind.
- For UI work, check 10-, 15-, and 31-band modes plus the horizontal slider scroll layout.
- Switching band count and applying presets **while running** is the regression-prone path: verify audio keeps playing without toggling the engine off and on.
- Test against a virtual output device that also has an input stream (the Xbox headset bridge) — that is the case the tap-offset logic exists for.

## Repository hygiene

- Keep source under the existing app folders and do not commit Xcode user-state or DerivedData files.
- The project is `objectVersion 56` with no file-system-synchronized groups, so a new source file must be hand-registered in `project.pbxproj` in four places: `PBXBuildFile`, `PBXFileReference`, the owning `PBXGroup`'s children, and the target's `PBXSourcesBuildPhase`. Verify with `plutil -lint` afterwards.
- Preserve the existing SwiftUI style and inline comments; comments around Core Audio lifecycle code document real safety constraints.
- There is currently no README. Keep this file focused on implementation context; add user-facing setup or product documentation separately when requested.
