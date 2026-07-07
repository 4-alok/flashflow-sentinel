# FlashFlow Sentinel — Flutter App Implementation Plan

> **Status (2026-07-02): implemented.** All six phases are in the codebase;
> `flutter analyze` is clean and unit tests pass. Remaining: on-device
> verification per the checklists below.

## Context

The ML side of FlashFlow is done: a TF-IDF + logistic-regression gatekeeper (exported to `assets/models/classifier_model.json`, consumed by `SmsClassifierService`) and a fine-tuned Qwen3-0.6B GGUF (shipped as `assets/models/smollm-q4_k_m.gguf`, run via `llama_flutter_android` in `GenerativeExtractorService`, ~1–2s per message). The Flutter app currently only supports single-message analysis; `startBulkScan()` is stubbed, results live only in memory, and `Transaction.fromGenerative` has a bug (`date: DateTime.now()` at `lib/app/data/models/transaction.dart:69` — SMS timestamp ignored).

Goal: make the app fully functional —
1. **First-run bulk processing** of the last **6 months** of SMS: TF-IDF classifies everything instantly; transactional messages show as "pending"; Qwen extracts details sequentially in the background while the app stays usable (two-phase UX).
2. **Persist all inference results in Hive** so restarts never re-run inference; later opens process only new SMS (date watermark).
3. **Manual overrides with full field editing** (type, amount, vendor, date) plus an **exclude flag** (e.g. self-transfer credits), preserving original AI output.
4. **Correction log** (original vs corrected, reason) exportable as JSONL matching the training format, to improve future datasets — including TF-IDF false positive/negative feedback.
5. **Analytics dashboard**: hourly/daily/weekly/monthly spending via `fl_chart` (already a dependency), respecting overrides/exclusions.

**Note:** This plan should be saved to `/Volumes/SSD/Projects/FlashFlow/flashflow_sentinel/IMPLEMENTATION_PLAN.md` as the first implementation step (user will execute with Sonnet in a follow-up session).

Project root: `/Volumes/SSD/Projects/FlashFlow/flashflow_sentinel`

## Architecture decisions

- **New central Hive model `ProcessedMessage`** (typeId 2, box `processed_messages`), keyed by stable string: `msg.id?.toString() ?? '${msg.date?.millisecondsSinceEpoch}_${msg.body.hashCode}'`. Always `box.put(key, record)`, never `add`.
- **Overrides flattened into `ProcessedMessage`** (mutable nullable fields) + separate **append-only `CorrectionRecord`** (typeId 3, box `corrections`) as the audit/export log.
- **Legacy `Transaction`/`DatasetMessage` boxes superseded, not migrated** — keep typeIds 0/1 registered so old boxes open; stop writing to `transactions`.
- **Analytics reads only effective-value getters** (`effectiveType/Amount/Date/Vendor`, `isIncluded`): user override > LLM parse > SMS metadata.
- Incremental-sync watermark in plain `Box` `app_meta`, key `lastSyncedSmsDateMs` (int).
- LLM queue = sequential Dart async loop in a `GetxService` (llama call is an async platform channel; no isolate needed).
- Verified constraints: `SmsClassifierService.classify()` returns only bool (probability must be exposed); `flutter_sms_inbox` `querySms` has no date filter — omit `count`, filter by date in Dart; `SmsMessage` exposes `id` (int?), `body`, `address`, `date`; `share_plus` not yet a dependency.

---

## Phase 1 — Data layer: models, boxes, classifier probability, date-bug fix

### New `lib/app/data/models/processed_message.dart`

```dart
@HiveType(typeId: 2)
class ProcessedMessage extends HiveObject {
  // Identity / raw SMS (final)
  @HiveField(0) final String key;
  @HiveField(1) final String body;
  @HiveField(2) final String address;
  @HiveField(3) final DateTime smsDate;

  // Classifier (final)
  @HiveField(4) final bool classifiedAsTransaction;
  @HiveField(5) final double classifierProbability;

  // Extraction state (mutable)
  @HiveField(6) String extractionStatus;     // 'pending'|'done'|'failed'|'skipped'
  @HiveField(7) String? rawLlmOutput;
  @HiveField(8) int extractionAttempts;      // default 0

  // Parsed LLM fields (mutable, nullable)
  @HiveField(9)  String? aiType;             // normalized 'credit'|'debit'
  @HiveField(10) double? aiAmount;
  @HiveField(11) DateTime? aiDate;
  @HiveField(12) String? aiVendor;           // counterparty_name
  @HiveField(13) String? aiBank;
  @HiveField(14) String? aiAccount;
  @HiveField(15) double? aiBalance;
  @HiveField(16) String? aiReferenceId;
  @HiveField(17) String? aiCurrency;

  // User override (mutable, null = no override)
  @HiveField(18) String? overrideType;
  @HiveField(19) double? overrideAmount;
  @HiveField(20) String? overrideVendor;
  @HiveField(21) DateTime? overrideDate;
  @HiveField(22) bool excluded;              // default false
  @HiveField(23) String? overrideReason;     // 'self_transfer'|'wrong_amount'|'wrong_type'|'not_a_transaction'|'missed_transaction'|'other'
  @HiveField(24) DateTime? overriddenAt;
  @HiveField(25) bool? userSaysTransaction;  // null = agrees with classifier
}
```

Plain Dart getters (no HiveField):

```dart
bool get isTransaction => userSaysTransaction ?? classifiedAsTransaction;
bool get isIncluded => isTransaction && !excluded && extractionStatus != 'skipped';
String get effectiveType => overrideType ?? aiType ?? 'debit';
double get effectiveAmount => overrideAmount ?? aiAmount ?? 0.0;
DateTime get effectiveDate => overrideDate ?? aiDate ?? smsDate; // trust aiDate only if within ~3 days of smsDate (LLM hallucination guard)
String? get effectiveVendor => overrideVendor ?? aiVendor;
bool get hasOverride => overriddenAt != null;
```

### New `lib/app/data/models/correction_record.dart`

```dart
@HiveType(typeId: 3)
class CorrectionRecord extends HiveObject {
  @HiveField(0) final String messageKey;
  @HiveField(1) final String smsBody;
  @HiveField(2) final String smsAddress;
  @HiveField(3) final DateTime smsDate;
  @HiveField(4) final String? originalAiJson;   // rawLlmOutput at time of correction
  @HiveField(5) final String correctedJson;     // jsonEncode of corrected field map
  @HiveField(6) final String reason;
  @HiveField(7) final DateTime timestamp;
  @HiveField(8) final String kind;              // 'extraction_fix'|'classifier_false_positive'|'classifier_false_negative'|'exclusion'
  @HiveField(9) final double? classifierProbability;
}
```

### Modifications

- **New `lib/app/core/utils/date_parsing.dart`**: `DateTime resolveDate(Map json, DateTime smsDate)` — parses `json['date']` (+ optional `json['time']`) via `DateTime.tryParse`, falls back to `smsDate`. Shared by `Transaction.fromGenerative` and the extraction queue.
- **`lib/app/data/models/transaction.dart`**: `fromGenerative` gains required `DateTime smsDate` param; line 69 uses `resolveDate(json, smsDate)` instead of `DateTime.now()`.
- **`lib/app/data/services/sms_classifier_service.dart`**: extract scoring into `double probability(String text)`; `classify` = `probability(text) >= _threshold`. Gate per-message prints behind a `verbose` flag (bulk scan would spam logcat).
- **`lib/main.dart`**: use generated registrar (`import 'hive_registrar.g.dart'; Hive.registerAdapters();`); open boxes `processed_messages` (`Box<ProcessedMessage>`), `corrections` (`Box<CorrectionRecord>`), `app_meta` (plain).
- **`pubspec.yaml`**: add `share_plus: ^12.0.0` now (used in Phase 6).

### Build & verify

```
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
```
- App boots, all boxes open, no typeId collisions.
- Optional unit tests: `test/date_parsing_test.dart`, `test/effective_values_test.dart` (override precedence).

---

## Phase 2 — Bulk sync + instant TF-IDF classification

### Modify `lib/app/data/services/sms_service.dart`

`Future<List<SmsMessage>> fetchMessages({DateTime? since})` — keep permission logic; call `querySms(kinds: [SmsQueryKind.inbox])` **without `count`**, filter `m.date != null && (since == null || m.date!.isAfter(since))`, sort newest-first.

### New `lib/app/data/services/sms_sync_service.dart`

```dart
class SmsSyncService extends GetxService {
  final isSyncing = false.obs;
  final lastSyncNewCount = 0.obs;
  Future<List<String>> syncInbox(); // returns keys of new pending (transactional) records, newest first
}
```

Logic:
1. `since = watermark(app_meta) ?? now - Duration(days: 180)`.
2. `SmsService.fetchMessages(since: since)`.
3. Per message: compute key; **skip if already in box** (idempotent — the never-rerun guarantee); `p = classifier.probability(body)`; create `ProcessedMessage` with `classifiedAsTransaction: p >= 0.80`, `extractionStatus: isTxn ? 'pending' : 'skipped'`; `box.put(key, record)`.
4. Advance watermark to max SMS date seen (after successful loop only).

Register in `main.dart` (`Get.put(..., permanent: true)`).

### Modify HomeController + HomeView

- `lib/app/modules/home/controllers/home_controller.dart`: replace `smsMessages`/`fetchSms`/`startBulkScan` internals. On init: load box → `final messages = <ProcessedMessage>[].obs` (smsDate desc), then `syncInbox()` and refresh. Subscribe to `box.watch()` to update rows live. `analyzeMessage` now writes into the `ProcessedMessage` record.
- `lib/app/modules/home/views/home_view.dart`: rows render `ProcessedMessage` states — skipped (dimmed "not a transaction"), pending ("Extracting…" chip), done (amount + type + vendor), failed ("Failed" chip; retry wired in Phase 3).

### Verify
- First launch: after SMS permission, last-6-months messages appear in ~1–2s, transactional ones pending.
- Kill + relaunch: 0 new records created (log it); new incoming SMS picked up via watermark.

---

## Phase 3 — Background extraction queue (Qwen, cached forever)

### New `lib/app/data/services/extraction_queue_service.dart`

```dart
class ExtractionQueueService extends GetxService with WidgetsBindingObserver {
  final isRunning = false.obs;
  final isPaused = false.obs;
  final totalQueued = 0.obs;
  final completedCount = 0.obs;
  final currentKey = RxnString();

  void enqueue(List<String> keys);   // dedupe, newest-first
  void enqueueAllPending();          // box scan: 'pending' + retryable 'failed'
  void pause();                      // finish current message, then halt
  void resume();
  Future<void> retry(String key);    // reset attempts, re-enqueue, resume
}
```

Loop (single Future guarded by `isRunning`):
1. Pop key; skip if missing, `done`, `userSaysTransaction == false`, or `extractionAttempts >= 2`.
2. Ensure model loaded (`loadModel()` once at loop start).
3. `await extractor.extractFromSms(record.body)`; increment attempts.
4. Success → populate `ai*` fields (normalize type with existing credit/receive-contains logic; amount num-or-string parse as in `fromGenerative`; `aiDate` via shared `resolveDate`; vendor = `counterparty_name` ?? `counterparty`), `rawLlmOutput`, `extractionStatus = 'done'`. Error → keep `rawLlmOutput` if present; status = `attempts >= 2 ? 'failed' : 'pending'` (goes to back of queue once).
5. `await record.save()`; update Rx counters; `Future.delayed(50ms)` to yield to UI.
6. Lifecycle: `didChangeAppLifecycleState` — pause on `paused`, resume on `resumed`.

### Wiring
- Register in `main.dart`.
- `HomeController`: after `syncInbox()` → `queue.enqueue(keys)`; also `queue.enqueueAllPending()` on startup (records left pending by a previous kill).
- `HomeView`: slim persistent progress bar under AppBar — "Extracting {completed}/{total}", `LinearProgressIndicator`, pause/resume button.
- Repurpose `startBulkScan()` as "re-sync now".

### Verify
- Pending rows fill in one-by-one while scrolling stays smooth; progress counts up; pause/resume works.
- Kill mid-queue, relaunch: only remaining pending re-queued; done records (incl. `rawLlmOutput`) untouched.
- Force a failure (unload model) → `failed` after 2 attempts; retry works.

---

## Phase 4 — Manual overrides + correction log

### New `lib/app/data/services/correction_service.dart`

```dart
class CorrectionService extends GetxService {
  Future<void> applyFieldOverride({required ProcessedMessage record,
    String? type, double? amount, String? vendor, DateTime? date,
    bool? excluded, required String reason});
    // sets override fields + overriddenAt, saves, appends CorrectionRecord
    // (kind: excluded==true ? 'exclusion' : 'extraction_fix')
  Future<void> markNotATransaction(ProcessedMessage record);
    // userSaysTransaction=false, status='skipped' (keep ai*), kind 'classifier_false_positive'
  Future<void> markAsTransaction(ProcessedMessage record, ExtractionQueueService queue);
    // userSaysTransaction=true, status='pending', attempts=0, kind 'classifier_false_negative', enqueue + resume
  Future<void> clearOverride(ProcessedMessage record); // null overrides; keep log entries
}
```

`correctedJson` = `jsonEncode({'transaction_type', 'amount', 'counterparty_name', 'date' (ISO), 'excluded'})` from effective values after the edit — this feeds export.

### New `lib/app/modules/home/views/widgets/edit_transaction_sheet.dart`

Modal bottom sheet: type segmented control, amount TextField (numeric), vendor TextField, date picker (initial `effectiveDate`), "Exclude from analytics" switch, reason dropdown (self_transfer / wrong_amount / wrong_type / other), Save/Cancel. Original AI values shown as hints under overridden fields. Only changed fields passed to `applyFieldOverride`.

### Wiring
- `HomeController`: `openEditor`, `toggleExcluded`, `markNotTransaction`, `markMissedTransaction`.
- `HomeView`: row long-press / trailing menu — Edit / Exclude / "Not a transaction" (done rows) / "This IS a transaction" (skipped rows). Pencil badge on overridden rows; excluded rows dimmed + strikethrough amount.
- Register service in `main.dart`.

### Verify
- Edit amount → new value shown, `aiAmount` preserved, one `CorrectionRecord` appended with both JSONs.
- Skipped → mark as transaction → extracted. Done → not-a-transaction → leaves analytics; kind `classifier_false_positive`.
- Overrides persist across restart.

---

## Phase 5 — Analytics dashboard + navigation shell

### New `lib/app/data/services/analytics_service.dart`

Pure functions over records where `isIncluded && extractionStatus == 'done'`:

```dart
enum Period { hourly, daily, weekly, monthly }
List<ProcessedMessage> included(Box<ProcessedMessage> box);
({double credit, double debit}) totals(List<ProcessedMessage> txns, DateTimeRange range);
Map<DateTime, double> spendingBuckets(txns, Period period, DateTimeRange range);
  // hourly: 24 buckets over selected day; daily: last 30 days; weekly: last 12 ISO weeks; monthly: last 12 months; debit only
List<MapEntry<String, double>> topVendors(txns, range, {int limit = 5});
```
All math on `effectiveDate` / `effectiveAmount` / `effectiveType`.

### New module `lib/app/modules/dashboard/`
- `controllers/dashboard_controller.dart`: `period` Rx, `buckets`/`creditTotal`/`debitTotal`/`topVendors` Rx; `_recompute()` on init, period change, and `box.watch()` events (debounce ~300ms — queue writes frequently).
- `views/dashboard_view.dart`: `SegmentedButton<Period>`; summary cards (spent / received / net) with `NumberFormat.currency(locale: 'en_IN', symbol: '₹')`; fl_chart `BarChart` for hourly/daily/weekly, `LineChart` for monthly trend; top-vendors list; empty state.

### Navigation
- New `lib/app/modules/root/views/root_view.dart` + `controllers/root_controller.dart`: `Scaffold` with `IndexedStack` [HomeView, DashboardView, DataView(Phase-6 placeholder)] + 3-destination `NavigationBar`.
- `main.dart`: `home: RootView()`; `Get.lazyPut(DashboardController)`, put `RootController`.

### Verify
- Totals match hand-computed sums; edits/exclusions on Messages tab update dashboard live; period switching works; no crash on empty box.

---

## Phase 6 — Export (correction dataset + classifier feedback)

### New `lib/app/data/services/export_service.dart`

```dart
Future<File> buildExtractionCorrectionsJsonl();
// per extraction_fix/exclusion record:
// {"instruction": <extractionSystemPrompt>, "input": "SMS: <body>", "output": <correctedJson>}
Future<File> buildClassifierFeedbackJsonl();
// per false_positive/false_negative record:
// {"text": <body>, "label": 0|1, "source": "user_correction", "probability": <p>}
Future<void> shareAll(); // temp dir + SharePlus.instance.share(ShareParams(files: [XFile...]))
```

Hoist the `const systemPrompt` local in `lib/app/data/services/generative_extractor_service.dart` to `static const String extractionSystemPrompt` (referenced by both `extractFromSms` and export) so exported JSONL matches the training format in `data/v2/` exactly.

### New `lib/app/modules/data/views/data_view.dart` (third tab)
Correction counts by kind; extraction stats (done/pending/failed/skipped); "Export corrections (JSONL)" → `shareAll()`; "Re-run failed extractions" → `queue.enqueueAllPending()`.

### Verify
- Export after 2–3 corrections: valid JSONL, `instruction` matches training prompt, `output` reflects corrections; classifier file has label 1 for missed, 0 for false positives; share sheet opens.

---

## Cross-cutting notes

- **TypeIds**: 0 `Transaction`, 1 `DatasetMessage` (keep); 2 `ProcessedMessage`, 3 `CorrectionRecord`. Never renumber HiveFields once shipped.
- Re-run `dart run build_runner build --delete-conflicting-outputs` after every model change; the generated `lib/hive_registrar.g.dart` picks up new adapters.
- **Never-rerun-inference guarantee** = (a) sync skips existing keys, (b) queue skips `done`, (c) fields + `rawLlmOutput` saved via `record.save()` immediately after each extraction.
- GGUF asset stays `assets/models/smollm-q4_k_m.gguf` (it is actually the Qwen3-0.6B export renamed — do not rename anything model-related).
- All Hive writes stay on the main isolate.

## Verification (end-to-end)

1. Fresh install on Android device → grant SMS permission → last 6 months classified within seconds, extraction progress bar counts up while app remains usable.
2. Restart mid-extraction → no re-inference of completed messages; queue resumes remainder.
3. Edit a transaction's amount, exclude a self-transfer credit, mark one skipped SMS as a transaction → all reflected on rows, in the corrections box, and live on the dashboard.
4. Dashboard: switch hourly/daily/weekly/monthly; totals respect exclusions/overrides; dates come from SMS timestamps not "now".
5. Export from Data tab → both JSONL files valid and format-compatible with `data/v2/train.jsonl`.
