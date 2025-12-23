# 💬 Talka

<div align="center">
  <img src="assets/icon.png" alt="Talka Logo" width="120" height="120">
  
  **A modern, feature-rich chat and calling application built with Flutter**
  
  [![Flutter](https://img.shields.io/badge/Flutter-3.9.2+-02569B?logo=flutter)](https://flutter.dev)
  [![Dart](https://img.shields.io/badge/Dart-3.9.2+-0175C2?logo=dart)](https://dart.dev)
  [![Supabase](https://img.shields.io/badge/Supabase-Backend-3ECF8E?logo=supabase)](https://supabase.com)
  [![Firebase](https://img.shields.io/badge/Firebase-Notifications-FFCA28?logo=firebase)](https://firebase.google.com)
</div>

---

## ✨ Features

- 💬 **Real-time Messaging** - Instant chat with friends and groups
- 📞 **Voice & Video Calls** - High-quality WebRTC-based calling
- 🔔 **Push Notifications** - Stay connected with FCM notifications
- 📸 **Media Sharing** - Share images and files seamlessly
- 🎨 **Modern UI** - Beautiful Material Design with dark mode support
- 🔐 **Secure Authentication** - Powered by Supabase Auth
- 📱 **Cross-Platform** - Works on Android, iOS, Web, macOS, Linux, and Windows
- ⚡ **High Performance** - Optimized for smooth 90/120Hz displays
- 🎭 **Stories** - Share moments that disappear after 24 hours
- 👤 **User Profiles** - Customizable profiles with avatars

---

## 📸 Screenshots

<div align="center">
  <i>Screenshots coming soon...</i>
</div>

---

## 🚀 Getting Started

### Prerequisites

Before you begin, ensure you have the following installed:

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.9.2 or higher)
- [Dart SDK](https://dart.dev/get-dart) (3.9.2 or higher)
- [Android Studio](https://developer.android.com/studio) or [Xcode](https://developer.apple.com/xcode/) (for mobile development)
- A [Supabase](https://supabase.com) account
- A [Firebase](https://firebase.google.com) project (for push notifications)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/talka-flutter.git
   cd talka-flutter
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Set up environment variables**
   
   Copy the example environment file and fill in your credentials:
   ```bash
   cp .env.example .env
   ```
   
   Edit `.env` and add your Supabase credentials:
   ```env
   SUPABASE_URL=https://your-project-id.supabase.co
   SUPABASE_ANON_KEY=your-anon-key-here
   ```

4. **Set up Supabase Database**
   
   Run the SQL schema in your Supabase project:
   ```bash
   # Go to your Supabase project dashboard
   # Navigate to SQL Editor
   # Run the contents of supabase_schema.sql
   ```

5. **Configure Firebase (Optional - for push notifications)**
   
   - Create a Firebase project at [Firebase Console](https://console.firebase.google.com)
   - Add Android/iOS apps to your Firebase project
   - Download configuration files:
     - `google-services.json` → Place in `android/app/`
     - `GoogleService-Info.plist` → Place in `ios/Runner/`
   
   > **Note:** Firebase configuration files are gitignored for security. You'll need to generate your own.

6. **Run the app**
   ```bash
   # For mobile
   flutter run
   
   # For web
   flutter run -d chrome
   
   # For desktop
   flutter run -d macos    # macOS
   flutter run -d windows  # Windows
   flutter run -d linux    # Linux
   ```

---

## 🔧 Configuration

### Supabase Setup

1. **Create a Supabase project** at [supabase.com](https://supabase.com)
2. **Get your credentials** from Project Settings → API
3. **Run the database schema** from `supabase_schema.sql`
4. **Configure authentication** providers (Email, OAuth, etc.)
5. **Set up storage buckets** for media files

### Firebase Setup (Push Notifications)

1. **Create a Firebase project** at [console.firebase.google.com](https://console.firebase.google.com)
2. **Add your apps** (Android/iOS) to the Firebase project
3. **Download configuration files** and place them in the correct directories
4. **Enable Cloud Messaging** in Firebase Console
5. **Configure FCM in Supabase** (optional) for server-side notifications

---

## 📁 Project Structure

```
talka-flutter/
├── lib/
│   ├── main.dart                 # App entry point
│   ├── theme.dart               # App theming
│   └── src/
│       ├── auth/                # Authentication screens & logic
│       ├── call/                # Voice/Video calling functionality
│       ├── chat/                # Chat screens & messaging
│       ├── notify/              # Push notification handling
│       ├── profile/             # User profiles
│       ├── settings/            # App settings
│       ├── storage/             # File storage utilities
│       ├── story/               # Stories feature
│       ├── ui/                  # Shared UI components
│       └── providers.dart       # Riverpod providers
├── assets/                      # Images, fonts, icons
├── android/                     # Android platform files
├── ios/                         # iOS platform files
├── web/                         # Web platform files
├── macos/                       # macOS platform files
├── linux/                       # Linux platform files
├── windows/                     # Windows platform files
├── .env.example                 # Environment variables template
├── supabase_schema.sql          # Database schema
└── pubspec.yaml                 # Dependencies
```

---

## 🛠️ Built With

- **[Flutter](https://flutter.dev)** - UI framework
- **[Dart](https://dart.dev)** - Programming language
- **[Supabase](https://supabase.com)** - Backend & database
- **[Firebase](https://firebase.google.com)** - Push notifications
- **[flutter_riverpod](https://pub.dev/packages/flutter_riverpod)** - State management
- **[flutter_webrtc](https://pub.dev/packages/flutter_webrtc)** - WebRTC for calls
- **[google_fonts](https://pub.dev/packages/google_fonts)** - Typography
- **[cached_network_image](https://pub.dev/packages/cached_network_image)** - Image caching
- **[image_picker](https://pub.dev/packages/image_picker)** - Media selection
- **[flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications)** - Local notifications

---

## 🎯 Key Features Explained

### Real-time Messaging
Messages are synced in real-time using Supabase Realtime subscriptions. All messages are stored securely in PostgreSQL with Row Level Security (RLS) policies.

### Voice & Video Calls
Built on WebRTC technology with signaling through Supabase. Supports:
- One-on-one voice calls
- One-on-one video calls
- Call notifications with accept/decline actions
- In-call controls (mute, speaker, camera toggle)

### Push Notifications
Firebase Cloud Messaging (FCM) delivers notifications for:
- New messages
- Incoming calls
- Call status updates

### State Management
Uses Riverpod for:
- Clean separation of concerns
- Testable business logic
- Efficient rebuilds
- Dependency injection

---

## 🔐 Security

- **Environment Variables**: All secrets are stored in `.env` (gitignored)
- **Firebase Config**: Configuration files are excluded from version control
- **Row Level Security**: Supabase RLS policies protect user data
- **Authentication**: Secure auth flows with Supabase Auth
- **HTTPS**: All API calls use secure connections

### Important Security Notes

⚠️ **Never commit these files:**
- `.env` - Contains your API keys
- `android/app/google-services.json` - Firebase Android config
- `ios/Runner/GoogleService-Info.plist` - Firebase iOS config

These files are already added to `.gitignore` for your protection.

---

## 🧪 Testing

Run tests with:
```bash
flutter test
```

Run specific test files:
```bash
flutter test test/widget_test.dart
```

---

## 📱 Platform-Specific Setup

### Android
- Minimum SDK: 21
- Target SDK: 34
- Permissions configured in `AndroidManifest.xml`

### iOS
- Deployment target: iOS 12.0+
- Permissions configured in `Info.plist`

### Web
- Progressive Web App (PWA) ready
- Service worker for offline support

### Desktop (macOS/Windows/Linux)
- Native desktop support
- Platform-specific UI adaptations

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the project
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 👨‍💻 Author

**Your Name**

- GitHub: [@yourusername](https://github.com/yourusername)
- Email: your.email@example.com

---

## 🙏 Acknowledgments

- Flutter team for the amazing framework
- Supabase for the powerful backend
- Firebase for reliable push notifications
- All open-source contributors

---

## 📞 Support

If you have any questions or need help, please:

- Open an [issue](https://github.com/yourusername/talka-flutter/issues)
- Check the [documentation](https://github.com/yourusername/talka-flutter/wiki)
- Join our community discussions

---

<div align="center">
  Made with ❤️ using Flutter
  
  ⭐ Star this repo if you like it!
</div>
