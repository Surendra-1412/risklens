# RiskLens Complete Source Code

This document contains the full source code for all screens in the RiskLens application.

## 1. Main Application & Navigation (lib/main.dart)

```dart
import 'package:flutter/material.dart';
import 'dart:ui';

import 'Features/ledger_screen.dart';
import 'Features/scanner_screen.dart';

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
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFFFFBFE),
        canvasColor: const Color(0xFFFFFBFE),
      ),
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        canvasColor: const Color(0xFF121212),
      ),
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: ScanScreen(toggleTheme: toggleTheme, isDarkMode: isDarkMode),
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
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.blue.withOpacity(0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              size: 36,
              color: isActive ? Colors.blue : Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 17,
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
            height: 70,
            width: 70,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              image: DecorationImage(
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
      Center(
        child: Text(
          "Home Screen",
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
        ),
      ),
      const LedgerScreen(),
      const SizedBox.shrink(), // Scanner is now opened via Navigator.push
      const Center(child: Text("Pro Screen")),
      const Center(child: Text("News Screen")),
    ];

    return Scaffold(
      appBar: selectedIndex == 0
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: Icon(
                  widget.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                  color: isDark ? Colors.white : Colors.black,
                ),
                onPressed: widget.toggleTheme,
              ),
            )
          : null,
      extendBodyBehindAppBar: true,
      extendBody: true,
      body: screens[selectedIndex],
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(bottom: 20, left: 16, right: 16),
        child: SizedBox(
          height: 90,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(38),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.grey.withOpacity(0.2)
                      : Colors.grey.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.black.withOpacity(0.15),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    navItem(Icons.home, "Home", 0),
                    navItem(Icons.visibility, "Track", 1),
                    reportItem(), // ✅ now inside row
                    navItem(Icons.workspace_premium, "Pro", 3),
                    navItem(Icons.public, "News", 4),
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
```

## 2. Omni-Chain QR Scanner (lib/Features/scanner_screen.dart)

```dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'ledger_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isNavigating = false;
  bool _isInvalid = false;
  Timer? _resetTimer;
  TorchState _torchState = TorchState.off;

  @override
  void dispose() {
    _resetTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  bool _isValidAddress(String address) {
    final cleanAddr = address.trim();
    if (cleanAddr.isEmpty) return false;

    // Ethereum / EVM
    if (cleanAddr.startsWith("0x") && cleanAddr.length == 42) {
      return true;
    }

    // Bitcoin
    if (cleanAddr.startsWith("1") ||
        cleanAddr.startsWith("3") ||
        cleanAddr.startsWith("bc1")) {
      if (cleanAddr.length >= 26 && cleanAddr.length <= 62) {
        return true;
      }
    }

    // Solana
    if (cleanAddr.length >= 32 && cleanAddr.length <= 44) {
      final base58Regex = RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$');
      if (base58Regex.hasMatch(cleanAddr)) {
        return true;
      }
    }

    return false;
  }

  void _onDetect(String code) {
    if (_isNavigating || _isInvalid) return;

    if (_isValidAddress(code)) {
      setState(() => _isNavigating = true);
      _controller.stop();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => LedgerScreen(initialAddress: code),
        ),
      );
    } else {
      setState(() => _isInvalid = true);
      _resetTimer?.cancel();
      _resetTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() => _isInvalid = false);
        }
      });
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      final barcodes = await _controller.analyzeImage(image.path);
      if (barcodes != null && barcodes.barcodes.isNotEmpty) {
        final code = barcodes.barcodes.first.displayValue;
        if (code != null) {
          _onDetect(code);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.displayValue != null) {
                  _onDetect(barcode.displayValue!);
                }
              }
            },
          ),
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.7),
              BlendMode.srcOut,
            ),
            child: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    backgroundBlendMode: BlendMode.dstOut,
                  ),
                ),
                Center(
                  child: Container(
                    height: 250,
                    width: 250,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Center(
            child: SizedBox(
              height: 250,
              width: 250,
              child: CustomPaint(
                painter: _ScannerCornerPainter(
                  color: _isNavigating
                      ? Colors.blue
                      : (_isInvalid ? Colors.red : Colors.white),
                ),
              ),
            ),
          ),
          if (_isInvalid)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.45,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Text(
                    "Invalid QR",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _circularButton(
                  icon: Icons.arrow_back,
                  onTap: () => Navigator.pop(context),
                ),
                Column(
                  children: [
                    _circularButton(
                      icon: _torchState == TorchState.on ? Icons.flashlight_off : Icons.flashlight_on,
                      onTap: () async {
                        await _controller.toggleTorch();
                        if (mounted) {
                          setState(() {
                            _torchState = _torchState == TorchState.on ? TorchState.off : TorchState.on;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    _circularButton(icon: Icons.photo_library, onTap: _pickImage),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Column(
              children: [
                const Text(
                  "Scan any crypto QR codes",
                  style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _circularButton({required IconData icon, required VoidCallback onTap, double size = 48, double iconSize = 24}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: size,
        width: size,
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: iconSize),
      ),
    );
  }
}

class _ScannerCornerPainter extends CustomPainter {
  final Color color;
  _ScannerCornerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLength = 30.0;
    const radius = 24.0;

    final topLeftPath = Path()..moveTo(0, cornerLength)..lineTo(0, radius)..arcToPoint(const Offset(radius, 0), radius: const Radius.circular(radius))..lineTo(cornerLength, 0);
    canvas.drawPath(topLeftPath, paint);

    final topRightPath = Path()..moveTo(size.width - cornerLength, 0)..lineTo(size.width - radius, 0)..arcToPoint(Offset(size.width, radius), radius: const Radius.circular(radius))..lineTo(size.width, cornerLength);
    canvas.drawPath(topRightPath, paint);

    final bottomLeftPath = Path()..moveTo(0, size.height - cornerLength)..lineTo(0, size.height - radius)..arcToPoint(Offset(radius, size.height), radius: const Radius.circular(radius), clockwise: false)..lineTo(cornerLength, size.height);
    canvas.drawPath(bottomLeftPath, paint);

    final bottomRightPath = Path()..moveTo(size.width, size.height - cornerLength)..lineTo(size.width, size.height - radius)..arcToPoint(Offset(size.width - radius, size.height), radius: const Radius.circular(radius))..lineTo(size.width - cornerLength, size.height);
    canvas.drawPath(bottomRightPath, paint);
  }

  @override
  bool shouldRepaint(covariant _ScannerCornerPainter oldDelegate) => oldDelegate.color != color;
}
```

## 3. Portfolio & Ledger Dashboard (lib/Features/ledger_screen.dart)

```dart
import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';

class LedgerScreen extends StatefulWidget {
  final String? initialAddress;
  const LedgerScreen({super.key, this.initialAddress});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late TabController _tabController;

  bool _isFocused = false;
  bool _isLoading = false;
  bool _hasError = false;
  bool _showResults = false;
  bool _showPriceInfo = false;

  String _balance = "0.00";
  String _chain = "Ethereum";
  double _currentPrice = 0.0;
  String _errorMessage = "Invalid address or failed to fetch data";
  String _selectedTimeFilter = "1D";

  List<FlSpot> _chartData = [];
  List<Map<String, dynamic>> _allTransactions = [];
  Map<String, List<Map<String, dynamic>>> _historyData = {};
  String _historySearchQuery = "";
  DateTime? _historyFilterDate;
  String _historyFilterType = "All";
  String _historyFilterDirection = "All";

  final String moralisApiKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJub25jZSI6ImYyMTE4N2MxLTE4NzAtNDU0MC1hYzIwLTc3NTc4NDRhYjFjNCIsIm9yZ0lkIjoiNTEzODg4IiwidXNlcklkIjoiNTI4ODExIiwidHlwZUlkIjoiOTQ2YTI0ZGMtODdkNC00YzNiLTlmN2UtNTQzZjA3MDc2OTAyIiwidHlwZSI6IlBST0pFQ1QiLCJpYXQiOjE3Nzc3Mzg0NzMsImV4cCI6NDkzMzQ5ODQ3M30.MRhG1_u1iLfLPI77pteOnlpyQgvNyaDTzt2hm1hwOZA";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _focusNode.addListener(() => setState(() => _isFocused = _focusNode.hasFocus));
    if (widget.initialAddress != null) {
      _controller.text = widget.initialAddress!;
      WidgetsBinding.instance.addPostFrameCallback((_) => fetchWalletData());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  String _detectChain(String address) {
    final len = address.length;
    if (address.startsWith("0x") && len == 42) return "Ethereum";
    if (address.startsWith("bc1")) return "Bitcoin";
    if (len == 44 && !address.startsWith("0x")) return "Solana";
    if (address.startsWith("1") && len >= 26 && len <= 34) return "Bitcoin";
    if (address.startsWith("3") && len >= 26 && len <= 35) return "Bitcoin";
    return "Solana";
  }

  Future<double> _fetchPrice(String coinId) async {
    try {
      final res = await http.get(Uri.parse("https://api.coingecko.com/api/v3/simple/price?ids=$coinId&vs_currencies=usd"));
      if (res.statusCode == 200) return (jsonDecode(res.body)[coinId]['usd'] as num).toDouble();
    } catch (_) {}
    return 0.0;
  }

  Future<void> fetchWalletData() async {
    final address = _controller.text.trim();
    if (address.isEmpty) return;
    _focusNode.unfocus();
    final detectedChain = _detectChain(address);
    setState(() { _isLoading = true; _hasError = false; _showResults = false; _chain = detectedChain; });
    try {
      await _fetchBalance(address, detectedChain);
      await _fetchTransactions(address, detectedChain);
      _currentPrice = await _fetchPrice(detectedChain.toLowerCase());
      setState(() { _showResults = true; _isLoading = false; });
    } catch (e) {
      setState(() { _hasError = true; _isLoading = false; });
    }
  }

  // --- UI Components ---
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFFFFBFE),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              _buildGlassSearchBar(),
              const SizedBox(height: 32),
              Expanded(child: _buildMainContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterButton(String defaultText, String? selectedText, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool isSelected = selectedText != null;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.withOpacity(0.2) : (isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? Colors.blue : (isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 18),
              Expanded(child: Text(isSelected ? selectedText : defaultText, style: GoogleFonts.quicksand(color: isSelected ? Colors.blue : (isDark ? Colors.grey : Colors.grey.shade700), fontSize: 15, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down, size: 14, color: isSelected ? Colors.blue : (isDark ? Colors.grey : Colors.grey.shade700)),
            ],
          ),
        ),
      ),
    );
  }
  
  // (Full transaction logic, graph rendering, and balance fetching methods are included in the source file)
}
```
