# Stopwatch

A quiet macOS stopwatch, Pomodoro and countdown timer, with large DynaPuff numbers, painted backgrounds and a small draggable pixel cat.

- Stopwatch, countdown and Pomodoro modes
- 25/5 and 50/10 presets, plus custom focus and break durations
- A small wallpaper button beside Reset cycles through the backgrounds
- Playful cat reminders when mouse movement interrupts a running stopwatch or Pomodoro focus session
- Full-screen layout and controls that fade when the mouse is idle
- Space to start/pause, R to reset; + and − adjust countdowns by one minute
- Local, offline timing; an internet connection is only needed for installation and updates

## Install on your Mac

Requires macOS 13 or later. Each Mac builds its own app, so Apple silicon and Intel use the same instructions. Intel has not yet been tested on hardware.

1. Open Terminal and install Apple's free Command Line Tools:

   ```sh
   xcode-select --install
   ```

   Finish the installer before continuing. If the tools are already installed, skip this step.

2. Copy and run:

   ```sh
   git clone https://github.com/camclarke11/stopwatch.git
   cd stopwatch
   ./install.sh
   ```

The app opens and is installed in **your home folder → Applications → Stopwatch**. Keep the cloned `stopwatch` folder in place: the app uses it to fetch future releases. If you move it, quit Stopwatch and run `./install.sh` from the new location.

No Apple Developer membership or App Store account is needed for this local source build. The app is locally signed, not notarized for general binary distribution.

## If installation reports “SDK is not supported by the compiler”

This means the installed Apple compiler and SDK do not match. The build now checks compatibility and tries other SDKs already installed with the selected developer tools. It does not change your system settings.

From the existing `stopwatch` folder, run:

```sh
git pull --ff-only
./install.sh
```

Do not clone again from inside that folder. If the build says no compatible SDK was found, open **System Settings → General → Software Update** and install the Command Line Tools update. If none is offered, install a matching Command Line Tools package from [Apple Downloads](https://developer.apple.com/download/all/), then retry `./install.sh`.

## Updates

The app checks for new stable version tags after launch and every six hours while open. You can also choose **Stopwatch → Check for Updates…** from the Mac menu bar.

When offered a release, click **Install Update**. The menu shows progress while the new version builds. The app restarts after the replacement is ready, restoring your timer and settings. A running timer includes the time spent restarting; paused timers stay paused. Ordinary quitting does not save a running session.

Updates build a separate copy of the selected release; they do not switch branches or overwrite edits in your checkout. Internet and the Command Line Tools must remain available. If fetching, compiling or preparing the replacement fails, the currently installed app remains in place. The installer retains **Stopwatch Previous.app** beside it after a successful replacement, so you can return to that version if needed. Launch success is not a guarantee against later runtime bugs.

Only install releases from a repository you trust: updates compile and run that repository's build script on your Mac.

## Publish an update

Make and test your changes, then increase `VERSION` (for example, to `1.0.1`). From this repository:

```sh
./Scripts/test.sh
./build.sh
git add Source Scripts Tests build.sh install.sh VERSION README.md
git commit -m "Describe the update"
git tag v1.0.1
git push origin main v1.0.1
```

Use a new `vMAJOR.MINOR.PATCH` tag for each release. Its number must match `VERSION`. Untagged commits and prerelease tags do not trigger updates. Do not move existing release tags. GitHub Releases pages are optional; the updater reads Git tags directly.

## Included assets

Rolling Number is bundled with its MIT license in `Source/ROLLING-LICENSE`. Font licenses are in `Source/Fonts` and `Source/FREDOKA-LICENSE`. Background images were supplied for this app; their inclusion does not grant a separate license to reuse the artwork. No blanket license is asserted over third-party artwork.
