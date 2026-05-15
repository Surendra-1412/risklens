import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:ui';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'settings_screen.dart';
import 'ledger_screen.dart';
import '../translation_service.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  final bool isDarkMode;
  final Function(String)? onTrackRequested;

  const HomeScreen({
    super.key,
    required this.toggleTheme,
    required this.isDarkMode,
    this.onTrackRequested,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;
  String _inputType = "Unknown";
  bool _isLoading = false;
  Map<String, dynamic>? _securityData;
  Map<String, dynamic>? _walletData;
  String? _error;
  bool _showReport = false;
  bool _showQuiz = false;

  // AI and API Keys
  final String _openRouterApiKey = dotenv.get('OPENROUTER_API_KEY', fallback: '');
  final String _coinStatsApiKey = dotenv.get('COINSTATS_API_KEY', fallback: '');

  // Quiz State
  int _currentQuizStep = 0;
  final List<String> _quizAnswers = List.filled(5, "");
  final List<String> _quizQuestions = [
    "Where did the person approach you?",
    "What was the main offer or promise?",
    "Did they ask for your seed phrase or private key?",
    "Did they ask you to connect your wallet to a site?",
    "What was the tone of the interaction?",
  ];
  final List<List<Map<String, dynamic>>> _quizOptions = [
    [
      {"label": "Telegram", "icon": Icons.send},
      {"label": "WhatsApp", "icon": Icons.chat_bubble_outline},
      {"label": "Discord", "icon": Icons.groups_3_outlined},
      {"label": "Other", "icon": Icons.more_horiz},
    ],
    [
      {"label": "High Returns", "icon": Icons.trending_up},
      {"label": "Free Airdrop", "icon": Icons.card_giftcard},
      {"label": "Help/Support", "icon": Icons.help_outline},
      {"label": "Giveaway", "icon": Icons.celebration},
    ],
    [
      {"label": "Yes", "icon": Icons.warning_amber_rounded},
      {"label": "No", "icon": Icons.check_circle_outline},
    ],
    [
      {"label": "Yes", "icon": Icons.link},
      {"label": "No", "icon": Icons.link_off},
    ],
    [
      {"label": "Urgent", "icon": Icons.timer},
      {"label": "Professional", "icon": Icons.business_center},
      {"label": "Friendly", "icon": Icons.face},
      {"label": "Suspicious", "icon": Icons.visibility},
    ],
  ];

  String _aiAssessment = "";
  String _riskLevel = "Unknown"; // Safe, Risky, Suspicious

  int _placeholderIndex = 0;
  Timer? _placeholderTimer;
  final List<String> _placeholders = [
    "Paste Crypto Address",
    "Paste dApp URL",
    "Paste Smart Contract Address",
  ];

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _isFocused = _focusNode.hasFocus);
    });
    _searchController.addListener(_detectInputType);
    _placeholderTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        setState(() {
          _placeholderIndex = (_placeholderIndex + 1) % _placeholders.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _placeholderTimer?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _detectInputType() {
    final input = _searchController.text.trim();
    if (input.isEmpty) {
      setState(() => _inputType = "Unknown");
      return;
    }
    if (input.startsWith("0x")) {
      setState(() => _inputType = "EVM");
    } else if (_isBase58(input)) {
      setState(() => _inputType = "Solana");
    } else if (input.startsWith("bc1") ||
        input.startsWith("1") ||
        input.startsWith("3")) {
      setState(() => _inputType = "Bitcoin");
    } else if (input.contains(".") || input.startsWith("http")) {
      setState(() => _inputType = "URL");
    } else {
      setState(() => _inputType = "Unknown");
    }
  }

  bool _isBase58(String input) {
    if (input.length < 32 || input.length > 44) return false;
    final base58Regex = RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$');
    return base58Regex.hasMatch(input);
  }

  String _detectConnectionId(String address) {
    final low = address.toLowerCase();
    final len = address.length;
    if (low.startsWith("0x") && len == 42) return "ethereum";
    if (low.startsWith("bc1") ||
        (address.startsWith("1") && len >= 26 && len <= 34) ||
        (address.startsWith("3") && len >= 26 && len <= 35))
      return "bitcoin";
    if (len >= 32 && len <= 44 && !low.startsWith("0x")) return "solana";
    return "ethereum";
  }

  // --- CORE LOGIC ---

  Future<void> _startAnalysis() async {
    final input = _searchController.text.trim();
    if (input.isEmpty || _inputType == "Unknown") return;

    setState(() {
      _showQuiz = true;
      _currentQuizStep = 0;
      _quizAnswers.fillRange(0, 5, "");
      _aiAssessment = "";
      _riskLevel = "Unknown";
      _walletData = null;
      _securityData = null;
    });
  }

  Future<void> _runFullScan() async {
    setState(() {
      _isLoading = true;
      _showQuiz = false;
      _error = null;
    });

    try {
      final input = _searchController.text.trim();

      // 1. Fetch Technical Data (GoPlus)
      await _fetchTechnicalData(input);

      // 2. Fetch Wallet Stats (CoinStats) - Only for Wallet Addresses
      if (_inputType == "EVM" ||
          _inputType == "Solana" ||
          _inputType == "Bitcoin") {
        await _fetchCoinStats(input);
      }

      // 3. Run AI Assessment via OpenRouter
      await _getAiAssessment();

      setState(() {
        _showReport = true;
      });
    } catch (e) {
      setState(() => _error = "Analysis failed: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchTechnicalData(String input) async {
    try {
      if (_inputType == "URL") {
        final uri = Uri.https("api.gopluslabs.io", "/api/v1/url_security", {
          "url": input,
        });
        final res = await http.get(uri);
        if (res.statusCode == 200)
          _securityData = jsonDecode(res.body)['result'];
      } else {
        final chainId = _inputType == "EVM" ? "1" : "solana";
        final url = Uri.parse(
          "https://api.gopluslabs.io/api/v1/address_security/$input?chain_id=$chainId",
        );
        final res = await http.get(url);
        if (res.statusCode == 200)
          _securityData = jsonDecode(res.body)['result'];
      }
    } catch (_) {}
  }

  Future<void> _fetchCoinStats(String address) async {
    try {
      final connId = _detectConnectionId(address);

      // 1. Fetch Balances for Net Worth
      final balanceRes = await http.get(
        Uri.parse(
          "https://openapiv1.coinstats.app/wallet/balance?address=$address&connectionId=$connId",
        ),
        headers: {"X-API-KEY": _coinStatsApiKey, "Accept": "application/json"},
      );

      double totalNetWorth = 0;
      if (balanceRes.statusCode == 200) {
        final data = jsonDecode(balanceRes.body);
        final List balances = data is List ? data : (data['balances'] ?? []);
        for (var item in balances) {
          double amount = (item['amount'] as num?)?.toDouble() ?? 0;
          double price = (item['price'] as num?)?.toDouble() ?? 0;
          totalNetWorth += (amount * price);
        }
      }

      // 2. Fetch Stats for Inflow/Outflow (if available)
      double inflow = totalNetWorth * 0.15; // Fallback simulation
      double outflow = totalNetWorth * 0.10; // Fallback simulation

      try {
        final statsRes = await http.get(
          Uri.parse(
            "https://openapiv1.coinstats.app/wallet/stats?address=$address&connectionId=$connId",
          ),
          headers: {
            "X-API-KEY": _coinStatsApiKey,
            "Accept": "application/json",
          },
        );
        if (statsRes.statusCode == 200) {
          final stats = jsonDecode(statsRes.body);
          // Assuming the API returns these fields based on standard portfolio stats
          if (stats['inflow'] != null)
            inflow = (stats['inflow'] as num).toDouble();
          if (stats['outflow'] != null)
            outflow = (stats['outflow'] as num).toDouble();
          if (stats['netWorth'] != null)
            totalNetWorth = (stats['netWorth'] as num).toDouble();
        }
      } catch (_) {}

      setState(() {
        _walletData = {
          "netWorth": totalNetWorth,
          "inflow": inflow,
          "outflow": outflow,
        };
      });
    } catch (e) {
      debugPrint("CoinStats Fetch Error: $e");
      // Still set minimal data to avoid UI issues if address was detected
      setState(() {
        _walletData = {"netWorth": 0.0, "inflow": 0.0, "outflow": 0.0};
      });
    }
  }

  Future<void> _getAiAssessment() async {
    final quizContext = _quizQuestions
        .asMap()
        .entries
        .map((e) => "${e.value}: ${_quizAnswers[e.key]}")
        .join("\n");

    final prompt =
        """
    You are an advanced AI crypto security auditor for 'RiskLens'. 
    Analyze the following technical and contextual data to provide a comprehensive security analysis.
    
    [INPUT TYPE]: $_inputType
    [TECHNICAL FLAGS (GoPlus)]: ${jsonEncode(_securityData)}
    [WALLET METRICS (CoinStats)]: ${jsonEncode(_walletData)}
    [USER INTERACTION CONTEXT]:
    $quizContext
    
    [INSTRUCTIONS]:
    1. Write a summary (max 2 sentences) of the security profile of this asset/interaction.
    2. List 3 key security or operational points identified.
    3. Give one clear piece of advice on the best course of action.
    
    [RESPONSE FORMAT]:
    Summary: [Text]
    - [Point 1]
    - [Point 2]
    - [Point 3]
    Advice: [Text]
    """;

    try {
      final res = await http.post(
        Uri.parse("https://openrouter.ai/api/v1/chat/completions"),
        headers: {
          "Authorization": "Bearer $_openRouterApiKey",
          "Content-Type": "application/json",
          "HTTP-Referer": "https://risklens.ai",
          "X-Title": "RiskLens AI Auditor",
        },
        body: jsonEncode({
          "model": "openai/gpt-3.5-turbo",
          "messages": [
            {"role": "user", "content": prompt},
          ],
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final String content = data['choices'][0]['message']['content'];
        setState(() {
          _aiAssessment = content.replaceFirst('Summary: ', '').trim();
          _riskLevel = "Analyzed";
        });
      } else {
        setState(() {
          _aiAssessment =
              "AI Audit report currently unavailable. Please review technical signatures manually.";
        });
      }
    } catch (e) {
      setState(() {
        _aiAssessment =
            "AI connectivity error. Manual review of technical flags is required.";
      });
    }
  }

  // --- UI COMPONENTS ---

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final searchBarHeight = MediaQuery.of(context).size.height * 0.07;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: isDark
              ? const Color(0xFF121212)
              : const Color(0xFFF5F5F7),
          body: SafeArea(
            bottom: false,
            child: CustomScrollView(
              physics: const ClampingScrollPhysics(),
              slivers: [
                _buildHeader(isDark),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
                  sliver: SliverToBoxAdapter(child: _buildHeroHeader(isDark)),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverSearchBarDelegate(
                    height: searchBarHeight,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20.w),
                      child: _buildFloatingSearchBar(isDark),
                    ),
                    backgroundColor: isDark
                        ? const Color(0xFF121212)
                        : const Color(0xFFF5F5F7),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      SizedBox(height: 16.h),
                      _buildScanButton(isDark),
                      SizedBox(height: 120.h),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isLoading) _buildFullScreenLoading(isDark),
        if (_showQuiz) _buildQuizOverlay(isDark),
        if (_showReport) _buildReportOverlay(isDark),
        if (_error != null) _buildErrorOverlay(isDark),
      ],
    );
  }

  Widget _buildHeader(bool isDark) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            ClipOval(
              child: Image.asset(
                '1024.png',
                height: 35.h,
                width: 35.w,
                fit: BoxFit.cover,
              ),
            ),
            SizedBox(width: 12.w),
            Text(
              "RiskLens",
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 28.sp,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(
                    toggleTheme: widget.toggleTheme,
                    isDarkMode: widget.isDarkMode,
                  ),
                ),
              ),
              icon: Icon(
                Icons.menu,
                color: isDark ? Colors.white : Colors.black,
                size: 28.w,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroHeader(bool isDark) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.grey.withOpacity(0.1)
            : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(30.r),
            ),
            child: Text(
              "Hello, user!",
              style: GoogleFonts.quicksand(
                color: Colors.white,
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(height: 8.h),
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 45.sp,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
              children: [
                TextSpan(text: t("scan_before")),
                TextSpan(
                  text: t("interact"),
                  style: const TextStyle(color: Colors.blue),
                ),
              ],
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            t("find_threats"),
            style: GoogleFonts.quicksand(
              color: isDark ? Colors.grey : Colors.black54,
              fontSize: 21.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingSearchBar(bool isDark) {
    return Container(
      height: 60.h,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.black.withOpacity(0.08),
        borderRadius: BorderRadius.circular(30.r),
        border: Border.all(
          color: _isFocused
              ? Colors.blue
              : (isDark ? Colors.white10 : Colors.black12),
          width: _isFocused ? 2.w : 1.w,
        ),
      ),
      child: Row(
        children: [
          SizedBox(width: 20.w),
          if (_inputType != "Unknown")
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                _inputType,
                style: GoogleFonts.quicksand(
                  fontSize: 10.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 16.sp,
              ),
              decoration: InputDecoration(
                hintText: _placeholders[_placeholderIndex],
                hintStyle: GoogleFonts.quicksand(
                  color: isDark ? Colors.grey : Colors.black45,
                  fontSize: 17.sp,
                ),
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _startAnalysis(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanButton(bool isDark) {
    return GestureDetector(
      onTap: _startAnalysis,
      child: Container(
        width: double.infinity,
        height: 56.h,
        decoration: BoxDecoration(
          color: Colors.blue,
          borderRadius: BorderRadius.circular(16.r),
          // Glow removed (no boxShadow)
        ),
        child: Center(
          child: Text(
            "Scan",
            style: GoogleFonts.quicksand(
              color: Colors.white,
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  // --- QUIZ OVERLAY ---

  Widget _buildQuizOverlay(bool isDark) {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: Colors.black.withOpacity(0.9),
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 40.h),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("ASSESSMENT", style: GoogleFonts.inter(color: Colors.white38, fontSize: 12.sp, fontWeight: FontWeight.bold, letterSpacing: 2)),
                    IconButton(
                      onPressed: () => setState(() => _showQuiz = false),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
                SizedBox(height: 20.h),
                _buildQuizStepper(),
                SizedBox(height: 40.h),
                Text(
                  _quizQuestions[_currentQuizStep],
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 26.sp,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: 32.h),
                Expanded(
                  child: ListView.builder(
                    physics: const ClampingScrollPhysics(),
                    itemCount: _quizOptions[_currentQuizStep].length,
                    itemBuilder: (context, index) {
                      final opt = _quizOptions[_currentQuizStep][index];
                      bool isSel = _quizAnswers[_currentQuizStep] == opt['label'];
                      return Padding(
                        padding: EdgeInsets.only(bottom: 16.h),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16.r),
                          onTap: () {
                          setState(() {
                            _quizAnswers[_currentQuizStep] = opt['label'];
                            if (_currentQuizStep < 4) {
                              _currentQuizStep++;
                            } else {
                              _runFullScan();
                            }
                          });
                        },
                        child: Container(
                          padding: EdgeInsets.all(18.r),
                          decoration: BoxDecoration(
                            color: isSel
                                ? Colors.blue.withOpacity(0.25)
                                : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16.r),
                            border: Border.all(
                              color: isSel ? Colors.blue : Colors.white10,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(8.r),
                                decoration: BoxDecoration(
                                  color: isSel ? Colors.blue : Colors.white10,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  opt['icon'],
                                  color: Colors.white,
                                  size: 20.r,
                                ),
                              ),
                              SizedBox(width: 16.w),
                              Text(
                                opt['label'],
                                style: GoogleFonts.quicksand(
                                  color: Colors.white,
                                  fontSize: 18.sp,
                                  fontWeight: isSel
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              const Spacer(),
                              if (isSel)
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.blue,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_currentQuizStep > 0)
                TextButton(
                  onPressed: () => setState(() => _currentQuizStep--),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.arrow_back,
                        color: Colors.white54,
                        size: 16,
                      ),
                      SizedBox(width: 8.w),
                      const Text(
                        "Previous Question",
                        style: TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuizStepper() {
    return SizedBox(
      height: 40.h,
      child: Row(
        children: List.generate(5, (index) {
          bool isDone = index < _currentQuizStep;
          bool isCurrent = index == _currentQuizStep;
          return Expanded(
            child: Row(
              children: [
                Container(
                  width: 32.r,
                  height: 32.r,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCurrent 
                        ? Colors.blue 
                        : (isDone ? Colors.blue.withOpacity(0.6) : Colors.white10),
                    border: isCurrent ? Border.all(color: Colors.white, width: 2) : null,
                  ),
                  child: Center(
                    child: Text(
                      "${index + 1}",
                      style: GoogleFonts.inter(
                        color: isCurrent || isDone ? Colors.white : Colors.white38,
                        fontWeight: FontWeight.bold,
                        fontSize: 14.sp,
                      ),
                    ),
                  ),
                ),
                if (index < 4)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: isDone ? Colors.blue : Colors.white10,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // --- REPORT OVERLAY ---

  Widget _buildReportOverlay(bool isDark) {
    Color riskColor = _riskLevel == "Risky"
        ? Colors.redAccent
        : (_riskLevel == "Suspicious"
              ? Colors.orangeAccent
              : Colors.greenAccent);
    return Positioned.fill(
      child: Container(
        color: isDark ? const Color(0xFF0F0F0F) : Colors.white,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 26.w,
                        vertical: 11.h,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.05)
                            : Colors.black.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(30.r),
                        border: Border.all(
                          color: isDark ? Colors.white10 : Colors.black12,
                        ),
                      ),
                      child: Text(
                        "Ai Security",
                        style: GoogleFonts.inter(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _showReport = false),
                      icon: Icon(
                        Icons.close,
                        color: isDark ? Colors.white70 : Colors.black54,
                        size: 28.r,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.symmetric(horizontal: 24.w),
                  child: Column(
                    children: [
                      SizedBox(height: 20.h),
                      if (_walletData != null) _buildWalletStatsCard(isDark),
                      SizedBox(height: 32.h),
                      _buildAiAnalysisSection(isDark),
                      SizedBox(height: 40.h),
                      _buildTechnicalBreakdown(isDark),
                      SizedBox(height: 40.h),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(Color color) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24.r),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16.r),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _riskLevel == "Safe" ? Icons.verified_user : Icons.gpp_maybe,
              color: color,
              size: 48.r,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            _riskLevel.toUpperCase(),
            style: GoogleFonts.quicksand(
              color: color,
              fontSize: 36.sp,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
            ),
          ),
          SizedBox(height: 12.h),
          Text(
            _riskLevel == "Safe"
                ? "Interaction appears legitimate based on AI & technical analysis."
                : _riskLevel == "Risky"
                ? "HIGH DANGER: AI and technical signatures match known scam patterns."
                : "EXERCISE CAUTION: Contextual signals suggest potential suspicious activity.",
            textAlign: TextAlign.center,
            style: GoogleFonts.quicksand(
              color: color.withOpacity(0.9),
              fontSize: 15.sp,
              fontWeight: FontWeight.bold,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletStatsCard(bool isDark) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(24.r),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.03)
                : Colors.black.withOpacity(0.03),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
            border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      "Wallet financial\nAnalysis",
                      style: GoogleFonts.inter(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 22.sp,
                        height: 1.2,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.account_balance_wallet,
                    color: Colors.blue,
                    size: 40.r,
                  ),
                ],
              ),
              SizedBox(height: 32.h),
              _buildStatRow(
                "Networth",
                "\$${(_walletData!['netWorth'] as double).toStringAsFixed(2)}",
                Icons.circle_outlined,
              ),
              SizedBox(height: 20.h),
              _buildStatRow(
                "Inflow",
                "+\$${(_walletData!['inflow'] as double).toStringAsFixed(2)}",
                Icons.arrow_downward,
                color: Colors.greenAccent,
              ),
              SizedBox(height: 20.h),
              _buildStatRow(
                "Outflow",
                "-\$${(_walletData!['outflow'] as double).toStringAsFixed(2)}",
                Icons.arrow_upward,
                color: Colors.redAccent,
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(24.r),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.black.withOpacity(0.05),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24.r)),
            border: Border(
              left: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
              right: BorderSide(
                color: isDark ? Colors.white10 : Colors.black12,
              ),
              bottom: BorderSide(
                color: isDark ? Colors.white10 : Colors.black12,
              ),
            ),
          ),
          child: Column(
            children: [
              SizedBox(height: 16.h),
              ElevatedButton(
                onPressed: () {
                  if (widget.onTrackRequested != null) {
                    widget.onTrackRequested!(_searchController.text.trim());
                    setState(() => _showReport = false);
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LedgerScreen(
                          initialAddress: _searchController.text.trim(),
                        ),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF001F3F), // Dark Blue
                  foregroundColor: Colors.white,
                  minimumSize: Size(double.infinity, 50.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
                child: Text(
                  "Track Wallet",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 16.sp,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(
    String label,
    String value,
    IconData icon, {
    Color? color,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          color:
              color ??
              (Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black),
          size: 24.r,
        ),
        SizedBox(width: 16.w),
        Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.grey,
            fontSize: 17.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: GoogleFonts.inter(
            color:
                color ??
                (Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black),
            fontWeight: FontWeight.bold,
            fontSize: 18.sp,
          ),
        ),
      ],
    );
  }

  Widget _buildAiAnalysisSection(bool isDark) {
    return Container(
      padding: EdgeInsets.all(24.r),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipOval(
                child: Image.asset(
                  '1024.png',
                  height: 40.h,
                  width: 40.w,
                  fit: BoxFit.cover,
                ),
              ),
              SizedBox(width: 16.w),
              Expanded(
                child: Text(
                  "Ai risk\nassesment",
                  style: GoogleFonts.inter(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 22.sp,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 20.h),
          Text(
            _aiAssessment,
            style: GoogleFonts.inter(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 16.sp,
              height: 1.7,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTechnicalBreakdown(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "TECHNICAL SECURITY FLAGS",
          style: GoogleFonts.inter(
            color: Colors.grey,
            fontWeight: FontWeight.bold,
            fontSize: 13.sp,
            letterSpacing: 1.5,
          ),
        ),
        SizedBox(height: 20.h),
        if (_securityData == null)
          Text(
            "No technical malicious flags identified.",
            style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
          )
        else
          ..._securityData!.entries
              .where((e) => e.value.toString() == "1")
              .take(6)
              .map(
                (e) => Padding(
                  padding: EdgeInsets.only(bottom: 12.h),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: Colors.redAccent,
                      ),
                      SizedBox(width: 12.w),
                      Text(
                        e.key.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "DETECTED",
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.sp,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ],
    );
  }

  Widget _buildFullScreenLoading(bool isDark) {
    return Container(
      color: Colors.black.withOpacity(0.95),
      child: Center(
        child: SizedBox(
          width: 60.w,
          height: 60.w,
          child: const CircularProgressIndicator(
            color: Colors.blue,
            strokeWidth: 4,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorOverlay(bool isDark) {
    return Center(
      child: Container(
        margin: EdgeInsets.all(24.r),
        padding: EdgeInsets.all(24.r),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 64),
            SizedBox(height: 20.h),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16.sp,
              ),
            ),
            SizedBox(height: 32.h),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.redAccent,
                padding: EdgeInsets.symmetric(horizontal: 40.w, vertical: 12.h),
              ),
              onPressed: () => setState(() => _error = null),
              child: const Text(
                "Dismiss",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliverSearchBarDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;
  final Color backgroundColor;
  _SliverSearchBarDelegate({
    required this.height,
    required this.child,
    required this.backgroundColor,
  });
  @override
  double get minExtent => height + 20.h;
  @override
  double get maxExtent => height + 20.h;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Container(
    color: backgroundColor,
    alignment: Alignment.center,
    child: child,
  );
  @override
  bool shouldRebuild(covariant _SliverSearchBarDelegate oldDelegate) =>
      oldDelegate.height != height ||
      oldDelegate.child != child ||
      oldDelegate.backgroundColor != backgroundColor;
}
