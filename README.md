# Today

Today is my private iPhone home base for training. It combines the workout plan from
my marathon coach, quick morning weight entry, detailed lifting logs, and the original
Apple Health recap in one app I can actually use every day.

[Try the Health Recap browser demo](https://health-recap.vercel.app) ·
[Read the original case study](https://rohansingh04.com/projects/health-tracker-ios)

The app is personal first. The architecture is intentionally small and configurable so
it can become a reusable starter after the real workflow is proven.

## What works

- Pulls the current privacy-safe run and Upper or Lower plan from
  `rohansingh04.com`
- Opens directly to a five-second morning weight logger
- Saves body weight to Apple Health and mirrors it in a private local history
- Schedules an 8:30 AM reminder and a noon fallback when weight is still missing
- Watches for newly completed HealthKit sleep and can move the reminder closer to wake time
- Keeps working when the coach plan ends, expires, or cannot refresh
- Starts Upper, Lower, Push, Pull, Legs, Chest, or Back from a useful exercise template
- Offers a blank workout when I just want to add exercises as I go
- Opens weight, plan, or the workout picker from Siri, Spotlight, and Shortcuts
- Reuses the previous exercise order and values for each named workout type
- Uses exactly two default working sets, with an optional extra set for strong days
- Adjusts weight by exercise-specific increments and reps one at a time
- Keeps dumbbell loads per hand and unilateral reps per side
- Shows the last three performances for each exercise
- Reuses the last completed values when an exercise is added during a workout
- Keeps recent exercises at the top and lets several be added in one pass
- Folds completed exercises down and moves the next unfinished work into view
- Lets exercises move up or down when gym equipment is busy
- Searches an offline-cached catalog of more than 700 lifting exercises
- Lights up a detailed front and back muscle map as sets are completed
- Keeps the full muscle map tucked away during the workout, then shows it in the recap
- Shows workout duration, weekly training totals, strength records, and a private 30-day weight trend
- Lets a bad workout be removed from History before it affects future defaults
- Debounces live workout saves, protects the file while the phone is locked, and keeps a last-good backup
- Preserves the original sleep, movement, and daily recap experience under Insights

## The private data boundary

```text
Public coaching plan
        │
        ▼
      Today app ─────────► Apple Health body weight
        │
        ├── private lifting history
        ├── private weight trends
        └── muscle and strength insights

Apple Watch workout ─► Apple Health ─► HealthFit ─► marathon coach
```

Today does not replace or rewrite Apple Watch workouts. The Watch and HealthFit remain
the workout source of truth. Today records the exercise detail that a generic Strength
Training workout cannot capture.

Exact body weight, exercise choices, sets, reps, and lifting weights do not go to the
public fitness dashboard. A future public muscle view can use broad weekly muscle
frequency without exposing the underlying private log.

## Exercise catalog and anatomy

The searchable catalog builds on
[`yuhonas/free-exercise-db`](https://github.com/yuhonas/free-exercise-db), an Unlicense
public-domain dataset with more than 800 exercises. Its muscle labels are deliberately
treated as a search fallback because categories such as `arms` or `back` are not precise
enough for the anatomy view.

Today adds a more detailed local mapping for the exercises that matter, including:

- upper, middle, and lower chest
- front, side, and rear delts
- lats, rhomboids, and upper, middle, and lower traps
- long and short biceps heads plus brachialis
- long, lateral, and medial triceps heads
- individual quad regions, hamstrings, glutes, adductors, and abductors
- gastrocnemius, soleus, abs, obliques, tibialis anterior, and lower back

The heat map scores completed working sets. It does not compare raw machine tonnage
across unrelated exercises.

Because I normally use lifting straps for back work, incidental grip work from an
imported pulling exercise does not light the forearms. Curls can still give them a
small amount of credit, and direct forearm exercises count fully.

The base anatomy vectors are adapted from
[`HichamELBSI/react-native-body-highlighter`](https://github.com/HichamELBSI/react-native-body-highlighter)
under the MIT License. Today adds the side-by-side anatomy view, smaller muscle splits,
workout scoring, labels, and native SwiftUI interaction.

## Architecture

```text
SwiftUI app shell
    ├── Today
    │   ├── TrainingPlanService
    │   ├── WeightLogView
    │   ├── WorkoutStartFlow
    │   └── WorkoutLogView
    ├── History
    └── Insights
        ├── MuscleMapView
        ├── private weight and strength trends
        └── DailyRecapView

TodayStore
    ├── debounced active-workout persistence
    ├── protected atomic private JSON
    └── last-good local recovery copy

HealthKitManager
    ├── read sleep and movement
    ├── write body mass
    └── observe completed sleep sessions

NotificationManager
    ├── wake-aware prompt
    ├── 8:30 AM fallback
    └── noon follow-up
```

The app targets iOS 17 and uses SwiftUI, HealthKit, App Intents, async/await, and
protocol-backed services. Simulator uses deterministic recap data and local weight
entries because HealthKit is only available on a physical iPhone.

## Put Today on your iPhone

The project already uses automatic signing and has Rohan's development team selected.

1. Connect the iPhone to the Mac with USB-C and tap **Trust** on both devices if asked.
2. In Xcode, open **Xcode > Settings > Accounts** and make sure the Apple Account for the selected team is signed in.
3. Open `Health Tracker.xcodeproj`, click the blue **Health Tracker** project, select the **Health Tracker** target, then open **Signing & Capabilities**. Leave **Automatically manage signing** on. If Xcode shows a signing error, choose the available Personal Team or paid team.
4. In the top Xcode toolbar, click the device name beside the **Health Tracker** scheme and choose the connected iPhone instead of the simulator.
5. Press the Run triangle or `Command-R`.
6. If the phone asks for Developer Mode, open **Settings > Privacy & Security > Developer Mode**, turn it on, restart, confirm it after the restart, then press Run in Xcode again.
7. On first launch, allow Apple Health access and notifications. Body weight stays private and the workout logger remains separate from the Apple Watch workout record.

After the first wired pairing, Xcode can usually reconnect to the phone on the same network. A free Personal Team install expires after seven days, so press Run again from Xcode when it needs to be refreshed. A paid Apple Developer team avoids that weekly reinstall.

## Run it in Simulator

Requirements: Xcode 15 or newer and iOS 17 or newer.

1. Open `Health Tracker.xcodeproj`.
2. Select an iPhone Simulator for the interface and sample-data flow.
3. Use the physical-iPhone steps above to test Apple Health reads, body-weight writes,
   sleep background delivery, and notifications.

The project currently uses the existing `Health Tracker` scheme and bundle identifier,
while the installed display name is **Today**.

## Tests

The 31-test suite covers the original sleep scoring and recap correctness plus Today’s
same-day weight replacement, invalid values, active-workout relaunch, backup recovery,
two-set workout reset, workout deletion, detailed muscle scoring, prior-value reuse,
and coach-plan lift detection. UI coverage opens the quick weight logger and verifies
that Health Recap remains available from Insights.

## Next platform slice

The next slice is a Lock Screen widget backed by the same App Intents. It should show
whether morning weight is logged and today’s run plus Upper or Lower plan without
showing the exact weight. Private iCloud export for the coaching repo also waits on the
app’s permanent signing and iCloud capability setup.
