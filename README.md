# Audio Equalizer

A system-wide equalizer for macOS. It shapes and boosts whatever your Mac is
playing (music, videos, games, calls) on whichever output you are using, with
no virtual audio driver to install.

- **10, 15 or 31 band graphic EQ**, from 20 Hz to 20 kHz, ±24 dB per band.
- **Master gain up to +24 dB**, for quiet laptops, speakers and headphones.
- **17 built-in presets** (Bass Boost, Vocal, Podcast/Voice, Night Mode and
  more), plus your own. Presets can be saved, imported and exported as JSON.
- **A profile for each output device.** A curve set for your headphones comes
  back automatically when you switch back to them; your TV keeps its own.
- **Live spectrum analyzer** in the main window.
- **A visualizer window** with 24 audio-driven modes, an Auto mode that cycles
  through presets on the beat, and import for MilkDrop `.milk` presets.

## How it works

Audio Equalizer uses the Core Audio *process tap* API added in macOS 26. When
you press Start, it:

1. Creates a **process tap** that captures everything the Mac is playing,
   except the app's own audio. While the tap is active, macOS mutes the
   original sound, so you hear only the equalized version.
2. Creates an **aggregate audio device** named "Audio Equalizer Output" that
   combines the tap with your real speakers or headphones.
3. Runs the captured audio through the EQ and plays the result on your output
   device, all in one clock-synced audio callback.

The tap and the aggregate device are both **private**: other apps, System
Settings and Audio MIDI Setup do not see them. Pressing Stop removes both and
your Mac's audio goes back to normal. If the app quits or crashes, macOS
removes them automatically.

### What it does not install

There is no kernel extension, no audio driver or plug-in, no login item and no
background service. The app only runs while you have it open.

### What it stores on your Mac

- **The app itself**, wherever you put it (usually `/Applications`).
- **Your presets, device profiles and imported MilkDrop presets** in
  `~/Library/Application Support/AudioEqualizer/`.
- **Its settings** (master gain, visualizer choices, whether device profiles
  are on) in its preferences file,
  `~/Library/Preferences/com.zuujis.AudioEqualizer.plist`.
- **The audio-capture permission** you grant it, which macOS keeps in its
  privacy settings under Privacy & Security → Screen & System Audio Recording.

## Getting started

### What you need

- A Mac with **Apple silicon** (M1 or later).
- **macOS 26 (Tahoe) or later.** The process-tap APIs it depends on are not
  available on older versions. Tested on macOS 26 and macOS 27.
- **Xcode 26 or later**, free from the Mac App Store.

### Build and install

```bash
git clone https://github.com/zuujiscom/AudioEqualizer.git
cd AudioEqualizer
xcodebuild -project AudioEqualizer.xcodeproj -scheme AudioEqualizer -configuration Release -derivedDataPath build
cp -R build/Build/Products/Release/AudioEqualizer.app /Applications/
open /Applications/AudioEqualizer.app
```

You can also open `AudioEqualizer.xcodeproj` in Xcode and press Run. The
project signs with Xcode's "Sign to Run Locally" setting, so no Apple
developer account is needed to build it for your own Mac.

### Use it

1. Press the **power button** at the top left of the window, or choose
   **Engine → Start Engine**. The first time, macOS asks for permission to
   capture audio. Allow it, since the app cannot equalize audio it cannot hear.
2. Play something and move the sliders, or pick a preset from the header.
3. Choose 10, 15 or 31 bands to trade simplicity for precision. Presets adapt
   to whichever you pick.
4. Press the power button again to stop. Your Mac's audio returns to normal.

The EQ follows the Mac's current output. Switch outputs in System Settings →
Sound or the menu bar and it rebuilds the route for the new device, bringing
back that device's saved curve.

### Presets

- **File → Save Current as Preset…** saves your curve.
- **File → Import Preset…** and **Export Selected Preset…** share presets as
  JSON files.
- The **Presets** menu lists every preset, and **Reset EQ to Flat** clears the
  curve.
- Presets live in `~/Library/Application Support/AudioEqualizer/`. Use
  **File → Reveal Presets File in Finder** to get there.

### Visualizer

Choose **Visualizer → Open Visualizer**, or pick a mode from the Visualizer
menu. **Auto** cycles through presets, switching on a beat. Everything the
visualizer draws is driven by the audio, so it sits still in silence.

**MilkDrop presets:** choose **File → Import MilkDrop Presets…** and select
`.milk` files or whole folders. Imported presets appear in the Visualizer menu.
They reproduce each preset's motion; MilkDrop's custom shapes, waves and shader
code are not supported. No presets are bundled with the app, because the
community packs have unclear licensing, so bring your own.

### Update

```bash
git pull
xcodebuild -project AudioEqualizer.xcodeproj -scheme AudioEqualizer -configuration Release -derivedDataPath build
```

Quit the app, copy the new `AudioEqualizer.app` over the old one in
`/Applications`, and reopen it.

### Uninstall

1. Press Stop (or just quit the app), then delete it from `/Applications`.
2. To remove your presets, device profiles and settings too:

   ```bash
   rm -rf ~/Library/Application\ Support/AudioEqualizer
   defaults delete com.zuujis.AudioEqualizer
   ```

3. To remove its audio-capture permission, open System Settings → Privacy &
   Security → Screen & System Audio Recording, select Audio Equalizer and
   remove it with the minus button.

### Troubleshooting

- **No sound after pressing Start.** Check that Audio Equalizer is allowed
  under System Settings → Privacy & Security → Screen & System Audio Recording.
  Then stop and start the engine.
- **Sound is distorted.** Lower the master gain, or pull the boosted bands
  down. Stacking large boosts on top of master gain clips.
- **Audio stays silent after the app quits unexpectedly.** Reopen the app and
  press Start and then Stop, or switch the output device in System Settings →
  Sound and back.
- **Reporting a problem.** Choose **Engine → Copy Diagnostics** and paste the
  result into a [GitHub issue](https://github.com/zuujiscom/AudioEqualizer/issues).

## License

Audio Equalizer is free software, released under the
[GNU General Public License v3.0](LICENSE). You can use, study, change and
share it. If you distribute a modified version, you must release its source
under the same license.
