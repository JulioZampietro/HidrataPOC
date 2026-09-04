import BackgroundTasks
import Foundation

/// Best-effort background top-up for `NotificationScheduler.tick()` when the app isn't
/// foregrounded. `BGAppRefreshTask` scheduling is opportunistic — iOS decides when (or
/// whether) it actually runs based on usage patterns and battery state, so this is a
/// supplement to, not a replacement for, the foreground polling in `HidrataPOCApp`.
/// `BGAppRefreshTask` isn't `Sendable`, but the system only ever touches one instance
/// serially through its short lifecycle (launch handler → our completion). Wrapping it
/// lets that single instance cross into the `Task` that awaits the actual work.
private final class BGTaskBox: @unchecked Sendable {
    let task: BGAppRefreshTask
    init(_ task: BGAppRefreshTask) { self.task = task }
}

enum BackgroundRefreshService {
    static let taskIdentifier = "com.hidratapoc.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            handle(task: task as! BGAppRefreshTask)
        }
    }

    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date.now.addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(task: BGAppRefreshTask) {
        scheduleNext()

        let box = BGTaskBox(task)
        let workTask = Task {
            await NotificationScheduler.shared.tick()
            box.task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { workTask.cancel() }
    }
}
