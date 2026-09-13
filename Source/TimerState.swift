import Foundation

enum TimerMode: String, Codable { case stopwatch, pomodoro, timer }
enum FocusPhase: String, Codable { case focus, shortBreak, longBreak }

struct TimerState: Codable {
    var mode: TimerMode = .stopwatch
    var phase: FocusPhase = .focus
    var stopwatchElapsed = 0.0
    var pomodoroElapsed = 0.0
    var timerElapsed = 0.0
    var timerDuration = 10.0 * 60
    var timerCompleted = false
    var startedAt: Double?
    var completed = false
    var completedFocusCount = 0
    var focusMinutes = 25
    var breakMinutes = 5
    var longBreakMinutes = 15

    var duration: Double {
        if mode == .timer { return timerDuration }
        switch phase { case .focus: return Double(focusMinutes * 60); case .shortBreak: return Double(breakMinutes * 60); case .longBreak: return Double(longBreakMinutes * 60) }
    }
    func elapsed(at now: Double) -> Double {
        let stored = mode == .stopwatch ? stopwatchElapsed : mode == .timer ? timerElapsed : pomodoroElapsed
        return stored + (startedAt.map { max(0, now - $0) } ?? 0)
    }
    mutating func pause(at now: Double) {
        let value = elapsed(at: now)
        if mode == .stopwatch { stopwatchElapsed = value } else if mode == .timer { timerElapsed = min(duration, value) }
        else { pomodoroElapsed = min(duration, value) }
        startedAt = nil
    }
    // A long sleep completes just this interval. The next one waits for the user.
    @discardableResult mutating func tick(at now: Double) -> Bool {
        guard mode != .stopwatch, startedAt != nil, elapsed(at: now) >= duration else { return false }
        startedAt = nil
        if mode == .timer { timerElapsed = duration; timerCompleted = true }
        else { pomodoroElapsed = duration; completed = true; if phase == .focus { completedFocusCount += 1 } }
        return true
    }
    @discardableResult mutating func handle(_ action: String, at now: Double) -> Bool {
        if action.hasPrefix("pomodoro-settings:") {
            let parts = action.dropFirst("pomodoro-settings:".count).split(separator: ",", omittingEmptySubsequences: false)
            let values = parts.compactMap { Int($0) }
            guard mode == .pomodoro, parts.count == 3, values.count == 3, values.allSatisfy({ (1...180).contains($0) }) else { return false }
            guard values != [focusMinutes, breakMinutes, longBreakMinutes] else { return tick(at: now) }
            focusMinutes = values[0]; breakMinutes = values[1]; longBreakMinutes = values[2]
            phase = .focus; pomodoroElapsed = 0; completed = false; completedFocusCount = 0; startedAt = nil
            return false
        }
        let justCompleted = tick(at: now)
        if justCompleted && action == "toggle" { return true }
        if action.hasPrefix("adjust:"), mode == .timer, let minutes = Int(action.dropFirst(7)), [-10, -5, -1, 1, 5, 10].contains(minutes) {
            let value = elapsed(at: now), wasRunning = startedAt != nil
            timerDuration = min(24 * 60 * 60, max(0, timerDuration + Double(minutes * 60)))
            timerElapsed = min(value, timerDuration)
            timerCompleted = timerDuration > 0 && timerElapsed >= timerDuration
            startedAt = wasRunning && timerDuration > 0 ? now : nil
            if wasRunning && timerCompleted { startedAt = nil; return true }
        } else if action.hasPrefix("mode:"), let next = TimerMode(rawValue: String(action.dropFirst(5))), next != mode {
            pause(at: now); mode = next
        } else if action == "toggle" {
            if startedAt != nil { pause(at: now) }
            else {
                if mode == .timer {
                    guard timerDuration > 0 else { return justCompleted }
                    if timerCompleted { timerElapsed = 0; timerCompleted = false }
                }
                if mode == .pomodoro && completed {
                    phase = phase == .focus ? (completedFocusCount % 4 == 0 ? .longBreak : .shortBreak) : .focus
                    pomodoroElapsed = 0; completed = false
                }
                startedAt = now
            }
        } else if action == "reset" {
            startedAt = nil
            if mode == .stopwatch { stopwatchElapsed = 0 }
            else if mode == .timer { timerElapsed = 0; timerCompleted = false }
            else { pomodoroElapsed = 0; completed = false }
        }
        return justCompleted
    }
    var isComplete: Bool { mode == .pomodoro ? completed : mode == .timer ? timerCompleted : false }
    func snapshot(at now: Double) -> [String: Any] {
        let value = elapsed(at: now)
        return ["mode": mode.rawValue, "phase": phase.rawValue,
                "seconds": mode == .stopwatch ? floor(value) : ceil(max(0, duration - value)),
                "running": startedAt != nil, "elapsed": value,
                "completed": isComplete, "canStart": mode != .timer || timerDuration > 0, "timerDuration": timerDuration,
                "focusMinutes": focusMinutes, "breakMinutes": breakMinutes, "longBreakMinutes": longBreakMinutes,
                "completedFocusCount": completedFocusCount,
                "focusNumber": completed && phase == .focus ? ((max(1, completedFocusCount) - 1) % 4 + 1) : (completedFocusCount % 4 + 1)]
    }
}

// Save elapsed time, never the process-local monotonic clock origin.
struct UpdateCheckpoint: Codable {
    var state: TimerState
    var date: Date
    var running: Bool
    init(state: TimerState, now: Double, date: Date = Date()) {
        self.state = state; self.date = date; running = state.startedAt != nil
        self.state.pause(at: now)
    }
    func restored(at now: Double, date: Date = Date()) -> TimerState {
        var result = state
        if running { result.startedAt = now - max(0, date.timeIntervalSince(self.date)) }
        return result
    }
}
