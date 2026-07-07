import 'package:flutter_test/flutter_test.dart';
import 'package:flashflow_sentinel/app/core/utils/date_parsing.dart';

void main() {
  final smsDate = DateTime(2026, 6, 15, 14, 30);

  group('parseLlmDate', () {
    test('falls back to the SMS time-of-day when time is absent', () {
      expect(parseLlmDate({'date': '2026-06-15'}, smsDate),
          DateTime(2026, 6, 15, 14, 30));
    });

    test('combines date and time fields', () {
      expect(parseLlmDate({'date': '2026-06-15', 'time': '14:05'}, smsDate),
          DateTime(2026, 6, 15, 14, 5));
    });

    test('returns null for absent or junk values', () {
      expect(parseLlmDate({}, smsDate), isNull);
      expect(parseLlmDate({'date': null}, smsDate), isNull);
      expect(parseLlmDate({'date': 'not-a-date'}, smsDate), isNull);
      expect(parseLlmDate({'date': ''}, smsDate), isNull);
    });
  });

  group('resolveDate', () {
    test('falls back to smsDate when unparseable', () {
      expect(resolveDate({'date': 'garbage'}, smsDate), smsDate);
      expect(resolveDate({}, smsDate), smsDate);
    });

    test('prefers the LLM date when valid, using SMS time-of-day if time is absent', () {
      expect(resolveDate({'date': '2026-06-14'}, smsDate),
          DateTime(2026, 6, 14, 14, 30));
    });
  });

  group('guardedDate', () {
    test('accepts an AI date close to the SMS date', () {
      final ai = smsDate.subtract(const Duration(days: 1));
      expect(guardedDate(ai, smsDate), ai);
    });

    test('rejects a hallucinated far-away date', () {
      final ai = smsDate.subtract(const Duration(days: 30));
      expect(guardedDate(ai, smsDate), smsDate);
    });

    test('handles null', () {
      expect(guardedDate(null, smsDate), smsDate);
    });
  });
}
