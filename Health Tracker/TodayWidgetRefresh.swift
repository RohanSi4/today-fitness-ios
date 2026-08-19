import Foundation
import UIKit

/// Keeps trying to get a run onto the Lock Screen after the wake that carried it
/// has already failed.
///
/// **The failure this exists for.** A watch run syncing to Apple Health wakes
/// this app in the background through `HKObserverQuery`. If the phone is locked
/// - which it is, every time, because a run ends with the phone in a pocket -
/// `TodayStore` comes up empty under `.completeFileProtection` and
/// `TodayWidgetPublisher.publish` correctly refuses to write. Refusing is right:
/// publishing an unread store told the Lock Screen to "Log morning weight" for a
/// day already logged and zeroed the week's mileage.
///
/// But refusing silently is not. The stored payload left behind is not merely
/// old, it is *wrong in a specific direction*: it still says "Run remaining" for
/// the run that just finished, and nothing in the system will correct it. The
/// widget's own timeline books its next refresh for 08:30, noon, then tomorrow,
/// so an afternoon run sat under a stale prompt until the app was opened by
/// hand. The observer, meanwhile, had already reported the update as handled, so
/// HealthKit never sent it again.
///
/// The missing piece is a second chance at the moment the data becomes readable.
/// `protectedDataDidBecomeAvailable` is exactly that moment: it fires on the
/// first unlock, while the app is still alive in the background, which is
/// *before* he swipes past the Lock Screen. So the screen he is looking at is
/// already right by the time he looks at it.
@MainActor
final class TodayWidgetRefresh {
    static let shared = TodayWidgetRefresh()

    /// True when the last attempt could not write a payload, so the Lock Screen
    /// is knowingly out of date and owes a retry.
    private(set) var isPending = false

    /// Reads the current state and publishes it, reporting whether it landed.
    /// Injected rather than reached for, so this type holds no opinion about
    /// where the plan, the runs or the store come from, and a test can hand it a
    /// counter instead of HealthKit.
    private var publish: (@MainActor () -> Bool)?

    private var unlockObserver: (any NSObjectProtocol)?
    private var center: NotificationCenter = .default

    /// - Parameter unlockNotification: overridden only by tests.
    ///   `UIApplication.protectedDataDidBecomeAvailableNotification` is not
    ///   postable by hand in a unit test without lying to the whole process.
    func start(
        center: NotificationCenter = .default,
        unlockNotification: Notification.Name = UIApplication.protectedDataDidBecomeAvailableNotification,
        publish: @escaping @MainActor () -> Bool
    ) {
        self.publish = publish
        guard unlockObserver == nil else { return }
        self.center = center
        unlockObserver = center.addObserver(
            forName: unlockNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.retryIfPending()
            }
        }
    }

    /// Publish now, remembering the attempt if it could not be satisfied.
    func run() {
        guard let publish else { return }
        isPending = !publish()
    }

    /// The unlock hook. Deliberately a no-op when nothing is owed: an unlock is a
    /// frequent event and a widget reload is a budgeted one, so this must not
    /// spend a refresh restating a Lock Screen that is already correct.
    func retryIfPending() {
        guard isPending else { return }
        run()
    }

    /// Only for the foreground path, which has just published from a store it
    /// knows is readable. Without this a background failure would keep the flag
    /// raised for the rest of the day and burn a reload on every unlock.
    func clearPending() {
        isPending = false
    }

    /// Tears the unlock hook down. Only tests call this - the app's instance is a
    /// singleton that lives as long as the process, and a `deinit` on a
    /// `@MainActor` type cannot touch isolated state to do it anyway.
    func stop() {
        guard let unlockObserver else { return }
        center.removeObserver(unlockObserver)
        self.unlockObserver = nil
        publish = nil
    }
}
