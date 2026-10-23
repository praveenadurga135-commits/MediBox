MediBox 💊

MediBox is a Flutter-based medicine management application that helps users organize their medicines, track daily doses, and maintain a history of medication intake.

Features
Medicine Management: Add, edit, search, and delete medicines.
Dosage Tracking: Record medicine type, dosage, frequency, and food instructions.
Reminder Scheduling: Set a preferred reminder time for each medicine.
Daily Dashboard: View active medicines, completed doses, and pending doses.
Dose History: Review scheduled doses and mark medicines as taken.
Data Storage: Store medicine and dose records using SQLite.
Built With
Flutter
Dart
Material Design 3
SQLite (sqflite)
sqflite_common_ffi_web for web database support
Getting Started
Prerequisites
Flutter SDK
Dart SDK (included with Flutter)
Google Chrome for web testing
Android SDK and an emulator or Android device for Android testing

Android Studio is optional if the required Android SDK and tools are installed separately.

Installation

Clone the repository:

git clone https://github.com/YOUR_USERNAME/Medibox.git
cd Medibox


Install dependencies:

flutter pub get

Run on Chrome
flutter run -d chrome

Run on Android

Make sure an Android device or emulator is available, then run:

flutter devices
flutter run

Build for the Web
flutter build web


The generated web files will be available in build/web.

Data Storage

Android and web use separate local database storage. Medicine records saved in one platform do not automatically synchronize with the other.

Project Status

This project is under development. Test database initialization, medicine storage, dose tracking, and platform compatibility before using it as a production application.

Disclaimer

MediBox is a medication-tracking tool and does not replace professional medical advice.
