import Foundation
func check(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fatalError(message) } }
var timer = TimerState()
timer.handle("toggle", at: 10)
check(timer.elapsed(at: 20) == 10, "Stopwatch elapsed")
timer.handle("mode:pomodoro", at: 20)
check(timer.stopwatchElapsed == 10 && timer.startedAt == nil, "Mode switch pauses and preserves stopwatch")
check(timer.snapshot(at: 20)["seconds"] as? Double == 1500, "Pomodoro starts at 25 minutes")
timer.handle("toggle", at: 30)
check(timer.snapshot(at: 30.5)["seconds"] as? Double == 1500, "Countdown rounds up")
timer.handle("toggle", at: 40)
check(timer.pomodoroElapsed == 10 && timer.elapsed(at: 200) == 10, "Paused countdown stays fixed")
timer.handle("toggle", at: 300)
check(!timer.tick(at: 1789), "No early finish")
check(timer.tick(at: 1790), "Finish at deadline")
check(timer.completed && timer.startedAt == nil && timer.completedFocusCount == 1, "Finish does not auto-start break")
check(!timer.tick(at: 99999) && timer.completedFocusCount == 1, "Completion fires only once after long sleep")
timer.handle("toggle", at: 100000)
check(timer.phase == .shortBreak && timer.duration == 300, "Start short break")
check(timer.tick(at: 100300), "Break completes")
timer.handle("toggle", at: 100301)
check(timer.phase == .focus && timer.duration == 1500, "Return to focus")
timer.handle("mode:stopwatch", at: 100311)
check(timer.stopwatchElapsed == 10 && timer.pomodoroElapsed == 10, "Both modes retain elapsed time")
timer.handle("reset", at: 100400)
check(timer.stopwatchElapsed == 0 && timer.pomodoroElapsed == 10, "Reset affects only active mode")
var cycle = TimerState(); cycle.mode = .pomodoro
var now = 0.0
for index in 1...4 {
    cycle.handle("toggle", at: now)
    now += 1500; check(cycle.tick(at: now), "Focus finishes")
    check(cycle.completedFocusCount == index, "Count focus completions")
    cycle.handle("toggle", at: now)
    check(cycle.phase == (index == 4 ? .longBreak : .shortBreak), "Fourth session earns long break")
    now += cycle.duration; cycle.tick(at: now)
}
var boundary = TimerState(); boundary.mode = .pomodoro
boundary.handle("toggle", at: 0)
check(boundary.handle("toggle", at: 1500) && boundary.completed && boundary.startedAt == nil, "A pause exactly at deadline must not accidentally start the break")
boundary.handle("reset", at: 1600)
check(!boundary.completed && boundary.pomodoroElapsed == 0, "Reset a completed interval")
print("Passed: countdown, pause/resume, mode preservation, reset isolation, exact completion, sleep overrun, four-session cycle, deadline race.")
var countdown = TimerState(); countdown.mode = .timer
check(countdown.snapshot(at: 0)["seconds"] as? Double == 600, "Default timer is ten minutes")
countdown.handle("adjust:5", at: 0)
check(countdown.timerDuration == 900, "Add five minutes")
countdown.handle("adjust:-10", at: 0)
check(countdown.timerDuration == 300, "Subtract ten minutes")
countdown.handle("toggle", at: 10)
countdown.handle("adjust:10", at: 70)
check(countdown.elapsed(at: 70) == 60 && countdown.snapshot(at: 70)["seconds"] as? Double == 840, "Running adjustment preserves elapsed time")
countdown.handle("toggle", at: 100)
check(countdown.snapshot(at: 1000)["seconds"] as? Double == 810, "Paused adjusted timer stays fixed")
countdown.handle("mode:pomodoro", at: 1100)
check(countdown.snapshot(at: 1100)["seconds"] as? Double == 1500, "Timer adjustment does not affect Pomodoro")
countdown.handle("mode:timer", at: 1200)
check(countdown.snapshot(at: 1200)["seconds"] as? Double == 810, "Countdown preserved across mode switch")
countdown.handle("reset", at: 1200)
check(countdown.snapshot(at: 1200)["seconds"] as? Double == 900, "Reset uses selected duration")
countdown.handle("toggle", at: 1200)
check(countdown.tick(at: 2100) && countdown.isComplete, "Countdown completion")
check(!countdown.tick(at: 2200), "Countdown only completes once")
countdown.handle("toggle", at: 2300)
check(countdown.elapsed(at: 2300) == 0 && !countdown.isComplete, "Restart completed countdown")
countdown.handle("adjust:-10", at: 2300)
check(countdown.handle("adjust:-5", at: 2610), "Expired countdown reports completion before adjustment")
check(countdown.timerDuration == 0 && countdown.startedAt == nil, "Clamp at zero")
countdown.handle("toggle", at: 2700)
check(countdown.startedAt == nil, "Cannot start zero timer")
countdown.handle("adjust:5", at: 2700)
check(countdown.snapshot(at: 2700)["seconds"] as? Double == 300, "Can add time from zero")
for _ in 0..<200 { countdown.handle("adjust:10", at: 2700) }
check(countdown.timerDuration == 86400, "Upper bound of twenty-four hours")
print("Passed: timer adjustments, zero and upper limits, mode isolation, reset, completion, restart.")

var minuteKeys = TimerState(); minuteKeys.mode = .timer
minuteKeys.handle("adjust:1", at: 0)
check(minuteKeys.snapshot(at: 0)["seconds"] as? Double == 660, "One-minute shortcut adds sixty seconds")
minuteKeys.handle("toggle", at: 0)
minuteKeys.handle("adjust:-1", at: 30)
check(minuteKeys.snapshot(at: 30)["seconds"] as? Double == 570 && minuteKeys.startedAt != nil, "One-minute subtraction preserves running state and elapsed time")
minuteKeys.handle("toggle", at: 40)
minuteKeys.handle("adjust:1", at: 100)
check(minuteKeys.snapshot(at: 200)["seconds"] as? Double == 620 && minuteKeys.startedAt == nil, "One-minute addition preserves pause")
minuteKeys.handle("mode:pomodoro", at: 200)
minuteKeys.handle("adjust:-1", at: 200)
check(minuteKeys.duration == 1500 && minuteKeys.timerDuration == 660, "Minute shortcuts affect only Timer mode")
print("Passed: one-minute adjustments while running and paused, and mode isolation.")

var custom = TimerState(); custom.mode = .pomodoro
custom.handle("pomodoro-settings:50,10,30", at: 0)
check(custom.duration == 3000 && custom.startedAt == nil, "50/10 starts paused at fifty minutes")
custom.handle("toggle", at: 0)
custom.handle("pomodoro-settings:50,10,30", at: 60)
check(custom.elapsed(at: 60) == 60 && custom.startedAt != nil, "Applying unchanged settings preserves session")
check(custom.tick(at: 3000), "Custom focus duration completes exactly")
custom.handle("toggle", at: 3000)
check(custom.phase == .shortBreak && custom.duration == 600, "Custom short break duration")
custom.handle("pomodoro-settings:40,8,24", at: 3010)
check(custom.phase == .focus && custom.duration == 2400 && custom.startedAt == nil && custom.completedFocusCount == 0, "Changed settings reset to fresh paused focus")
for action in ["pomodoro-settings:0,5,15", "pomodoro-settings:181,5,15", "pomodoro-settings:25,x,15", "pomodoro-settings:25,5,15,x", "pomodoro-settings:25,5", "pomodoro-settings:25.5,5,15"] {
    custom.handle(action, at: 3010)
    check(custom.focusMinutes == 40 && custom.breakMinutes == 8 && custom.longBreakMinutes == 24, "Invalid settings ignored")
}
custom.completedFocusCount = 3
custom.handle("toggle", at: 4000)
custom.tick(at: 6400)
custom.handle("toggle", at: 6400)
check(custom.phase == .longBreak && custom.duration == 1440, "Fourth focus uses custom long break")
custom.handle("mode:timer", at: 6500)
custom.handle("pomodoro-settings:25,5,15", at: 6500)
check(custom.focusMinutes == 40 && custom.timerDuration == 600, "Settings cannot affect another mode")
check(custom.snapshot(at: 6500)["breakMinutes"] as? Int == 8, "Snapshot exposes configured timings")
print("Passed: Pomodoro presets, custom intervals, unchanged apply, reset semantics, validation and long breaks.")

var resetCycle = TimerState(); resetCycle.mode = .pomodoro
resetCycle.focusMinutes = 50; resetCycle.breakMinutes = 10; resetCycle.longBreakMinutes = 30
resetCycle.completedFocusCount = 2; resetCycle.phase = .focus; resetCycle.pomodoroElapsed = 120
resetCycle.startedAt = 100
resetCycle.handle("pomodoro-reset-session", at: 200)
check(resetCycle.snapshot(at: 200)["focusNumber"] as? Int == 1, "Session reset returns focus three to one")
check(resetCycle.phase == .focus && resetCycle.completedFocusCount == 0 && resetCycle.pomodoroElapsed == 0 && resetCycle.startedAt == nil && !resetCycle.completed, "Session reset pauses a fresh focus interval")
check(resetCycle.snapshot(at: 200)["seconds"] as? Double == 3000 && resetCycle.breakMinutes == 10, "Session reset keeps configured timings")
resetCycle.phase = .longBreak; resetCycle.completed = true; resetCycle.completedFocusCount = 4; resetCycle.pomodoroElapsed = 1800
resetCycle.handle("pomodoro-reset-session", at: 300)
check(resetCycle.phase == .focus && resetCycle.completedFocusCount == 0 && !resetCycle.completed && resetCycle.pomodoroElapsed == 0, "Session reset clears a completed long break")
resetCycle.handle("mode:timer", at: 300)
resetCycle.timerElapsed = 45; resetCycle.completedFocusCount = 2
resetCycle.handle("pomodoro-reset-session", at: 301)
check(resetCycle.timerElapsed == 45 && resetCycle.completedFocusCount == 2, "Pomodoro session reset is ignored in Timer mode")
print("Passed: Pomodoro cycle reset while running, after completion, and mode isolation.")

var updating = TimerState()
updating.handle("mode:timer", at: 0)
updating.handle("toggle", at: 100)
let saved = UpdateCheckpoint(state: updating, now: 160, date: Date(timeIntervalSince1970: 1000))
let encoded = try! JSONEncoder().encode(saved)
let decoded = try! JSONDecoder().decode(UpdateCheckpoint.self, from: encoded)
var resumed = decoded.restored(at: 2, date: Date(timeIntervalSince1970: 1010))
check(resumed.elapsed(at: 2) == 70, "Update includes elapsed restart time")
check(resumed.startedAt != nil, "Update resumes running timer")
check(resumed.tick(at: 532), "Restored timer completes at original deadline")
check(!resumed.tick(at: 533), "Restored completion fires once")
updating.pause(at: 160)
let pausedCheckpoint = UpdateCheckpoint(state: updating, now: 500, date: Date(timeIntervalSince1970: 1000))
let pausedRestore = pausedCheckpoint.restored(at: 0, date: Date(timeIntervalSince1970: 2000))
check(pausedRestore.elapsed(at: 0) == 60 && pausedRestore.startedAt == nil, "Paused timer remains paused across update")
print("Update checkpoint tests passed")

var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
let noon = utc.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 12))!
var serial = 0
func nextID() -> String { serial += 1; return "t\(serial)" }
var list = TaskLog()
for title in ["Write report", "  Email Sam  ", "Book dentist"] { list.handle("task-add:" + title, date: noon, makeID: nextID) }
check(list.tasks.allSatisfy { $0.created == noon && $0.finished == nil && $0.removed == nil }, "New tasks record when they were created")
check(list.tasks.map(\.title) == ["Write report", "Email Sam", "Book dentist"], "Tasks keep their order and trim spaces")
check(!list.handle("task-add:Fourth", makeID: nextID) && list.tasks.count == 3, "Three unfinished tasks fill the list")
check(!list.handle("task-add:   ", makeID: nextID), "Blank tasks are ignored")
check(list.handle("task-edit:t1:Draft: intro") && list.tasks[0].title == "Draft: intro", "Titles may contain colons")
list.handle("task-edit:t1:" + String(repeating: "x", count: 200))
check(list.tasks[0].title.count == TaskLog.titleLimit, "Titles are limited")
check(!list.handle("task-edit:t1:   ") && list.tasks[0].title.count == TaskLog.titleLimit, "Blank edits are ignored")
list.handle("task-done:t1:1", date: noon)
check(list.tasks.map(\.id) == ["t2", "t3", "t1"] && list.activeTask?.id == "t2", "Finished task sinks and the next becomes active")
check(!list.handle("task-move:t1:0"), "Finished tasks cannot be dragged above unfinished ones")
list.handle("task-move:t3:0")
check(list.tasks.map(\.id) == ["t3", "t2", "t1"], "Drag to the top")
list.handle("task-move:t3:9")
check(list.tasks.map(\.id) == ["t2", "t3", "t1"], "Drag clamps to the unfinished tasks")
list.handle("task-done:t2:1", date: noon)
check(list.tasks.map(\.id) == ["t3", "t1", "t2"], "Latest finished task goes to the very bottom")
list.handle("task-done:t1:0")
check(list.tasks.map(\.id) == ["t3", "t1", "t2"] && list.tasks[1].finished == nil, "Reopened task rejoins the unfinished tasks")
list.handle("task-add:Call bank", makeID: nextID)
check(list.tasks.map(\.id) == ["t3", "t1", "t4"] && list.archive.map(\.id) == ["t2"], "Adding to a full list clears the lowest finished task")
check(list.archive[0].finished == noon && list.archive[0].removed != nil, "Cleared tasks keep their finish and removal dates")
check(!list.handle("task-done:t9:1") && !list.handle("task-bogus:t3:1") && !list.handle("task-done:t3:yes") && !list.handle("task-add"), "Unknown tasks and malformed actions are ignored")
list.handle("task-delete:t1")
check(list.tasks.map(\.id) == ["t3", "t4"] && list.archive.map(\.id) == ["t2", "t1"], "Removed tasks are archived even without tracked time")
print("Passed: task list limit, editing, finishing, reordering and removal.")

var work = TaskLog(), watch = TimerState()
func record(_ t: Double) { work.record(watch, at: t, date: noon.addingTimeInterval(t), calendar: utc) }
func press(_ action: String, at t: Double) { record(t); watch.handle(action, at: t); record(t) }
func edit(_ action: String, at t: Double) { record(t); work.handle(action, date: noon.addingTimeInterval(t), makeID: nextID); record(t) }
func tick(at t: Double) { record(t); watch.tick(at: t); record(t) }
edit("task-add:Report", at: 0); edit("task-add:Email", at: 0)
let report = work.tasks[0].id, email = work.tasks[1].id
press("toggle", at: 0); record(30); press("toggle", at: 60)
check(work.seconds(for: report) == 60 && work.seconds(for: email) == 0 && !work.isTracking, "Stopwatch time goes to the top task")
press("toggle", at: 100); edit("task-move:\(email):0", at: 130)
check(work.isTracking && (work.snapshot()["tracking"] as? Bool) == true, "Snapshot reports tracking")
press("toggle", at: 150)
check(work.seconds(for: report) == 90 && work.seconds(for: email) == 20, "Dragging a task to the top moves the time to it")
press("toggle", at: 200); press("toggle", at: 200.4)
check(work.sessions.count == 3, "Sub-second starts are not recorded")
press("mode:pomodoro", at: 300); press("toggle", at: 300); record(1000); tick(at: 1800.6)
check(work.seconds(for: email) == 1520 && !work.isTracking, "Pomodoro focus counts only up to its deadline")
check(work.sessions.map { $0.completed == true } == [false, false, false, true], "Only a focus interval that ran to its end is marked completed")
press("toggle", at: 1900); record(2200)
check(watch.phase == .shortBreak && work.seconds(for: email) == 1520 && !work.isTracking, "Pomodoro breaks are not counted")
press("mode:timer", at: 2200); press("toggle", at: 2300); edit("task-done:\(email):1", at: 2360)
check(work.activeTask?.id == report && work.seconds(for: email) == 1580 && work.isTracking, "Timer counts, and finishing a task hands the clock to the next")
check(work.sessions.last(where: { $0.taskID == email })?.completed == nil, "A countdown interrupted by finishing the task is not marked completed")
press("mode:stopwatch", at: 2400)
check(work.seconds(for: report) == 130 && !work.isTracking, "Switching modes stops tracking")
let beforeMidnight = 12 * 3600 - 100.0
press("toggle", at: beforeMidnight); record(beforeMidnight + 50); record(beforeMidnight + 160); press("toggle", at: beforeMidnight + 200)
let days = work.history(calendar: utc)
check(days.map { $0["date"] as? String } == ["2026-10-05", "2026-10-04"], "History splits at midnight, newest day first")
let firstDay = days[1]["tasks"] as! [[String: Any]], secondDay = days[0]["tasks"] as! [[String: Any]]
check(firstDay.map { $0["title"] as? String } == ["Email", "Report"], "Longest task first")
check(firstDay[0]["seconds"] as? Double == 1580 && firstDay[0]["pomodoro"] as? Double == 1500 && firstDay[0]["stopwatch"] as? Double == 20 && firstDay[0]["timer"] as? Double == 60, "Time is split by mode")
check(firstDay[0]["finished"] as? Bool == true && firstDay[1]["finished"] as? Bool == false, "Finished tasks are marked on the day they were finished")
check(firstDay[1]["seconds"] as? Double == 290 && secondDay.first?["stopwatch"] as? Double == 40, "Each day keeps its own share of a session across midnight")
edit("task-delete:\(email)", at: 50000)
check(work.archive.map(\.id) == [email] && (work.history(calendar: utc)[1]["tasks"] as! [[String: Any]])[0]["title"] as? String == "Email", "Removed tasks keep their history")
press("toggle", at: 60000)
let taskEncoder = JSONEncoder(); taskEncoder.dateEncodingStrategy = .iso8601
let taskDecoder = JSONDecoder(); taskDecoder.dateDecodingStrategy = .iso8601
let reloaded = try! taskDecoder.decode(TaskLog.self, from: taskEncoder.encode(work))
check(reloaded.tasks == work.tasks && reloaded.archive == work.archive && reloaded.sessions == work.sessions && !reloaded.isTracking, "Tasks and history persist; the open clock does not")
print("Passed: task time tracking across modes, Pomodoro breaks, reordering, finishing, midnight, history and persistence.")
check(Tracklist.videoID(from: "https://www.youtube.com/watch?v=i43tkaTXtwI&t=30s") == "i43tkaTXtwI", "Watch link")
check(Tracklist.videoID(from: " youtu.be/TbAjL4qgzC0?si=abc ") == "TbAjL4qgzC0", "Short link without a scheme")
check(Tracklist.videoID(from: "https://music.youtube.com/watch?v=pHrGDXEBPGs&list=RD") == "pHrGDXEBPGs", "YouTube Music link")
check(Tracklist.videoID(from: "https://m.youtube.com/live/pHrGDXEBPGs") == "pHrGDXEBPGs" && Tracklist.videoID(from: "https://www.youtube.com/shorts/pHrGDXEBPGs") == "pHrGDXEBPGs", "Live and Shorts links")
check(Tracklist.videoID(from: "https://example.com/watch?v=pHrGDXEBPGs") == nil && Tracklist.videoID(from: "https://www.youtube.com/watch?v=short") == nil && Tracklist.videoID(from: "hello") == nil, "Other links are refused")
let mix = """
🎶 | Tracklist
[00:00] Tonion x xander. - Snow In April
[03:46] Purrple Cat - Dissipate
05:52 – Amess - Flying Colours (Remix)
1. 8:34 Yasumu - Forest Waltz [Chillhop]
11:16 - 12:30 twoscents - Rainy Days
\u{200B}13:30\u{200B} -  • Kanisan - Dahlia...
16:42 duplicate time should not replace the first
16:42 also at 16:42
Loved the drop at 5:00 💜
Hoogway - Found You 1:02:29
2:00:00 past the end
"""
let parsed = Tracklist.parse(mix, duration: 7200)
check(parsed.map(\.seconds) == [0, 226, 352, 514, 676, 810, 1002, 3749], "Rising timestamps survive; strays, repeats and times past the end drop out")
check(parsed.map(\.title) == ["Tonion x xander. - Snow In April", "Purrple Cat - Dissipate", "Amess - Flying Colours (Remix)", "Yasumu - Forest Waltz [Chillhop]",
                              "twoscents - Rainy Days", "Kanisan - Dahlia...", "duplicate time should not replace the first", "Hoogway - Found You"], "Titles are cleaned")
check(Tracklist.parse("00:00 A 03:20 B 07:10 C", duration: nil).map(\.title) == ["A", "B", "C"], "Several tracks on one line")
check(Tracklist.parse("0:00 One\n4:75 Bad\n1:61:00 Bad\n9:00 Two\n12:00 🎵\n15:00 Three", duration: 600).map(\.title) == ["One", "Two"], "Invalid times, empty titles and times past the end are skipped")
let picked = Tracklist.best(comments: ["the piano at 32:00 is deadly", "0:00 A\n3:00 B", "0:00 First\n2:00 Second\n4:00 Third", "0:00 Other\n2:00 Other two\n4:00 Other three"], description: "0:00 x\n1:00 y\n2:00 z\n3:00 w", duration: nil)
check(picked.map(\.title) == ["First", "Second", "Third"], "The fullest comment wins, earlier comments win ties, and the description is only a fallback")
check(Tracklist.best(comments: ["0:00 A\n3:00 B"], description: "0:00 x\n1:00 y\n2:00 z", duration: nil).map(\.title) == ["x", "y", "z"], "The description is used when no comment has a tracklist")
check(Tracklist.best(comments: ["great mix 10:00"], description: nil, duration: nil).isEmpty, "A single song has no tracklist")
// Lines from the tracklist comment on Virtual Riot's Lost Lands 2026 set (Ps1WZRwBS3A), with its legend.
let riot = """
Tracklist:
0:00 Set intro - Virtual Riot
6:43 Lost It - VIP (VIP) - Virtual Riot ** (alt, "lost it (vip show edit)")
8:45 This Could Be Us VIP - Virtual Riot x Modestep x FRANK ZUMMO *
25:46 ID - ID * (potentially Anybody (Virtual Riot Remix) - Skrillex x ISOxo)
26:37 Sh*t's On F*re - Virtual Riot

* = unreleased
** = released on SoundCloud under his main or alt "RiotVirtual". Formatted as (account, "name of song").
"""
let riotTracks = Tracklist.parse(riot, duration: nil)
check(riotTracks.map(\.title) == ["Set intro - Virtual Riot", "Lost It - VIP (VIP) - Virtual Riot", "This Could Be Us VIP - Virtual Riot x Modestep x FRANK ZUMMO", "ID - ID", "Sh*t's On F*re - Virtual Riot"], "Footnote markers come off the song names")
check(riotTracks.map(\.note) == [nil, "Released on SoundCloud under his main or alt \"RiotVirtual\" · alt, \"lost it (vip show edit)\"", "Unreleased", "Unreleased · potentially Anybody (Virtual Riot Remix) - Skrillex x ISOxo", nil], "Markers become notes using the comment's own legend")
let otherLegend = Tracklist.parse("0:00 Intro †\n3:00 (U) Second Song\n6:00 Third Song *\n† - edit\n(U): unreleased", duration: nil)
check(otherLegend.map(\.title) == ["Intro", "Second Song", "Third Song *"] && otherLegend.map(\.note) == ["Edit", "Unreleased", nil], "Other legend styles work, and markers the comment never explains stay as written")
// From the tracklist comment on Overmono's Boiler Room Manchester set (xgJBhezlMoE).
check(Tracklist.parse("2:41 - gunk\n12:00 - freedom 2\n16:05 - 🚀\n26:00 - turn the page\n1:06:43 - good lies\n1:07:24 (lewis on shoulders maybe)", duration: nil).map(\.title) == ["gunk", "freedom 2", "turn the page", "good lies"], "Emoji-only and bracketed remarks are not songs")
// From the tracklist comment on the Overmono, Fred again.. & Lil Yachty Lot Radio set (9Stt4wq3KCE).
let lot = Tracklist.parse("Tracklist:\n(19:30) ID – ID\n(22:30) Joy Orbison – Flight Fm (XL)\nw/ Lil Yachty & Future & Playboi Carti – Flex Up (QUALITY CONTROL)\n(26:30) ID – ID\nLet me know if I missed anything", duration: nil)
check(lot.map(\.title) == ["ID – ID", "Joy Orbison – Flight Fm (XL)", "ID – ID"] && lot.map(\.note) == [nil, "w/ Lil Yachty & Future & Playboi Carti – Flex Up (QUALITY CONTROL)", nil], "A \"w/\" line under a track becomes its note; other loose lines are ignored")
// Comments from Overmono's Lost Village 2026 set (bVwguT23r0k): track-ID questions, not a tracklist.
let overmono = ["Need that unreleased \"Ray Tune\" from Joy Orbison ASAP 36:10", "22:40 TF IS THIS?!?!?!??!?!?!?", "also 23:00 track ID plz",
                "what is the marianne remix ID at 19:50??", "19:06 song ID?", "I NEED to know what ID is 19:00 😮", "18:58 track ID?", "23:00 what is this wow"]
check(Tracklist.best(comments: overmono, description: "Live from The Outpost with Defender at Lost Village 2026... 🌲", duration: nil).isEmpty, "Scattered track-ID questions are not stitched into a tracklist")
let response: [String: Any] = ["onResponseReceivedEndpoints": [["reloadContinuationItemsCommand": ["continuationItems": [
    ["commentThreadRenderer": ["replies": ["commentRepliesRenderer": ["contents": [["continuationItemRenderer": ["continuationEndpoint": ["continuationCommand": ["token": "replies"]]]]]]]]],
    ["continuationItemRenderer": ["continuationEndpoint": ["continuationCommand": ["token": "page2"]]]]]]]],
    "frameworkUpdates": ["entityBatchUpdate": ["mutations": [["payload": ["commentEntityPayload": ["properties": ["content": ["content": "0:00 A"]]]]], ["payload": ["commentEntityPayload": ["properties": ["content": ["content": "nice"]]]]]]]]]
check(Tracklist.comments(in: response) == ["0:00 A", "nice"] && Tracklist.nextPageToken(in: response) == "page2", "Comments and the next page are read from a YouTube response")
let watchPage: [String: Any] = ["contents": [["itemSectionRenderer": ["sectionIdentifier": "comment-item-section", "contents": [["continuationItemRenderer": ["continuationEndpoint": ["continuationCommand": ["token": "first"]]]]]]]],
                            "description": ["attributedDescription": ["content": "About this mix"]]]
check(Tracklist.commentsToken(in: watchPage) == "first" && Tracklist.description(in: watchPage) == "About this mix", "The comments token and description are read from the watch response")
let link = MusicLink(id: "i43tkaTXtwI", title: "Mix", author: "Lofi Girl", thumbnail: "", tracks: parsed)
check(try! JSONDecoder().decode(MusicLink.self, from: JSONEncoder().encode(link)) == link, "The pasted link persists")
print("Passed: YouTube links, tracklist parsing and cleaning, picking the best comment, and reading YouTube responses.")
