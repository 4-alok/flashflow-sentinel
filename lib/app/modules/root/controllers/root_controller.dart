import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

class RootController extends GetxController {
  final tabIndex = 0.obs;
  final isDarkMode = true.obs;

  @override
  void onInit() {
    super.onInit();
    final box = Hive.box('app_meta');
    final savedMode = box.get('theme_mode', defaultValue: 'dark');
    isDarkMode.value = savedMode == 'dark';
    Get.changeThemeMode(isDarkMode.value ? ThemeMode.dark : ThemeMode.light);
  }

  void toggleTheme() {
    isDarkMode.value = !isDarkMode.value;
    final box = Hive.box('app_meta');
    box.put('theme_mode', isDarkMode.value ? 'dark' : 'light');
    Get.changeThemeMode(isDarkMode.value ? ThemeMode.dark : ThemeMode.light);
  }
}
