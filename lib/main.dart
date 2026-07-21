import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'app/core/theme.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'app/data/models/transaction.dart';
import 'app/data/models/dataset_message.dart';
import 'app/data/models/processed_message.dart';
import 'app/data/models/correction_record.dart';
import 'app/modules/dashboard/controllers/chart_zoom_controller.dart';
import 'app/modules/dashboard/controllers/dashboard_controller.dart';
import 'app/modules/data/controllers/data_controller.dart';
import 'app/modules/home/controllers/home_controller.dart';
import 'app/modules/root/controllers/root_controller.dart';
import 'app/modules/root/views/root_view.dart';
import 'app/data/services/correction_service.dart';
import 'app/data/services/export_service.dart';
import 'app/data/services/extraction_queue_service.dart';
import 'app/data/services/generative_extractor_service.dart';
import 'app/data/services/sms_classifier_service.dart';
import 'app/data/services/sms_sync_service.dart';
import 'hive_registrar.g.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive first — services and controllers read the boxes.
  await Hive.initFlutter();
  Hive.registerAdapters();
  await Hive.openBox<Transaction>('transactions');
  await Hive.openBox<DatasetMessage>('dataset_messages');
  await Hive.openBox<ProcessedMessage>('processed_messages');
  await Hive.openBox<CorrectionRecord>('corrections');
  await Hive.openBox('app_meta');

  // Core services
  Get.put(GenerativeExtractorService(), permanent: true);
  Get.put(SmsClassifierService(), permanent: true);
  Get.put(SmsSyncService(), permanent: true);
  Get.put(ExtractionQueueService(), permanent: true);
  Get.put(CorrectionService(), permanent: true);
  Get.put(ExportService(), permanent: true);

  runApp(const FlashFlowApp());
}

class FlashFlowApp extends StatelessWidget {
  const FlashFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    final box = Hive.box('app_meta');
    final isDark = box.get('theme_mode', defaultValue: 'dark') == 'dark';

    return GetMaterialApp(
      title: 'FlashFlow Sentinel',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      initialBinding: BindingsBuilder(() {
        Get.put(RootController());
        Get.put(HomeController());
        Get.lazyPut(() => DashboardController());
        Get.lazyPut(() => ChartZoomController());
        Get.lazyPut(() => DataController());
      }),
      home: const RootView(),
    );
  }
}
