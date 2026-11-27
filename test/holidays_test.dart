import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/ui/holiday_fall.dart';
import 'package:flutter_chan/ui/holidays.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Easter falls on its Sunday', () {
    expect(Holiday.easterSunday(2024), DateTime(2024, 3, 31));
    expect(Holiday.easterSunday(2025), DateTime(2025, 4, 20));
    expect(Holiday.easterSunday(2026), DateTime(2026, 4, 5));
    expect(Holiday.easterSunday(2027), DateTime(2027, 3, 28));
    expect(Holiday.easterSunday(2038), DateTime(2038, 4, 25));
  });

  test('each holiday is on its days, and only those', () {
    final Map<DateTime, Holiday?> days = {
      DateTime(2026, 11, 27): null,
      DateTime(2026, 11, 30, 23, 59): null,
      DateTime(2026, 12, 1): Holiday.christmas,
      DateTime(2026, 12, 26, 23): Holiday.christmas,
      DateTime(2026, 12, 27): null,
      DateTime(2026, 12, 31): Holiday.newYear,
      DateTime(2027, 1, 1, 12): Holiday.newYear,
      DateTime(2027, 1, 2): null,
      DateTime(2027, 2, 12): null,
      DateTime(2027, 2, 13): Holiday.valentines,
      DateTime(2027, 2, 14): Holiday.valentines,
      DateTime(2027, 3, 17): Holiday.stPatricks,
      // Good Friday to Easter Monday.
      DateTime(2027, 3, 25): null,
      DateTime(2027, 3, 26): Holiday.easter,
      DateTime(2027, 3, 29): Holiday.easter,
      DateTime(2027, 3, 30): null,
      DateTime(2026, 10, 23): null,
      DateTime(2026, 10, 24): Holiday.halloween,
      DateTime(2026, 10, 31, 23, 59): Holiday.halloween,
      DateTime(2026, 11, 1): null,
    };
    days.forEach((DateTime day, Holiday? holiday) {
      expect(Holiday.on(day), holiday, reason: '$day');
    });
  });

  test('knows when it ends', () {
    expect(
      Holiday.christmas.lastDay(DateTime(2026, 12, 3)),
      DateTime(2026, 12, 26),
    );
    // New Year's Day ends the one that started the year before.
    expect(Holiday.newYear.lastDay(DateTime(2027, 1, 1)), DateTime(2027, 1, 1));
    expect(
      Holiday.newYear.lastDay(DateTime(2026, 12, 31)),
      DateTime(2027, 1, 1),
    );
  });

  test('a holiday can be kept all year, or go by the date', () {
    // Every holiday can be chosen, and each choice is one.
    expect([for (final c in HolidayChoice.values) ?c.fixed], Holiday.values);
    final DateTime july = DateTime(2027, 7, 4);
    expect(HolidayChoice.byDate.on(july), isNull);
    expect(HolidayChoice.christmas.on(july), Holiday.christmas);
    // Kept, it stays the same on another holiday.
    expect(
      HolidayChoice.christmas.on(DateTime(2026, 10, 31)),
      Holiday.christmas,
    );
    expect(HolidayChoice.byDate.on(DateTime(2026, 10, 31)), Holiday.halloween);
  });

  for (final Holiday holiday in Holiday.values) {
    testWidgets('${holiday.name} falls, light and dark', (tester) async {
      for (final Brightness brightness in Brightness.values) {
        await tester.pumpWidget(
          CupertinoTheme(
            data: CupertinoThemeData(brightness: brightness),
            child: HolidayFall(holiday: holiday),
          ),
        );
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 30));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('stands still with reduced motion', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: HolidayFall(holiday: Holiday.christmas),
      ),
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
