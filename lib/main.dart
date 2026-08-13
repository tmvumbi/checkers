import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bindings/initial_binding.dart';
import 'core/config/supabase_config.dart';
import 'core/constants/app_strings.dart';
import 'routes/app_pages.dart';
import 'routes/app_routes.dart';
import 'themes/app_theme.dart';
import 'translations/app_translations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    // The self-hosted stack issues legacy JWT keys; publishableKey does not
    // apply there yet.
    // ignore: deprecated_member_use
    anonKey: SupabaseConfig.anonKey,
  );
  runApp(const CheckersApp());
}

class CheckersApp extends StatelessWidget {
  const CheckersApp({
    this.initialBinding,
    this.initialRoute = AppRoutes.landing,
    super.key,
  });

  final Bindings? initialBinding;
  final String initialRoute;

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
        locale: const Locale('en', 'US'),
        fallbackLocale: const Locale('en', 'US'),
        theme: AppTheme.light,
        themeMode: ThemeMode.light,
      ),
    );
  }
}
