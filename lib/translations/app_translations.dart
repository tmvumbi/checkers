import 'package:get/get.dart';

import 'locales/en_us.dart';
import 'locales/fr_fr.dart';

class AppTranslations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {'en_US': enUs, 'fr_FR': frFr};
}
