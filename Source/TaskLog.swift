import Foundation

struct TaskItem: Codable, Equatable {
    var id: String
    var title: String
    var created: Date
    var finished: Date?
    var removed: Date?
    var done: Bool { finished != nil }
}

struct WorkSession: Codable, Equatable {
    var taskID: String
    var mode: TimerMode
    var start: Date
    var seconds: Double
    // True when a Pomodoro focus or countdown ran to its end, so finished intervals can be counted.
    var completed: Bool?
}

// Up to three tasks for the day. The top unfinished task earns time from whichever timer is running.
struct TaskLog: Codable {
    static let capacity = 3
    static let titleLimit = 80
    var tasks: [TaskItem] = []
    // Every removed task, timed or not, so the full record of tasks survives.
    var archive: [TaskItem] = []
    var sessions: [WorkSession] = []
    // While tracking, the open session is always the last one.
    private var tracking: (taskID: String, mode: TimerMode, elapsed: Double)?
    private enum CodingKeys: String, CodingKey { case tasks, archive, sessions }

    var activeTask: TaskItem? { tasks.first { !$0.done } }
    var isTracking: Bool { tracking != nil }
    private var unfinishedCount: Int { tasks.filter { !$0.done }.count }

    static func cleanTitle(_ text: Substring) -> String? {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(titleLimit).trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }

    // Returns true when the list changed.
    @discardableResult mutating func handle(_ action: String, date: Date = Date(), makeID: () -> String = { UUID().uuidString }) -> Bool {
        guard let colon = action.firstIndex(of: ":") else { return false }
        let verb = action[..<colon], rest = action[action.index(after: colon)...]
        if verb == "task-add" {
            guard let title = Self.cleanTitle(rest) else { return false }
            if tasks.count >= Self.capacity {
                // A full list makes room by clearing its lowest finished task.
                guard let index = tasks.lastIndex(where: { $0.done }) else { return false }
                retire(at: index, date: date)
            }
            tasks.insert(TaskItem(id: makeID(), title: title, created: date), at: unfinishedCount)
            return true
        }
        let parts = rest.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let id = parts.first, let index = tasks.firstIndex(where: { $0.id == id }) else { return false }
        let argument = parts.count > 1 ? parts[1] : ""
        switch verb {
        case "task-edit":
            guard let title = Self.cleanTitle(argument), title != tasks[index].title else { return false }
            tasks[index].title = title
        case "task-done":
            guard argument == "1" || argument == "0" else { return false }
            let done = argument == "1"
            guard tasks[index].done != done else { return false }
            var task = tasks.remove(at: index)
            task.finished = done ? date : nil
            // Finished tasks sink to the bottom. Reopened ones rejoin the end of the unfinished group.
            tasks.insert(task, at: done ? tasks.count : unfinishedCount)
        case "task-move":
            guard !tasks[index].done, let target = Int(argument) else { return false }
            let destination = min(max(0, target), unfinishedCount - 1)
            guard destination != index else { return false }
            tasks.insert(tasks.remove(at: index), at: destination)
        case "task-delete":
            retire(at: index, date: date)
        default:
            return false
        }
        return true
    }

    private mutating func retire(at index: Int, date: Date) {
        var task = tasks.remove(at: index)
        task.removed = date
        archive.append(task)
    }

    // Call before and after anything that changes the timer or the list, so time goes to the task that earned it.
    mutating func record(_ state: TimerState, at now: Double, date: Date = Date(), calendar: Calendar = .current) {
        let task = state.countsTowardTask ? activeTask : nil
        let elapsed = state.trackedElapsed(at: now)
        if let current = tracking, current.taskID == task?.id, current.mode == state.mode {
            sessions[sessions.count - 1].seconds += max(0, elapsed - current.elapsed)
            tracking?.elapsed = elapsed
            // Split at midnight so each day's history is its own.
            if !calendar.isDate(sessions[sessions.count - 1].start, inSameDayAs: date) {
                sessions.append(WorkSession(taskID: current.taskID, mode: current.mode, start: date, seconds: 0))
            }
            return
        }
        if tracking != nil, let last = sessions.last {
            if last.seconds < 1 { sessions.removeLast() }
            else if state.isComplete && state.mode == last.mode { sessions[sessions.count - 1].completed = true }
        }
        tracking = nil
        guard let task else { return }
        sessions.append(WorkSession(taskID: task.id, mode: state.mode, start: date, seconds: 0))
        tracking = (task.id, state.mode, elapsed)
    }

    func seconds(for id: String) -> Double { sessions.reduce(0) { $1.taskID == id ? $0 + $1.seconds : $0 } }

    func snapshot() -> [String: Any] {
        ["tasks": tasks.map { ["id": $0.id, "title": $0.title, "done": $0.done, "seconds": seconds(for: $0.id)] as [String: Any] },
         "tracking": isTracking]
    }

    // Newest day first. Each task's time is split by the mode that earned it.
    func history(calendar: Calendar = .current) -> [[String: Any]] {
        var names: [String: TaskItem] = [:]
        for task in archive + tasks { names[task.id] = task }
        var days: [Date: [String: [TimerMode: Double]]] = [:]
        for session in sessions where session.seconds >= 1 {
            days[calendar.startOfDay(for: session.start), default: [:]][session.taskID, default: [:]][session.mode, default: 0] += session.seconds
        }
        struct Row { var title: String; var finished: Bool; var modes: [TimerMode: Double]; var total: Double }
        return days.keys.sorted(by: >).map { day -> [String: Any] in
            let rows: [Row] = days[day]!.map { id, modes in
                let task = names[id]
                let finished = task?.finished.map { calendar.isDate($0, inSameDayAs: day) } ?? false
                return Row(title: task?.title ?? "Removed task", finished: finished, modes: modes, total: modes.values.reduce(0, +))
            }
            let ordered = rows.sorted { $0.total != $1.total ? $0.total > $1.total : $0.title < $1.title }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            return ["date": String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!),
                    "tasks": ordered.map { row -> [String: Any] in
                        var result: [String: Any] = ["title": row.title, "finished": row.finished, "seconds": row.total]
                        for (mode, seconds) in row.modes { result[mode.rawValue] = seconds }
                        return result
                    }]
        }
    }
}
