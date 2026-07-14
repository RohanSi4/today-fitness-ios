# Health Recap

Health Recap turns Apple Health sleep and movement samples into a focused, privacy-first daily briefing. The app is built with SwiftUI, HealthKit, async/await, and deterministic sample data so the complete experience is reviewable without a physical device.

## What it shows

- A weighted sleep score based on duration, efficiency, and wake-time consistency
- Sleep duration, time in bed, bedtime, wake time, and seven-day comparisons
- Steps, walking distance, active energy, and seven-day baselines
- A plain-language takeaway selected from the strongest sleep and movement signals
- An opt-in recap notification when the app observes a newly completed sleep session

## Architecture

```text
SwiftUI screen
    └── DailyRecapViewModel (loading and presentation state)
        └── DailyRecapBuilder (recap orchestration and domain rules)
            ├── HealthDataProviding
            │   └── HealthKitManager
            └── SleepScoreCalculator / CircularClock / DailyRecapInsight
```

Dependencies are protocol-backed, so the presentation flow can use HealthKit on iPhone and deterministic fixtures in Simulator and tests. Domain models do not depend on SwiftUI or HealthKit types.

## Data correctness details

- Overlapping sleep-stage intervals are merged before duration is calculated, avoiding double-counting samples from multiple stages or sources.
- Bedtime and wake-time baselines use a circular mean, so 11:50 PM and 12:10 AM average to midnight instead of noon.
- Movement comparisons use the seven calendar days *before* the recap day; the current value is not included in its own baseline.
- HealthKit authorization is requested only for read types. Notification permission is a separate, explicit action.

## Running it

Requirements: Xcode 15+, iOS 17+, and an Apple Developer account for HealthKit device testing.

1. Open `Health Tracker.xcodeproj`.
2. Select an iPhone Simulator to explore the automatic sample-data experience.
3. Select a signed physical iPhone to grant Health access and review personal data.

The overflow menu can switch between sample and Health data. Simulator always falls back to sample data because HealthKit is unavailable there. UI tests launch with `-useMockData true` for a deterministic state.

## Tests

The test suite covers sleep-score boundaries, overlap-safe session assembly, midnight-aware time math, seven-day baseline selection, deterministic fixtures, Simulator fallback, and the sample recap’s core UI sections.

## Privacy and limitations

- Health data stays on-device and is never uploaded.
- The app requests read-only access to sleep, steps, walking/running distance, and active energy.
- HealthKit behavior must be validated on a physical iPhone; Simulator validates the full UI and sample-data path only.
- Notification scheduling is currently best-effort while the app is active. Background HealthKit delivery is not implemented, so this is not yet a guaranteed morning alarm.
