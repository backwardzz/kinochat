import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'config.dart';
import 'models.dart';
import 'screens/home_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/backend.dart';
import 'services/local_backend.dart';
import 'services/prefs.dart';
import 'services/search.dart';
import 'services/supabase_backend.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await Prefs.load();

  Backend backend;
  if (hasServer) {
    try {
      backend = await SupabaseBackend.connect();
    } catch (_) {
      backend = LocalBackend(prefs);
    }
  } else {
    backend = LocalBackend(prefs);
  }

  runApp(
    KinoChatApp(
      services: Services(
        prefs: prefs,
        backend: backend,
        search: SearchService(prefs),
      ),
    ),
  );
}

/// App-wide objects, handed down the tree by [ServicesScope].
class Services {
  Services({required this.prefs, required this.backend, required this.search});

  final Prefs prefs;
  final Backend backend;
  final SearchService search;

  /// `?as=Имя` in the address opens the site as a separate guest. Handy for
  /// trying a room from two tabs of one browser.
  late final String? _guestName = kIsWeb
      ? Uri.base.queryParameters['as']?.trim()
      : null;

  bool get hasName =>
      (_guestName?.isNotEmpty ?? false) ||
      (prefs.userName?.isNotEmpty ?? false);

  UserProfile get profile {
    final guest = _guestName;
    if (guest != null && guest.isNotEmpty) {
      return UserProfile(id: 'guest-$guest', name: guest);
    }
    return prefs.profile;
  }

  /// Address people open to get the web version.
  String get inviteBase {
    if (!kIsWeb) return webAppUrl;
    final u = Uri.base;
    return Uri(
      scheme: u.scheme,
      host: u.host,
      port: u.hasPort ? u.port : null,
      path: u.path,
    ).toString();
  }

  String inviteLink(Room room) => '$inviteBase?room=${room.code}';
}

class ServicesScope extends InheritedWidget {
  const ServicesScope({
    super.key,
    required this.services,
    required super.child,
  });

  final Services services;

  static Services of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ServicesScope>()!.services;

  @override
  bool updateShouldNotify(ServicesScope oldWidget) => false;
}

/// Room code from an invite link: `…/?room=ABC123` (or `…/#/r/ABC123`).
String? inviteCodeFromUrl() {
  if (!kIsWeb) return null;
  final u = Uri.base;
  final m = RegExp(r'/r/([A-Za-z0-9]{6})').firstMatch(u.fragment);
  final code = u.queryParameters['room'] ?? m?.group(1);
  if (code == null || !RegExp(r'^[A-Za-z0-9]{6}$').hasMatch(code)) return null;
  return code.toUpperCase();
}

class KinoChatApp extends StatefulWidget {
  const KinoChatApp({super.key, required this.services});

  final Services services;

  @override
  State<KinoChatApp> createState() => _KinoChatAppState();
}

class _KinoChatAppState extends State<KinoChatApp> {
  late bool _hasName = widget.services.hasName;

  /// Read once at start: a newcomer first passes the name screen, and the
  /// address may have changed by the time they are through.
  final String? _inviteCode = inviteCodeFromUrl();

  @override
  Widget build(BuildContext context) {
    return ServicesScope(
      services: widget.services,
      child: MaterialApp(
        title: appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: _hasName
            ? HomeScreen(initialCode: _inviteCode)
            : WelcomeScreen(onDone: () => setState(() => _hasName = true)),
      ),
    );
  }
}
