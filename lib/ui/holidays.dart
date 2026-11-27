import 'package:flutter/widgets.dart';
import 'package:flutter_chan/ui/colors.dart';

/// What falls down the screen on a holiday.
enum HolidayFallShape { snow, leaf, confetti, heart, clover, petal }

/// A day (or a few) when the app dresses up: it wears [theme]'s colors, and
/// [fall] drifts down the screen, each if it's on in Settings.
enum Holiday {
  newYear(ThemeColor.newYear, HolidayFallShape.confetti, [
    Color(0xFFFCD34D),
    Color(0xFFF0ABFC),
    Color(0xFF67E8F9),
    Color(0xFFFFFFFF),
  ]),
  valentines(ThemeColor.valentines, HolidayFallShape.heart, [
    Color(0xFFF472B6),
    Color(0xFFFB7185),
    Color(0xFFF9A8D4),
  ]),
  stPatricks(ThemeColor.stPatricks, HolidayFallShape.clover, [
    Color(0xFF4ADE80),
    Color(0xFF22C55E),
    Color(0xFF86EFAC),
  ]),
  easter(ThemeColor.easter, HolidayFallShape.petal, [
    Color(0xFFC4B5FD),
    Color(0xFFFDE68A),
    Color(0xFFF9A8D4),
    Color(0xFFA7F3D0),
  ]),
  halloween(ThemeColor.halloween, HolidayFallShape.leaf, [
    Color(0xFFFF9F43),
    Color(0xFFEA580C),
    Color(0xFFB45309),
    Color(0xFFC084FC),
  ]),
  christmas(
    ThemeColor.christmas,
    HolidayFallShape.snow,
    // Snow is white in the dark and pale blue on a light page; see colorsFor.
    [Color(0xFFFFFFFF)],
  );

  const Holiday(this.theme, this.fall, this._colors);

  final ThemeColor theme;
  final HolidayFallShape fall;

  final List<Color> _colors;

  String get title => theme.title;

  /// What [fall] is painted in: snow can't be white on a light page.
  List<Color> colorsFor(Brightness brightness) =>
      this == Holiday.christmas && brightness == Brightness.light
      ? const [Color(0xFFB9CCE4), Color(0xFFCAD8EA)]
      : _colors;

  /// The days each is on, last day included, in [year].
  (DateTime, DateTime) daysIn(int year) => switch (this) {
    // Both ends of a year: from New Year's Eve, and New Year's Day.
    Holiday.newYear => (DateTime(year, 12, 31), DateTime(year + 1, 1, 1)),
    Holiday.valentines => (DateTime(year, 2, 13), DateTime(year, 2, 14)),
    Holiday.stPatricks => (DateTime(year, 3, 17), DateTime(year, 3, 17)),
    // Good Friday to Easter Monday.
    Holiday.easter => (
      easterSunday(year).subtract(const Duration(days: 2)),
      easterSunday(year).add(const Duration(days: 1)),
    ),
    Holiday.halloween => (DateTime(year, 10, 24), DateTime(year, 10, 31)),
    Holiday.christmas => (DateTime(year, 12, 1), DateTime(year, 12, 26)),
  };

  /// The holiday on [when]'s day, if there is one.
  static Holiday? on(DateTime when) {
    final DateTime day = DateTime(when.year, when.month, when.day);
    for (final Holiday holiday in Holiday.values) {
      // New Year's Day belongs to the year before's.
      for (final int year in [day.year - 1, day.year]) {
        final (DateTime first, DateTime last) = holiday.daysIn(year);
        if (!day.isBefore(first) && !day.isAfter(last)) {
          return holiday;
        }
      }
    }
    return null;
  }

  /// The last day of the holiday on [when]'s day.
  DateTime lastDay(DateTime when) {
    final DateTime day = DateTime(when.year, when.month, when.day);
    final (DateTime thisYearsFirst, DateTime thisYears) = daysIn(day.year);
    return day.isBefore(thisYearsFirst) ? daysIn(day.year - 1).$2 : thisYears;
  }

  /// Easter Sunday in the Gregorian calendar (the anonymous algorithm, as
  /// Western churches count it).
  static DateTime easterSunday(int year) {
    final int a = year % 19;
    final int b = year ~/ 100;
    final int c = year % 100;
    final int d = b ~/ 4;
    final int e = b % 4;
    final int f = (b + 8) ~/ 25;
    final int g = (b - f + 1) ~/ 3;
    final int h = (19 * a + b - d - g + 15) % 30;
    final int i = c ~/ 4;
    final int k = c % 4;
    final int l = (32 + 2 * e + 2 * i - h - k) % 7;
    final int m = (a + 11 * h + 22 * l) ~/ 451;
    final int n = h + l - 7 * m + 114;
    return DateTime(year, n ~/ 31, n % 31 + 1);
  }

  /// What the time is, for which holiday it is; tests set their own.
  static DateTime Function() clock = DateTime.now;
}

/// Which holiday the app dresses up for, chosen in Settings: whichever it
/// is by the date, or one all year round (Christmas in July).
enum HolidayChoice {
  byDate,
  newYear,
  valentines,
  stPatricks,
  easter,
  halloween,
  christmas;

  /// The holiday chosen; none when it goes [byDate].
  Holiday? get fixed => this == byDate ? null : Holiday.values.byName(name);

  /// The holiday the app dresses up for on [when].
  Holiday? on(DateTime when) => fixed ?? Holiday.on(when);

  String get title => fixed?.title ?? 'By date';
}
