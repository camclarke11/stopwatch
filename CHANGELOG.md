# Releases

## 1.0.11

- Paste a YouTube link to a song or mix into the note in the top-right corner. Its title and a small thumbnail sit in the corner, and clicking them opens the video.
- For mixes, a small arrow opens the tracklist, taken from the video's comments (or its description when no comment has one). Timestamps are checked: they must rise, fall inside the video, and have a song name. Click a track to play from there on YouTube.
- Add an Edit menu so ⌘C, ⌘V and the other text shortcuts work in the app.

## 1.0.10

- The current task shown above the clock while the controls are faded is now quieter, at half opacity.

## 1.0.9

- Add a three-task list for the day in the top-left corner. Drag tasks to reorder them, click one to rename it, and tick it off to sink it to the bottom with a strikethrough.
- The top unfinished task collects time whenever the stopwatch, timer or a Pomodoro focus runs. Breaks are not counted.
- When the controls fade, the current task appears above the enlarged clock.
- A day-by-day task history, split by mode, opens from the clock icon in the list. Every task and session is kept in `~/Library/Application Support/Stewie/tasks.json`.
- In smaller windows the list folds into a pill beside the mode switcher.
- Clicking the faded add-task field focuses it straight away.

## 1.0.8

- Rename the macOS app, menu and update messages to Stewie while keeping the same timer settings and update source.
- Existing Stopwatch installations migrate to Stewie.app on first launch after updating.

## 1.0.7

- Replace the 50 painted wallpapers with 24 generated backgrounds selected for this app, alongside the seven originals.
- Add a Pomodoro cycle reset icon beside Apply timings.

## 1.0.6

- 50 new painted wallpapers: 25 playful subjects (a frog in a crown, a cat in a bow tie, a dachshund in a jumper, fried eggs, tulips and more), each in two colourways. Cycle through them with the picture button beside Reset.
- The Stopwatch / Pomodoro / Timer labels now switch colour with the clock, so they stay readable on pale wallpapers.

## 1.0.5

- The cat now chats in every mode: Stopwatch, Timer and Pomodoro. During Pomodoro breaks it has its own gentler, break-time lines.
- Fix: clicking a faded control (for example pausing without moving the mouse first) now works on the first click, instead of only bringing the controls back.
- Fix: after applying Pomodoro timings with the mouse, Space starts the session again instead of reopening the settings.

## 1.0.4

- Add a pixel cat app icon for the Dock, Finder and app switcher.
- The cat’s reminders now also appear during Pomodoro focus sessions (not during breaks).
- The play, reset, wallpaper and settings buttons sit on a frosted glass bar, like the mode switcher, so they stay visible on every wallpaper.

## 1.0.3

- Expand the cat’s reminders to 48 encouraging and playful lines.

- Show a visible update window with a spinner, build/install stage and elapsed time.
- Keep a local diagnostic log available through Show details.
- Confirm the installed version after restarting.

## 1.0.2

- Switch wallpapers using the small picture button beside Reset. Clock colour adapts automatically.
- The cat offers one of 12 short, encouraging or playful reminders when mouse movement brings the controls back during a running stopwatch.
- Reminders stay visible for about four seconds, with a 45-second cooldown. They do not appear during paused sessions or while dragging the cat.
- Includes the existing seven wallpapers.

## 1.0.1

- Check compiler and SDK compatibility before building, trying other installed SDKs when needed.
