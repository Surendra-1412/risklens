import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'Features/ledger_screen.dart';
import 'Features/scanner_screen.dart';
import 'Features/home_screen.dart';
import 'Features/menu.dart';
import 'Features/news_screen.dart';
import 'Features/pro_screen.dart';
import 'Features/settings_screen.dart';
import 'translation_service.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
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
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return ValueListenableBuilder<String>(
          valueListenable: currentLanguage,
          builder: (context, lang, child) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              builder: (context, child) {
                return MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.0)),
                  child: child!,
                );
              },
              theme: ThemeData.light().copyWith(
                scaffoldBackgroundColor: const Color(0xFFFFFBFE),
                canvasColor: const Color(0xFFFFFBFE),
              ),
              darkTheme: ThemeData.dark().copyWith(
                scaffoldBackgroundColor: const Color(0xFF121212),
                canvasColor: const Color(0xFF121212),
              ),
              themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
              home: ScanScreen(
                toggleTheme: toggleTheme,
                isDarkMode: isDarkMode,
              ),
            );
          },
        );
      },
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
  String? trackingAddress;

  Widget navItem(IconData icon, String label, int index) {
    final isActive = selectedIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          if (index == 1) {
            trackingAddress = null; // Clear auto-scan address on manual tab click
          }
          selectedIndex = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.blue.withOpacity(0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Icon(
              icon,
              size: 32.w,
              color: isActive ? Colors.blue : Colors.grey,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            label,
            style: TextStyle(
              fontSize: 17.sp,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? Colors.blue : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget reportItem() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ScannerScreen()),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 70.h,
            width: 70.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              image: const DecorationImage(
                image: AssetImage('icon.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final screens = [
      HomeScreen(
        toggleTheme: widget.toggleTheme,
        isDarkMode: widget.isDarkMode,
        onTrackRequested: (addr) {
          setState(() {
            trackingAddress = addr;
            selectedIndex = 1;
          });
        },
      ),
      LedgerScreen(
        key: ValueKey(trackingAddress), // Force rebuild when address changes
        toggleTheme: widget.toggleTheme,
        isDarkMode: widget.isDarkMode,
        initialAddress: trackingAddress,
      ),
      const SizedBox.shrink(), // Placeholder for center button (Scanner)
      const SimulationScreen(),
      const NewsScreen(),
    ];

    return Scaffold(
      appBar: null,
      extendBodyBehindAppBar: true,
      extendBody: true,
      body: screens[selectedIndex],
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(bottom: 10.h, left: 3.w, right: 3.w),
        child: SizedBox(
          height: 75
              .h, // Changed from MediaQuery logic back to fixed responsive height for consistency
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20.r),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.grey.withOpacity(0.2)
                      : Colors.grey.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(28.r),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.black.withOpacity(0.15),
                    width: 1.w,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    navItem(Icons.home, t("home"), 0),
                    navItem(Icons.visibility, t("track"), 1),
                    reportItem(), // ✅ now inside row
                    navItem(Icons.view_in_ar, "Simu", 3),
                    navItem(Icons.public, t("news"), 4),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
