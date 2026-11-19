import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api.dart';
import 'layout.dart';
import 'theme.dart';

/// The update notice the admin sets in Admin → Settings → App update.
class AppUpdate {
  const AppUpdate({this.latestBuild = 0, this.minBuild = 0, this.url = '', this.message = ''});
  final int latestBuild, minBuild;
  final String url, message;

  factory AppUpdate.fromJson(Map<String, dynamic>? j) => AppUpdate(
    latestBuild: (j?['latest_build'] as num?)?.toInt() ?? 0,
    minBuild: (j?['min_build'] as num?)?.toInt() ?? 0,
    url: j?['url'] as String? ?? '',
    message: j?['message'] as String? ?? '',
  );

  /// This phone is older than the minimum: it must update before using the app.
  bool mustUpdate(int build) => minBuild > 0 && build < minBuild;
  bool canUpdate(int build) => latestBuild > 0 && build < latestBuild;
}

/// The build number of the installed app (the number after "+" in pubspec's version).
final installedBuildProvider = FutureProvider<int>((ref) async => int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0);

/// Asks the server for the update notice. Offline or on any error: no notice (never blocks the app by mistake).
final appUpdateProvider = FutureProvider<AppUpdate>((ref) async {
  try {
    return AppUpdate.fromJson(Map<String, dynamic>.from((await ref.read(apiProvider).get('/app/update'))['update'] as Map));
  } catch (_) {
    return const AppUpdate();
  }
});

/// Wraps the whole app. Optional update: a pop-up (once per launch, can be dismissed).
/// Required update (phone older than the minimum build): a full-screen block with only an Update button.
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.navigatorKey, required this.child});
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> with WidgetsBindingObserver {
  int? _askedFor; // latest build already offered in this launch

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.invalidate(appUpdateProvider); // refreshed when the app returns, not on a timer
  }

  Future<void> _offer(AppUpdate u) async {
    if (_askedFor == u.latestBuild) return;
    _askedFor = u.latestBuild;
    final ctx = widget.navigatorKey.currentContext;
    if (ctx == null) return;
    final go = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Update available'),
        content: Text(u.message.isEmpty ? 'A new version of FOLK Tracker is ready.' : u.message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Later')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 48)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    if (go == true) await _install(u.url);
  }

  /// Downloads the new version inside the app (with a progress bar) and opens Android's installer. Android always asks the
  /// user to tap Install once; an app cannot install itself silently. A failed download is reported here with "Try again":
  /// the app never sends the user to a browser or a file-sharing site.
  Future<void> _install(String url) async {
    final ctx = widget.navigatorKey.currentContext;
    if (ctx == null) return;
    final progress = ValueNotifier<int?>(null);
    var dialogOpen = true;
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Downloading update'),
          content: ValueListenableBuilder<int?>(
            valueListenable: progress,
            builder: (context, p, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: p == null ? null : p / 100, minHeight: 8),
                const SizedBox(height: kGapM),
                Text(p == null ? 'Starting...' : '$p%  •  When it finishes, tap Install.'),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() => dialogOpen = false);
    var failed = false;
    try {
      await for (final e in OtaUpdate().execute(url, destinationFilename: 'FOLK-Tracker.apk')) {
        if (e.status == OtaStatus.DOWNLOADING) {
          progress.value = int.tryParse(e.value ?? '');
        } else if (e.status == OtaStatus.INSTALLING || e.status == OtaStatus.INSTALLATION_DONE || e.status == OtaStatus.CANCELED) {
          break;
        } else {
          failed = true;
          break;
        }
      }
    } catch (_) {
      failed = true;
    }
    if (dialogOpen && ctx.mounted) Navigator.of(ctx, rootNavigator: true).pop();
    progress.dispose();
    if (!failed || !ctx.mounted) return;
    final retry = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Update could not download'),
        content: const Text('Please check your internet connection and try again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Close')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 48)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
    if (retry == true) await _install(url);
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return widget.child; // the website is always the latest version; APK updates are for the Android app
    final build = ref.watch(installedBuildProvider).value;
    final u = ref.watch(appUpdateProvider).value;
    if (build == null || u == null || u.url.isEmpty) return widget.child;
    if (u.mustUpdate(build)) return _RequiredUpdate(message: u.message, onUpdate: () => _install(u.url));
    if (u.canUpdate(build)) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _offer(u) : null);
    return widget.child;
  }
}

class _RequiredUpdate extends StatelessWidget {
  const _RequiredUpdate({required this.message, required this.onUpdate});
  final String message;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(kGapXL),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.system_update, size: 64, color: context.colors.brand),
                    const SizedBox(height: kGapM),
                    Text('Update required', style: text.titleLarge, textAlign: TextAlign.center),
                    const SizedBox(height: kGapS),
                    Text(
                      message.isEmpty ? 'This version of FOLK Tracker is no longer supported. Please update to continue.' : message,
                      style: text.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: kGapL),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(onPressed: onUpdate, icon: const Icon(Icons.download), label: const Text('Update now')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
