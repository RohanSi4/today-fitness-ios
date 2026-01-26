# Health Tracker

A modern iOS app built with SwiftUI + HealthKit. Current focus: a **Daily Health Recap** with a sleep-first morning highlight and simple 7-day comparisons.

## Current MVP: Daily Recap Dashboard

**Morning flow**
- Detect the **sleep session that just ended** (most recent session end time).
- Best-effort notification at **wakeTime + 20 minutes** with a short sleep highlight.
- Tap opens `DailyRecapView(date: yesterday)`.

**“Yesterday” definition**
- **Sleep:** the sleep session that just ended (most recent session end).
- **Movement stats:** the **calendar day before today**, midnight → midnight (local time).

## Daily Recap: MVP Sections

**Sleep (required)**
- Sleep score
- Time asleep
- Time in bed
- Efficiency
- Bedtime + wake time
- Comparison vs 7‑day average

**Movement (required)**
- Steps
- Walking distance
- Active energy
- Each shows yesterday, 7‑day average, and delta text

**Insight (required)**
- One sentence summarizing the most meaningful signal across metrics.

**Optional later**
- Activity rings
- Resting HR / HRV
- Workouts / mindful minutes

## Sleep Score (Option A — asymmetric duration)

Goal: **80+ is attainable**, **90+ is hard**.

**Inputs**
- Duration (asleep)
- Efficiency (asleep / in bed)
- Consistency (wake time vs 7‑day average wake time)

**Duration subscore**
- 7.5–10.5h → 1.0 (no penalty)
- 6.0–7.5h → 0.7 → 1.0 (linear)
- 5.0–6.0h → 0.4 → 0.7 (linear)
- <5.0h → 0.3
- 10.5–12.0h → 1.0 → 0.6 (linear)
- >12.0h → 0.5

**Efficiency subscore**
- ≥95% → 1.0
- 85–95% → 0.75 → 1.0 (linear)
- 70–85% → 0.40 → 0.75 (linear)
- <70% → 0.30

**Consistency subscore (wake time)**
- ≤20 min → 1.0
- 20–60 min → 1.0 → 0.6 (linear)
- 60–120 min → 0.6 → 0.3 (linear)
- >120 min → 0.2

**Score**
```
score = 100 * (0.55*duration + 0.25*efficiency + 0.20*consistency)
```
**90+ gate:** if any subscore < 0.85, cap at 89.

## Data Sources (HealthKit)

- Sleep: `HKCategoryTypeIdentifier.sleepAnalysis`
- Steps: `HKQuantityTypeIdentifier.stepCount`
- Walking distance: `HKQuantityTypeIdentifier.distanceWalkingRunning`
- Active energy: `HKQuantityTypeIdentifier.activeEnergyBurned`

## MVP Checklist

**Must have**
- [ ] Sleep ingestion + score
- [ ] Steps, distance, active energy ingestion
- [ ] Daily recap UI with 7‑day comparisons
- [ ] Morning notification with sleep highlight + deep link

**Nice to have**
- [ ] Activity rings
- [ ] Insight selection refinements
- [ ] Weekly trends view

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.0+
- HealthKit capability enabled
- Apple Developer Account (for device testing)

## Getting Started

1. Open the project in Xcode:
   ```bash
   open "Health Tracker.xcodeproj"
   ```

2. Set your Development Team in **Signing & Capabilities**.

3. Build and run (⌘R).

## HealthKit Setup

Make sure your Info.plist contains:
- `NSHealthShareUsageDescription`
- `NSHealthUpdateUsageDescription`

Permissions can be managed in:
**Settings → Privacy & Security → Health → Health Tracker**

## Project Structure

```
Health Tracker/
├── Health Tracker/              # App source
│   ├── Health_TrackerApp.swift  # App entry point
│   ├── ContentView.swift        # Root view
│   ├── DailyRecapView.swift     # Daily recap UI
│   ├── HealthKitManager.swift   # HealthKit access
│   └── SleepScoreCalculator.swift
├── Health TrackerTests/
└── Health TrackerUITests/
```

## Version History

- **1.0** (June 2025) - Initial release
- **1.1** (In progress) - Daily Recap MVP

## Author

**Rohan Singh**
- Created: June 17, 2025

---

Made with SwiftUI and HealthKit
