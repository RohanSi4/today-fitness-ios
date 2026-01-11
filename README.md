# Health Tracker

A modern iOS application built with SwiftUI for tracking and monitoring health metrics using Apple's HealthKit framework.

## Overview

Health Tracker is a native iOS app designed to help users monitor their health data by integrating with Apple's HealthKit. The app provides an intuitive interface to view and track various health metrics synced from the Health app.

## Features

- 🔐 **HealthKit Integration** - Secure access to health data through Apple's HealthKit framework
- 📱 **Native iOS Experience** - Built with SwiftUI for a modern, responsive user interface
- 🎨 **Clean Design** - Minimalist and user-friendly interface
- ✅ **Well-Tested** - Includes unit and UI test suites

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.0+
- HealthKit capability enabled
- Apple Developer Account (for running on physical devices)

## Getting Started

### Prerequisites

1. Install [Xcode](https://developer.apple.com/xcode/) from the App Store
2. Ensure you have an Apple Developer Account configured in Xcode

### Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd "Health Tracker"
   ```

2. Open the project in Xcode:
   ```bash
   open "Health Tracker.xcodeproj"
   ```

3. Select your development team in the project settings:
   - Select the project in the navigator
   - Go to "Signing & Capabilities"
   - Choose your team from the dropdown

4. Build and run the project (⌘R)

### HealthKit Setup

The app requires HealthKit permissions to access health data. When you first run the app, iOS will prompt you to grant access to specific health data types. You can manage these permissions in:

**Settings → Privacy & Security → Health → Health Tracker**

## Project Structure

```
Health Tracker/
├── Health Tracker/              # Main app source code
│   ├── Health_TrackerApp.swift  # App entry point
│   ├── ContentView.swift        # Main view
│   ├── Assets.xcassets/         # App icons and assets
│   └── Health Tracker.entitlements  # HealthKit entitlements
├── Health TrackerTests/         # Unit tests
└── Health TrackerUITests/       # UI tests
```

## Technologies

- **SwiftUI** - Modern declarative UI framework
- **HealthKit** - Apple's health data framework
- **Swift 5.0** - Programming language
- **Testing Framework** - Swift's native testing framework

## Development

### Building for Different Platforms

- **Simulator**: Select any iOS simulator from the device menu
- **Physical Device**: Requires valid provisioning profile and code signing

### Running Tests

- **Unit Tests**: ⌘U or Product → Test
- **UI Tests**: Included in the test suite

## Version History

- **1.0** (June 2025) - Initial release

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is available for use.

## Author

**Rohan Singh**
- Created: June 17, 2025

## Future Enhancements

Potential features for future releases:
- 📊 Detailed health metrics visualization
- 📈 Trend analysis and insights
- 🎯 Goal setting and tracking
- 🔔 Health reminders and notifications
- 📝 Workout logging
- 👥 Sharing capabilities
- 🌙 Sleep tracking
- 💧 Hydration tracking

## Support

For issues, questions, or suggestions, please open an issue on the repository.

---

Made with ❤️ using SwiftUI and HealthKit

