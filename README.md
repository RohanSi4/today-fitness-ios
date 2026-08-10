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
- Matches planned runs against completed Apple Health workouts and shows distance,
  duration, and pace
- Shows the full week in Run and Lift + other columns with plan versus actual status
- Keeps a compact weekly snapshot on Today and a more useful detailed view one tap away
- Adds a Lock Screen widget that moves from morning weight, to today’s work, to what is
  left, to done with workout stats
- Refreshes the widget when weight, lifting, the coach plan, or a synced Apple Watch run changes
- Shares only a small derived widget snapshot through an App Group, never exact weight or exercise detail
- Opens directly to a five-second morning weight logger
- Saves body weight to Apple Health and mirrors it in a private local history
- Schedules an 8:30 AM reminder and a noon fallback when weight is still missing
- Watches for newly completed HealthKit sleep and can move the reminder closer to wake time
- Keeps working when the coach plan ends, expires, or cannot refresh
- Starts Upper, Lower, Push, Pull, Legs, Chest, or Back from a useful exercise template
- Offers a blank workout when I just want to add exercises as I go
- Opens weight, plan, or the workout picker from Siri, Spotlight, and Shortcuts
- Links directly to those App Shortcuts so they are easy to add to Siri or an Action Button
- Sends the coach's distance goal into Apple Workout with WorkoutKit, without starting a second workout session
- Reuses the previous exercise order and values for each named workout type
- Starts from editable Upper A, Lower A, Upper B, and Lower B routines with per-exercise set targets
- Distinguishes warm-up, working, and backoff sets so preparation does not inflate progression or volume
- Counts upward from the last completed set instead of forcing a rest countdown
- Adjusts weight by exercise-specific increments and reps one at a time
- Keeps dumbbell loads per hand and unilateral reps per side
- Shows the last three performances for each exercise
- Reuses the last completed values when an exercise is added during a workout
- Keeps recent exercises at the top and lets several be added in one pass
- Folds completed exercises down and moves the next unfinished work into view
- Reorders exercises by touch-and-hold drag when gym equipment is busy
- Lets me close a workout, use the rest of the app, and resume with every set intact
- Keeps discard in a secondary menu with a confirmation instead of making it the main exit
- Keeps run stretches as a quick visual reference instead of making every session a checklist
- Focuses the warm-up on seven marathon-relevant dynamic moves and trims the post-run list to five useful holds
- Adds a timer-first post-run flow that waits for play, guides 30-second holds, gives 5 seconds to switch, and supports pause, back, skip, and a routine wheel
- Searches the loaded offline catalog and reports its actual current size in the UI
- Shows a compact live coverage card with direct working-set counts and any planned muscles still missing
- Shows workout duration, PRs, next targets, weekly training totals, actionable strength trends, and a private 30-day weight trend
- Lets workouts and weights be corrected, deleted, or reopened from History without rebuilding them
- Debounces live workout saves, protects the file while the phone is locked, and keeps a last-good backup
- Preserves the original sleep, movement, and daily recap experience under Insights
- Encrypts the full weight and lifting snapshot with AES-256-GCM before upload
- Keeps the phone write token and encryption key in Keychain
- Saves first, retries failed syncs later, and shows the connection state in Insights
- Publishes only split, duration, working sets, and broad muscle groups to the fitness page
- Never publishes exact weight or a weight summary to the public site
- Includes App Store privacy manifests for health, fitness, app settings, and App Group settings

## The private data boundary

```text
Public coaching plan
        │
        ▼
      Today app ─────────► Apple Health body weight
        │
        ├── protected local history
        ├── AES-256-GCM private snapshot ─► website transport ─► coach decrypts
        └── safe strength summary ───────────────────────────► fitness page

Apple Watch workout ─► Apple Health ─► HealthFit ─► marathon coach
        ▲
        └── Today schedules the coach's run through WorkoutKit
```

Today does not replace or rewrite Apple Watch workouts. The Watch and HealthFit remain
the workout source of truth. Today records the exercise detail that a generic Strength
Training workout cannot capture.

Exercise choices, reps, lifting weights, and daily weight history do not go to the public
fitness dashboard. The public strength view uses split, duration, working-set count,
and broad muscle frequency without exposing the underlying gym log. No body-weight
number, average, change, goal, or logging history is sent to the public site.

## Exercise catalog and anatomy

Today ships its own library of 255 exercises, so the catalog is complete with no
network. It leans deliberately toward machines, cables, and their attachments, because
that is what most of my sessions are made of, and every entry has a hand-written
per-head muscle map.

That bundled library is then topped up from
[`yuhonas/free-exercise-db`](https://github.com/yuhonas/free-exercise-db), an Unlicense
public-domain dataset with more than 800 exercises. The import only adds movements the
bundled library does not already cover, matching on names and aliases with punctuation
and plurals ignored so the list does not fill with near-duplicates. Its muscle labels
are deliberately treated as a search fallback because categories such as `arms` or
`back` are not precise enough for the anatomy view.

### Machine brands

The same number on two makers' machines is not the same load, so the brand is recorded
rather than ignored. It is an attribute of a logged exercise, not a separate catalog
row: choosing Cybex on a lat pulldown logs it under `lat-pulldown@cybex`, which keeps
its own weight history and cannot be averaged in with the Hammer Strength one. The
searchable list still has exactly one row per movement, so a brand never buries the lift
you were looking for. Brands are offered for pin-loaded, plate-loaded, cable, and Smith
work and withheld from barbell, dumbbell, and bodyweight movements, where a 45 lb bar is
a 45 lb bar.

A small number of machines are their own catalog entry because the maker *is* the
movement: a Hammer Strength Iso-Lateral row does not share a movement path with a generic
seated row. Those come from manufacturers' published product lines, and brands whose
lineup is a set of otherwise generic movements get no such entries.

Today adds a more detailed local mapping for the exercises that matter, including:

- upper, middle, and lower chest
- front, side, and rear delts
- lats, rhomboids, and upper, middle, and lower traps
- long and short biceps heads plus brachialis
- long, lateral, and medial triceps heads
- individual quad regions, hamstrings, glutes, adductors, and abductors
- gastrocnemius, soleus, abs, obliques, tibialis anterior, and lower back

The live coverage view counts direct completed working sets. Warm-ups stay out of the
dose, and Today does not compare raw machine tonnage across unrelated exercises.

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
    │   ├── WeeklyTrainingBuilder
    │   ├── WeightLogView
    │   ├── guided run warm-up and cooldown
    │   ├── WorkoutStartFlow
    │   └── WorkoutLogView
    ├── History
    └── Insights
        ├── actionable private weight and strength trends
        ├── editable hypertrophy routines
        └── DailyRecapView

TodayStore
    ├── debounced active-workout persistence
    ├── protected atomic private JSON
    └── last-good local recovery copy

CoachSyncService
    ├── Keychain pairing credentials
    ├── local-first retry state
    ├── AES-256-GCM private snapshot
    ├── strict production endpoint boundary
    └── smaller strength-only public projection

HealthKitManager
    ├── read sleep and movement
    ├── read completed running workouts
    ├── write body mass
    └── observe completed sleep and workout changes

TodayWidget
    ├── Lock Screen inline and rectangular layouts
    ├── Home Screen small layout
    ├── app-triggered WidgetKit refreshes
    └── privacy-safe App Group snapshot

NotificationManager
    ├── wake-aware prompt
    ├── 8:30 AM fallback
    └── noon follow-up

WatchWorkoutService
    ├── validates the coach's run distance and date
    ├── schedules a stable, duplicate-safe WorkoutKit plan
    └── leaves workout recording to Apple Watch
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
7. On first launch, allow Apple Health access and notifications. The workout logger remains separate from the Apple Watch workout record, and exact weight stays private.

Before treating the signed integration paths as release-verified, complete
[`docs/REAL_DEVICE_VALIDATION.md`](docs/REAL_DEVICE_VALIDATION.md). Simulator and CI
cannot substitute for that device record.

To add the daily widget, hold the iPhone Lock Screen, tap **Customize**, choose
**Lock Screen**, tap the widget area below the clock, and add **Today**. The rectangular
version shows the most context. The inline version fits above the clock, and the small
version is also available on the Home Screen.

To connect the private coach, run `npm run pair:today` from the Marathon Prep Bot
repo. Add the generated read and write transport tokens to Vercel, then paste the
pairing code into **Insights > Coach sync**. The encryption key is never
added to the website environment.

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

The automated unit and UI suites cover the original sleep scoring and recap correctness plus Today’s
same-day weight replacement, correction precedence, invalid values, active-workout relaunch, backup recovery,
routine persistence, workout correction and reopening, warm-up exclusion, detailed muscle scoring, prior-value reuse,
coach-plan lift detection, weekly plan and actual matching, every widget state, widget
privacy, stretch routine state, stretch artwork integrity, endpoint allowlisting,
payload bounds, and isolation from production sync during tests. UI coverage opens the
quick weight logger, opens the weekly snapshot, checks the stretch reference and
optional walkthrough, closes and resumes an active workout, and verifies that Health
Recap remains available from Insights.

## Next platform slice

The current Apple Watch job stays simple. For runs, Today can schedule the coach's
distance goal in Apple Workout through WorkoutKit. For lifting, I still start Apple's
Strength Training workout and use Today on the phone for sets. A separate Watch workout
session would duplicate ownership and create bad HealthKit edge cases.

The iPhone Lock Screen widget now covers the daily glance without starting another live
workout session. The next justified Watch slice is a read-only Smart Stack widget for
today’s run and Upper or Lower plan. It should appear only when the wrist glance proves
more useful than the existing plan shortcut. A workout Live Activity remains optional
because Apple Watch still owns workout recording.

## Future food tracking

Once the weight and workout loop is proven, Today could add a rough food estimator. The
goal would not be another MyFitnessPal or perfect calorie accounting. It would make basic
awareness easy enough to keep using: describe a meal in a few words, get an editable
calorie and protein estimate, and see a simple daily range alongside longer-term weight
trends. Exact ingredients, barcode scanning, and detailed macro targets can stay optional.

Food history should remain private by default. Any future coach connection should use a
small derived summary only after the estimator is accurate enough to be useful.
