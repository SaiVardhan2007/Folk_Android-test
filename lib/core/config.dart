import 'package:flutter/material.dart' show ThemeMode;

/// Address of the FOLK API (Cloudflare Worker). Change only if the Worker is moved.
const String kApiBaseUrl = 'https://folk-api.jayadeva-jydd.workers.dev';

const int kMinPasswordLength = 8;

/// The app always uses the light (ivory) theme, whatever the phone's dark-mode setting. Change to ThemeMode.system to follow the phone.
const ThemeMode kThemeMode = ThemeMode.light;

/// While the Attendance screen is open, the shared list of who is present refreshes this often (several volunteers mark at the same door).
/// Everything else refreshes on open, on return to the app, on pull-down and after the user's own actions.
const Duration kLiveListRefresh = Duration(seconds: 60);
