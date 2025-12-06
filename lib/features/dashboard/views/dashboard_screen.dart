import 'package:flutter/material.dart';
import '../widgets/sidebar.dart';
import '../widgets/content_area.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Basic responsive check
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: const Color(0xFF1B2535),
      // On mobile, show an AppBar to open the drawer
      appBar: isDesktop
          ? null
          : AppBar(
              backgroundColor: const Color(0xFF161E2D),
              title: const Text('Dashboard'),
              iconTheme: const IconThemeData(color: Colors.white),
              titleTextStyle: const TextStyle(
                color: Colors.white,
                fontSize: 18,
              ),
            ),
      drawer: isDesktop ? null : const Sidebar(),
      body: Row(
        children: [
          // On Desktop, show Sidebar permanently
          if (isDesktop) const Sidebar(),

          // Main Content Area
          const Expanded(child: ContentArea()),
        ],
      ),
    );
  }
}
