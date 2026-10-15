import 'package:dartvex/dartvex.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bindings/initial_binding.dart';
import 'firebase_options.dart';
import 'core/config/convex_config.dart';
import 'core/config/supabase_config.dart';
import 'core/constants/app_strings.dart';
import 'core/locale_preference.dart';
import 'services/convex/convex_gateway.dart';
import 'services/convex/convex_session.dart';
import 'routes/app_pages.dart';
import 'routes/app_routes.dart';
import 'themes/app_theme.dart';
import 'translations/app_translations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Analytics/push degrade gracefully when Firebase can't start
    // (e.g. emulators without Play services).
  }
  final savedLocale = await LocalePreference.load();
  await _initLegacySupabaseForHandoff();

  final gateway = DartvexGateway(ConvexClient(ConvexConfig.url));
  final session = ConvexSession(gateway: gateway);
  Get.put<ConvexGateway>(gateway, permanent: true);
  Get.put<ConvexSession>(session, permanent: true);
  if (Firebase.apps.isNotEmpty) {
    await session.start();
  }
  runApp(CheckersApp(locale: savedLocale));
}

/// Players upgrading from the Supabase-era app still have that session on
/// the device; it is only used once, to claim their old account
/// (LegacyAccountHandoff). Skipped after the handoff completed.
Future<void> _initLegacySupabaseForHandoff() async {
  try {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool('legacy_supabase_claim_done') ?? false) {
      return;
    }
    await Supabase.initialize(
      url: SupabaseConfig.url,
      // The self-hosted stack issues legacy JWT keys.
      // ignore: deprecated_member_use
      anonKey: SupabaseConfig.anonKey,
    );
  } catch (_) {
    // No legacy session to hand off; the app runs on Convex regardless.
  }
}

class CheckersApp extends StatelessWidget {
  const CheckersApp({
    this.initialBinding,
    this.initialRoute = AppRoutes.landing,
    this.locale,
    super.key,
  });

  final Bindings? initialBinding;
  final String initialRoute;
  final Locale? locale;

  static const SystemUiOverlayStyle _systemUiOverlayStyle =
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _systemUiOverlayStyle,
      child: GetMaterialApp(
        title: AppStrings.appName,
        debugShowCheckedModeBanner: false,
        initialBinding: initialBinding ?? InitialBinding(),
        initialRoute: initialRoute,
        getPages: AppPages.pages,
        translations: AppTranslations(),
        locale: locale ?? const Locale('en', 'US'),
        fallbackLocale: const Locale('en', 'US'),
        theme: AppTheme.light,
        themeMode: ThemeMode.light,
      ),
    );
  }
}
