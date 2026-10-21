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
            guard let refreshTask = task as? BGAppRefreshTask else {
                // Nunca deve acontecer (só registramos um BGAppRefreshTaskRequest), mas
                // encerrar a tarefa é melhor que derrubar o app num launch de background.
                task.setTaskCompleted(success: false)
                return
            }
            handle(task: refreshTask)
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
        // `expirationHandler` instalado ANTES de o trabalho começar: atribuí-lo depois
        // deixava uma janela em que uma expiração não tinha quem a tratasse. E a
        // expiração precisa chamar `setTaskCompleted(success: false)` — sem isso o iOS
        // conta a tarefa como abandonada e passa a conceder menos tempo de background.
        let completed = CompletionGuard()
        let workTask = Task {
            // Lets the send-time policy decide the day's slots even if the app isn't
            // opened that day.
            await NotificationScheduler.shared.ensureTodayScheduled()
            await NotificationScheduler.shared.tick()
            if completed.claim() { box.task.setTaskCompleted(success: true) }
        }
        task.expirationHandler = {
            workTask.cancel()
            if completed.claim() { box.task.setTaskCompleted(success: false) }
        }
    }
}

/// Garante que `setTaskCompleted` é chamado uma vez só: o trabalho pode terminar no
/// mesmo instante em que o sistema expira a tarefa, e chamar duas vezes é erro de uso.
private final class CompletionGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return false }
        done = true
        return true
    }
}
