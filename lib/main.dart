import 'package:flutter/material.dart';
import 'dart:ui';
import 'Features/report_screen.dart'; // ✅ FIXED import

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool isDarkMode = true;

  void toggleTheme() {
    setState(() {
      isDarkMode = !isDarkMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF202123),
      ),
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: ScanScreen(
        toggleTheme: toggleTheme,
        isDarkMode: isDarkMode,
      ),
    );
  }
}

class ScanScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  final bool isDarkMode;

  const ScanScreen({
    super.key,
    required this.toggleTheme,
    required this.isDarkMode,
  });

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
              fontWeight:
                  isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? Colors.blue : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: selectedIndex == 2
          ? const ReportScreen()
          : Stack(
              children: [
                /// HOME SCREEN
                if (selectedIndex == 0)
                  Center(
                    child: Text(
                      "Home Screen",
                      style: TextStyle(
                        color:
                            isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),

                /// THEME BUTTON
                if (selectedIndex == 0)
                  Positioned(
                    top: 50,
                    left: 16,
                    child: GestureDetector(
                      onTap: widget.toggleTheme,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.grey.withOpacity(0.2)
                              : Colors.black.withOpacity(0.1),
                          borderRadius:
                              BorderRadius.circular(12),
                        ),
                        child: Icon(
                          widget.isDarkMode
                              ? Icons.light_mode
                              : Icons.dark_mode,
                          size: 28,
                          color: Theme.of(context)
                              .iconTheme
                              .color,
                        ),
                      ),
                    ),
                  ),
              ],
            ),

      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(
            bottom: 20, left: 16, right: 16),
        child: SizedBox(
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                        sigmaX: 20, sigmaY: 20),
                    child: Container(
                      height: 70,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.05)
                            : Colors.black.withOpacity(0.08),
                        borderRadius:
                            BorderRadius.circular(28),
                        border: Border.all(
                          color: isDark
                              ? Colors.white
                                  .withOpacity(0.08)
                              : Colors.black
                                  .withOpacity(0.1),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceAround,
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

              /// CENTER REPORT BUTTON
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
                      style: TextStyle(
                          color: Colors.grey,
                          fontSize: 11),
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