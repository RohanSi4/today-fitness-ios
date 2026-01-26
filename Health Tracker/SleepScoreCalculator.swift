import Foundation

struct SleepScoreResult {
    let score: Int
    let durationSubscore: Double
    let efficiencySubscore: Double
    let consistencySubscore: Double
}

struct SleepScoreCalculator {
    static func score(
        duration: TimeInterval,
        inBed: TimeInterval,
        wakeTimeMinutes: Double,
        avgWakeTimeMinutes: Double?
    ) -> SleepScoreResult {
        let hours = duration / 3600
        let efficiency = inBed > 0 ? duration / inBed : 0

        let durationSubscore = durationScore(hours: hours)
        let efficiencySubscore = efficiencyScore(efficiency)
        let consistencySubscore = consistencyScore(
            wakeTimeMinutes: wakeTimeMinutes,
            avgWakeTimeMinutes: avgWakeTimeMinutes
        )

        let rawScore = 100 * (0.55 * durationSubscore + 0.25 * efficiencySubscore + 0.20 * consistencySubscore)
        var finalScore = Int(rawScore.rounded())

        if durationSubscore < 0.85 || efficiencySubscore < 0.85 || consistencySubscore < 0.85 {
            finalScore = min(finalScore, 89)
        }

        return SleepScoreResult(
            score: finalScore,
            durationSubscore: durationSubscore,
            efficiencySubscore: efficiencySubscore,
            consistencySubscore: consistencySubscore
        )
    }

    private static func durationScore(hours: Double) -> Double {
        if hours >= 7.5 && hours <= 10.5 {
            return 1.0
        }
        if hours >= 6.0 && hours < 7.5 {
            return lerp(value: hours, from: 6.0, to: 7.5, outMin: 0.7, outMax: 1.0)
        }
        if hours >= 5.0 && hours < 6.0 {
            return lerp(value: hours, from: 5.0, to: 6.0, outMin: 0.4, outMax: 0.7)
        }
        if hours < 5.0 {
            return 0.3
        }
        if hours > 10.5 && hours <= 12.0 {
            return lerp(value: hours, from: 10.5, to: 12.0, outMin: 1.0, outMax: 0.6)
        }
        return 0.5
    }

    private static func efficiencyScore(_ efficiency: Double) -> Double {
        if efficiency >= 0.95 {
            return 1.0
        }
        if efficiency >= 0.85 {
            return lerp(value: efficiency, from: 0.85, to: 0.95, outMin: 0.75, outMax: 1.0)
        }
        if efficiency >= 0.70 {
            return lerp(value: efficiency, from: 0.70, to: 0.85, outMin: 0.40, outMax: 0.75)
        }
        return 0.30
    }

    private static func consistencyScore(wakeTimeMinutes: Double, avgWakeTimeMinutes: Double?) -> Double {
        guard let avgWakeTimeMinutes else {
            return 1.0
        }

        let diff = abs(wakeTimeMinutes - avgWakeTimeMinutes)
        if diff <= 20 {
            return 1.0
        }
        if diff <= 60 {
            return lerp(value: diff, from: 20, to: 60, outMin: 1.0, outMax: 0.6)
        }
        if diff <= 120 {
            return lerp(value: diff, from: 60, to: 120, outMin: 0.6, outMax: 0.3)
        }
        return 0.2
    }

    private static func lerp(value: Double, from: Double, to: Double, outMin: Double, outMax: Double) -> Double {
        guard to != from else { return outMax }
        let t = (value - from) / (to - from)
        return outMin + t * (outMax - outMin)
    }
}
