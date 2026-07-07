import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';

class SmsService {
  final SmsQuery _query = SmsQuery();

  /// Fetches inbox messages, newest first, optionally only those after [since].
  /// flutter_sms_inbox has no native date filter, so we fetch all and filter here.
  Future<List<SmsMessage>> fetchMessages({DateTime? since}) async {
    // 1. Request Permission
    var status = await Permission.sms.status;
    if (status.isDenied) {
      status = await Permission.sms.request();
    }

    if (!status.isGranted) {
      throw Exception('SMS Permission denied');
    }

    // 2. Query Messages (Inbox only)
    final messages = await _query.querySms(kinds: [SmsQueryKind.inbox]);

    final filtered = messages
        .where((m) =>
            m.date != null && (since == null || m.date!.isAfter(since)))
        .toList()
      ..sort((a, b) => b.date!.compareTo(a.date!));
    return filtered;
  }
}
