import Foundation
import Testing
@testable import Health_Tracker

/// The weight field is the control that gets touched most in a session, and its
/// behaviour while typing is invisible to both screenshots and the UI suite.
struct StepperTextTests {
    private let weight = 0...1

    @Test func anUnsetWeightRendersEmptySoThePlaceholderShows() {
        #expect(StepperText.display(0, fractionDigits: weight) == "")
    }

    @Test func realWeightsRenderWithoutTrailingZeros() {
        #expect(StepperText.display(235, fractionDigits: weight) == "235")
        #expect(StepperText.display(12.5, fractionDigits: weight) == "12.5")
        #expect(StepperText.display(17.5, fractionDigits: weight) == "17.5")
    }

    @Test func clearingTheFieldIsARealZeroRatherThanARefusal() {
        #expect(StepperText.parse("") == 0)
        #expect(StepperText.parse("   ") == 0)
    }

    // The whole reason for the local buffer: mid-typing "12." has to parse to
    // the same value the field already holds, or the resync guard fires and
    // deletes the decimal point on the keystroke after it.
    @Test func aHalfTypedDecimalParsesToTheValueAlreadyHeld() {
        #expect(StepperText.parse("12.") == 12)
        #expect(StepperText.parse("12.") == StepperText.parse("12"))
    }

    @Test func typingTwelvePointFiveNeverLosesTheSeparator() {
        // Replays the keystrokes and applies the same guard the view applies.
        var value: Double = 0
        var text = ""
        for character in "12.5" {
            text.append(character)
            if let parsed = StepperText.parse(text), parsed != value { value = parsed }
            // The view only rewrites the buffer when value moved independently.
            if StepperText.parse(text) != value {
                text = StepperText.display(value, fractionDigits: weight)
            }
        }
        #expect(text == "12.5")
        #expect(value == 12.5)
    }

    @Test func aStepperTapRewritesTheFieldBecauseTheChangeCameFromOutside() {
        let text = "12.5"
        let updated: Double = 17.5
        #expect(StepperText.parse(text) != updated)
        #expect(StepperText.display(updated, fractionDigits: weight) == "17.5")
    }

    @Test func decimalsTypedOnACommaKeyboardStillParse() {
        #expect(StepperText.parse("12,5") == 12.5)
    }

    @Test func partialGarbageLeavesTheValueAlone() {
        #expect(StepperText.parse("1.2.3") == nil)
        #expect(StepperText.parse("-") == nil)
    }
}
