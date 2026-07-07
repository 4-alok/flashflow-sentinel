import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../dashboard/views/dashboard_view.dart';
import '../../data/views/data_view.dart';
import '../../home/views/home_view.dart';
import '../controllers/root_controller.dart';

class RootView extends GetView<RootController> {
  const RootView({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() => Scaffold(
          body: IndexedStack(
            index: controller.tabIndex.value,
            children: const [
              DashboardView(),
              HomeView(),
              DataView(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: controller.tabIndex.value,
            onDestinationSelected: (i) => controller.tabIndex.value = i,
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart),
                  label: 'Dashboard'),
              NavigationDestination(
                  icon: Icon(Icons.sms_outlined),
                  selectedIcon: Icon(Icons.sms),
                  label: 'Messages'),
              NavigationDestination(
                  icon: Icon(Icons.dataset_outlined),
                  selectedIcon: Icon(Icons.dataset),
                  label: 'Data'),
            ],
          ),
        ));
  }
}
