import 'package:flutter/material.dart';
import 'dart:ui';
import 'Report_Screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF202123),
      ),
      home: const ScanScreen(),
    );
  }
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  int selectedIndex = 0;

  Widget navItem(IconData icon, String label, int index) {
    final isActive = selectedIndex == index;

    return GestureDetector(
      onTap: () => setState(() => selectedIndex = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 35, color: isActive ? Colors.blue : Colors.grey),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: isActive ? Colors.blue : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: selectedIndex == 2
          ? const ReportScreen()
          : const Center(
              child: Text("Home Screen", style: TextStyle(color: Colors.white)),
            ),

      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(bottom: 20, left: 16, right: 16),
        child: SizedBox(
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // 🔽 NAV BAR
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      height: 70,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          navItem(Icons.home, "Home", 0),
                          navItem(Icons.article, "Ledger", 1),

                          const SizedBox(width: 55),

                          navItem(Icons.manage_search, "Pro", 3),
                          navItem(Icons.public, "News", 4),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 🔴 REPORT BUTTON
              Positioned(
                bottom: 0,
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() => selectedIndex = 2);
                      },
                      child: Container(
                        height: 66,
                        width: 66,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.warning_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Report",
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
