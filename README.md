# SafeBuddy Flutter App

SafeBuddy is a mobile application designed to enhance personal safety by providing real-time information about crime hotspots and traffic accident zones. The app notifies users of danger zones and includes a demo mode for simulating location changes.

## Features

- **Map Integration**: Displays a map with crime hotspots and traffic accident zones.
- **Danger Zone Notifications**: Alerts users when they enter a danger zone.
- **Demo Mode**: Allows users to manually move their location on the map for testing purposes.
- **User-Friendly Interface**: Intuitive design for easy navigation and access to features.

## Project Structure

The project is organized into the following directories:

- **lib/**: Contains the main application code.
  - **models/**: Data models for risk information, location, and danger zones.
  - **services/**: Classes for API interactions, location management, and notifications.
  - **screens/**: UI screens for home, map, and settings.
  - **widgets/**: Reusable UI components.
  - **utils/**: Utility functions and constants.

- **assets/**: Contains image assets used in the app.

- **test/**: Contains widget tests to ensure UI functionality.

## Setup Instructions

1. **Clone the Repository**:
   ```
   git clone <repository-url>
   cd safebuddy
   ```

2. **Install Dependencies**:
   Ensure you have Flutter installed, then run:
   ```
   flutter pub get
   ```

3. **Run the App**:
   Use the following command to run the app on an emulator or connected device:
   ```
   flutter run
   ```

## Usage

- Launch the app to view the home screen.
- Navigate to the map screen to see crime hotspots and traffic accident zones.
- Enable notifications to receive alerts when entering danger zones.
- Use the demo mode to simulate location changes.

## Contributing

Contributions are welcome! Please submit a pull request or open an issue for any suggestions or improvements.

## License

This project is licensed under the MIT License. See the LICENSE file for details.