import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'app_localizations.dart';
import 'app_localizations_en.dart';

export 'app_localizations.dart';

final AppLocalizations _english = AppLocalizationsEn();

/// The English strings, for defaults outside a widget tree.
AppLocalizations get englishL10n => _english;

extension AppLocalizationsContext on BuildContext {
  /// The strings for the device language.
  ///
  /// Falls back to English where no [AppLocalizations] is in scope, such as
  /// a widget pumped on its own in a test.
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ?? _english;
}

/// Numbers and dates written the way the app language writes them.
extension AppFormats on AppLocalizations {
  /// The app's localization delegates load the date symbols for every
  /// supported language. Without them, as in a widget test, only US English
  /// is built in.
  DateFormat _date(DateFormat Function(String locale) format) {
    try {
      return format(localeName);
    } on Object {
      return format('en_US');
    }
  }

  /// [value] with exactly [digits] decimals, such as 12.5 or 12,5.
  String decimal(num value, {int digits = 1}) =>
      NumberFormat.decimalPatternDigits(
        locale: localeName,
        decimalDigits: digits,
      ).format(value);

  /// [value] with up to three decimals and no trailing zeros, such as 1.5
  /// or 1,5.
  String compactDecimal(num value) =>
      NumberFormat.decimalPattern(localeName).format(value);

  /// [meters] as a depth, such as "18.4 m" or "18,4 m".
  String depthValue(double meters, {int digits = 1}) =>
      metersValue(decimal(meters, digits: digits));

  /// [celsius] as a water temperature, such as "26 °C".
  String temperatureValue(double celsius, {int digits = 0}) =>
      celsiusValue(decimal(celsius, digits: digits));

  /// A date such as "Oct 11, 2026" or "11.10.2026".
  String mediumDate(DateTime date) => _date(DateFormat.yMMMd).format(date);

  /// A date without the year, such as "Oct 11" or "11. Okt.".
  String monthDay(DateTime date) => _date(DateFormat.MMMd).format(date);

  /// A 24-hour time of day, such as "09:41".
  String time24(DateTime date) => _date(DateFormat.Hm).format(date);
}
