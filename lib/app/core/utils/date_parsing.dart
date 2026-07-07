/// Parses the LLM-extracted `date` (+ optional `time`) fields.
/// When `time` is absent, defaults to the time-of-day component of
/// [smsDate] (the real SMS arrival instant) rather than midnight.
/// Returns null when `date` is absent or unparseable.
DateTime? parseLlmDate(Map<String, dynamic> json, DateTime smsDate) {
  final rawDate = json['date'];
  if (rawDate is! String || rawDate.isEmpty) return null;

  final rawTime = json['time'];
  // The model emits date as ISO 8601 (yyyy-MM-dd), time as HH:mm[:ss].
  if (rawTime is String && rawTime.trim().isNotEmpty) {
    return DateTime.tryParse('${rawDate.trim()} ${rawTime.trim()}');
  }

  final dateOnly = DateTime.tryParse(rawDate.trim());
  if (dateOnly == null) return null;
  return DateTime(dateOnly.year, dateOnly.month, dateOnly.day,
      smsDate.hour, smsDate.minute, smsDate.second);
}

/// LLM date with fallback to the SMS timestamp.
DateTime resolveDate(Map<String, dynamic> json, DateTime smsDate) {
  return parseLlmDate(json, smsDate) ?? smsDate;
}

/// The SMS arrives at (or just after) the transaction time, so an extracted
/// date far away from the SMS timestamp is a hallucination — prefer smsDate.
DateTime guardedDate(DateTime? aiDate, DateTime smsDate) {
  if (aiDate == null) return smsDate;
  final drift = aiDate.difference(smsDate).abs();
  return drift <= const Duration(days: 3) ? aiDate : smsDate;
}
