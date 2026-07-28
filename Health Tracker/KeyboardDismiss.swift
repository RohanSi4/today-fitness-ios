import UIKit

/// Resigns whatever is currently first responder.
///
/// The weight and rep fields sit several views deep behind bindings, so a
/// `@FocusState` on the screen that owns the Save or Finish button cannot reach
/// them, and both keypads are numeric with no return key to submit. This is the
/// only way to make a formatted `TextField` commit its parsed value before that
/// value is read.
@MainActor
func dismissKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
}
