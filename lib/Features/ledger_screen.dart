import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'historytab.dart';
import '../wallet/wallet.dart';
import 'settings_screen.dart';

class LedgerScreen extends StatefulWidget {
  final String? initialAddress;
  final VoidCallback? toggleTheme;
  final bool? isDarkMode;

  const LedgerScreen({
    super.key,
    this.initialAddress,
    this.toggleTheme,
    this.isDarkMode,
  });

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late TabController _tabController;

  // Hint Animation State
  int _hintIndex = 0;
  late Timer _hintTimer;
  final List<String> _hintLabels = ["BTC", "SOL", "ETH", "USDT", "EVM"];

  bool _isFocused = false;
  bool _isLoading = false;
  bool _hasError = false;
  bool _showResults = false;
  bool _showPriceInfo = false;

  String _balance = "0.00";
  String _chain = "Ethereum";
  double _currentPrice = 0.0;
  String _errorMessage = "Invalid address or failed to fetch data";
  String _selectedTimeFilter = "1M";

  int _loadingStep = 0;
  Timer? _loadingTimer;
  final List<String> _loadingMessages = [
    "Tracking the wallet...",
    "Getting net worth...",
    "Scanning assets...",
    "Fetching history...",
    "Almost there...",
  ];

  List<FlSpot> _chartData = [];
  List<double> _chartTimestamps = [];
  WalletScanSnapshot? _scanSnapshot;
  late final WalletScanCoordinator _walletScanner;
  late final WalletApiCredentials _walletCreds;

  // ── API Key (CoinStats only) ──────────────────────────────────────────────
  final String coinStatsApiKey = dotenv.get('COINSTATS_API_KEY', fallback: '');

  @override
  void initState() {
    super.initState();
    _walletCreds = WalletApiCredentials(coinStatsApiKey: coinStatsApiKey);
    _walletScanner = WalletScanCoordinator(_walletCreds);
    _tabController = TabController(length: 2, vsync: this);
    _focusNode.addListener(() {
      setState(() => _isFocused = _focusNode.hasFocus);
    });
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
    _hintTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        setState(() => _hintIndex = (_hintIndex + 1) % _hintLabels.length);
      }
    });
    if (widget.initialAddress != null) {
      _controller.text = widget.initialAddress!;
      WidgetsBinding.instance.addPostFrameCallback((_) => fetchWalletData());
    }
  }

  @override
  void dispose() {
    _walletScanner.dispose();
    _controller.dispose();
    _focusNode.dispose();
    _tabController.dispose();
    _hintTimer.cancel();
    super.dispose();
  }

  String _shortenAddress(String addr) {
    if (addr.length < 10) return addr;
    return "${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}";
  }

  // ─── TIME FILTER → CoinStats period ───────────────────────────────────────
  String _filterToPeriod(String filter) {
    switch (filter) {
      case "1H":
        return "1h";
      case "1D":
        return "24h";
      case "1W":
        return "1w";
      case "1M":
        return "1m";
      case "3M":
        return "3m";
      case "1Y":
        return "1y";
      case "Max":
        return "all";
      default:
        return "1m";
    }
  }

  // ─── CHART DATA via CoinStats ─────────────────────────────────────────────
  Future<void> _fetchChart({String? filter}) async {
    final rawAddress = _controller.text.trim();
    String address = rawAddress;
    if (address.contains(":")) address = address.split(":").last;
    if (address.isEmpty) return;

    final connId = _detectConnectionId(address);
    final period = _filterToPeriod(filter ?? _selectedTimeFilter);
    setState(() {
      _isLoading = true;
      _loadingStep = 0;
    });

    _loadingTimer?.cancel();
    _loadingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _isLoading) {
        setState(() {
          _loadingStep = (_loadingStep + 1) % _loadingMessages.length;
        });
      } else {
        timer.cancel();
      }
    });

    List<List<double>> chartPoints = [];

    try {
      final res = await http.get(
        Uri.parse(
          "https://openapiv1.coinstats.app/wallet/charts?address=$address&connectionId=$connId&period=$period",
        ),
        headers: {"X-API-KEY": coinStatsApiKey, "Accept": "application/json"},
      );

      if (res.statusCode == 200) {
        final raw = jsonDecode(res.body);
        final List dataList = raw is List ? raw : (raw['chart'] as List? ?? []);
        for (final point in dataList) {
          if (point is List && point.length >= 2) {
            chartPoints.add([
              (point[0] as num).toDouble(),
              (point[1] as num).toDouble(),
            ]);
          }
        }
      }
    } catch (e) {
      debugPrint("Portfolio chart fetch error: $e");
    }

    // Fallback: If wallet-wide history is unavailable (common for non-indexed addresses),
    // estimate it using the primary asset's price movement scaled by current total networth.
    if (chartPoints.isEmpty && _scanSnapshot != null) {
      final primaryChart = await _walletScanner.fetchCoinChart(
        _scanSnapshot!.primaryCoinId,
        period: period,
      );
      if (primaryChart.isNotEmpty) {
        final currentPrice = primaryChart.last[1];
        if (currentPrice > 0) {
          final scale = _scanSnapshot!.totalUsd / currentPrice;
          chartPoints = primaryChart.map((p) => [p[0], p[1] * scale]).toList();
        }
      }
    }

    if (mounted) {
      setState(() {
        if (chartPoints.isNotEmpty) {
          _chartTimestamps = chartPoints.map((p) => p[0]).toList();
          _chartData = chartPoints
              .asMap()
              .entries
              .map((e) => FlSpot(e.key.toDouble(), e.value[1]))
              .toList();
        }
        _isLoading = false;
      });
      _loadingTimer?.cancel();
    }
  }

  // ─── PRICE via CoinStats ──────────────────────────────────────────────────
  Future<void> _fetchPrice(String coinId) async {
    final price = await _walletScanner.fetchCoinPrice(coinId);
    if (mounted) setState(() => _currentPrice = price);
  }

  // ─── MAIN ENTRY POINT ────────────────────────────────────────────────────
  String _detectConnectionId(String address) {
    final low = address.toLowerCase();
    final len = address.length;
    if (low.startsWith("0x") && len == 42) return "ethereum";
    if (low.startsWith("bc1")) return "bitcoin";
    if (address.startsWith("1") && len >= 26 && len <= 34) return "bitcoin";
    if (address.startsWith("3") && len >= 26 && len <= 35) return "bitcoin";
    if (len >= 32 &&
        len <= 44 &&
        !low.startsWith("0x") &&
        !low.startsWith("bc1"))
      return "solana";
    return "ethereum";
  }

  String _chainToCoinId(String chain) {
    switch (chain.toLowerCase()) {
      case "solana":
        return "solana";
      case "bitcoin":
        return "bitcoin";
      case "bsc":
      case "binance-smart-chain":
        return "binancecoin";
      case "polygon":
        return "matic-network";
      case "tron":
        return "tron";
      case "xrp":
        return "ripple";
      case "avalanche":
        return "avalanche-2";
      default:
        return "ethereum";
    }
  }

  String _guessCoinId(String symbol) {
    switch (symbol.toUpperCase()) {
      case "BTC":
        return "bitcoin";
      case "ETH":
        return "ethereum";
      case "SOL":
        return "solana";
      case "BNB":
        return "binancecoin";
      case "MATIC":
        return "matic-network";
      case "TRX":
        return "tron";
      case "XRP":
        return "ripple";
      case "AVAX":
        return "avalanche-2";
      default:
        return "bitcoin";
    }
  }

  Future<void> fetchWalletData() async {
    final rawAddress = _controller.text.trim();
    String address = rawAddress;
    if (address.contains(":")) address = address.split(":").last;
    if (address.isEmpty) return;

    _focusNode.unfocus();

    setState(() {
      _isLoading = true;
      _hasError = false;
      _chartData = [];
      _scanSnapshot = null;
      _balance = "0.00";
      _errorMessage = "Failed to load portfolio data";
      _loadingStep = 0;
    });

    _loadingTimer?.cancel();
    _loadingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _isLoading) {
        setState(() {
          _loadingStep = (_loadingStep + 1) % _loadingMessages.length;
        });
      } else {
        timer.cancel();
      }
    });

    try {
      final connId = _detectConnectionId(address);
      final res = await http.get(
        Uri.parse(
          "https://openapiv1.coinstats.app/wallet/balance?address=$address&connectionId=$connId",
        ),
        headers: {"X-API-KEY": coinStatsApiKey, "Accept": "application/json"},
      );

      if (res.statusCode != 200) {
        throw Exception("CoinStats API error: ${res.statusCode} ${res.body}");
      }

      final raw = jsonDecode(res.body);
      final List balances = raw is List
          ? raw
          : (raw['balances'] as List? ??
                raw['result'] as List? ??
                raw['data'] as List? ??
                []);

      if (balances.isEmpty) {
        throw Exception("No tokens found for this address.");
      }

      double totalUsd = 0;
      final List<TokenHolding> holdings = [];
      final Set<String> chains = {};

      for (final token in balances) {
        final double bal =
            (token['amount'] as num?)?.toDouble() ??
            (token['balance'] as num?)?.toDouble() ??
            0;
        final double price =
            (token['price'] as num?)?.toDouble() ??
            (token['priceUsd'] as num?)?.toDouble() ??
            0;
        final double value = bal * price;
        final String sym =
            token['symbol']?.toString() ?? token['coinId']?.toString() ?? "???";
        final String chain =
            token['blockchain']?.toString() ??
            token['chain']?.toString() ??
            "ethereum";

        chains.add(chain);
        totalUsd += value;
        holdings.add(
          TokenHolding(
            symbol: sym.toUpperCase(),
            chain: chain,
            balance: bal,
            priceUsd: price,
            valueUsd: value,
          ),
        );
      }

      holdings.sort((a, b) => b.valueUsd.compareTo(a.valueUsd));

      String displayLabel;
      String primaryCoinId;

      if (chains.length > 1) {
        displayLabel = "Multi-chain";
        primaryCoinId = holdings.isNotEmpty
            ? _guessCoinId(holdings.first.symbol)
            : "bitcoin";
      } else {
        final singleChain = chains.first;
        displayLabel = singleChain.isNotEmpty
            ? singleChain[0].toUpperCase() + singleChain.substring(1)
            : singleChain;
        primaryCoinId = _chainToCoinId(displayLabel);
      }

      final snap = WalletScanSnapshot(
        displayLabel: displayLabel,
        totalUsd: totalUsd,
        primaryCoinId: primaryCoinId,
        historyDescriptors: chains
            .map((c) => HistoryDescriptor(chain: c, address: address))
            .toList(),
        holdings: holdings,
      );

      if (mounted) {
        setState(() {
          _chain = snap.displayLabel;
          _balance = snap.totalUsd.toStringAsFixed(2);
          _scanSnapshot = snap;
        });
      }

      final coinId = snap.primaryCoinId;
      await Future.wait([_fetchChart(), _fetchPrice(coinId)]);

      if (mounted) {
        setState(() {
          _showResults = true;
          _isLoading = false;
        });
        _loadingTimer?.cancel();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
          _errorMessage = "Failed to load data. Check address and try again.";
          _scanSnapshot = null;
        });
        _loadingTimer?.cancel();
      }
      debugPrint("fetchWalletData error: $e");
    }
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F7);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        bottom: false,
        child: NestedScrollView(
          physics: const ClampingScrollPhysics(),
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildHeader(),
                    const SizedBox(height: 24),
                    if (!_showResults) _buildGlassSearchBar(),
                    if (!_showResults) const SizedBox(height: 32),
                  ]),
                ),
              ),
              if (_showResults)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverHeaderDelegate(
                    height: 80,
                    backgroundColor: bgColor,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                      child: _buildGlassSearchBar(),
                    ),
                  ),
                ),
              if (_showResults)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverTabBarDelegate(
                    TabBar(
                      controller: _tabController,
                      indicatorColor: Colors.blue,
                      labelColor: isDark ? Colors.white : Colors.black,
                      unselectedLabelColor: Colors.grey,
                      dividerColor: isDark ? Colors.white12 : Colors.black12,
                      labelStyle: GoogleFonts.quicksand(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      unselectedLabelStyle: GoogleFonts.quicksand(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                      ),
                      tabs: const [
                        Tab(text: "Portfolio"),
                        Tab(text: "History"),
                      ],
                    ),
                    bgColor,
                  ),
                ),
            ];
          },
          body: _buildMainContent(),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.grey.withOpacity(0.15)
                : Colors.black.withOpacity(0.15),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 45,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  children: const [
                    TextSpan(text: "Track before you "),
                    TextSpan(
                      text: "trust",
                      style: TextStyle(color: Colors.blue),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Enter a wallet address to track portfolio and transaction history",
                style: GoogleFonts.quicksand(
                  color: isDark ? Colors.grey : Colors.black,
                  fontSize: 21,
                  fontWeight: isDark ? FontWeight.w500 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassSearchBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 60,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.black.withOpacity(0.12),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: _isFocused
                  ? Colors.blue
                  : (isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.black.withOpacity(0.15)),
              width: _isFocused ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 20),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  onSubmitted: (_) => fetchWalletData(),
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    hintText:
                        "Enter wallet address (${_hintLabels[_hintIndex]})",
                    hintStyle: TextStyle(color: Colors.grey),
                    border: InputBorder.none,
                  ),
                ),
              ),
              GestureDetector(
                onTap: fetchWalletData,
                child: Container(
                  height: 44,
                  width: 44,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white : Colors.black,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_upward,
                    color: isDark ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              CircularProgressIndicator(
                color: Colors.blue,
                strokeWidth: 3,
                backgroundColor: isDark ? Colors.white10 : Colors.black12,
              ),
              const SizedBox(height: 24),
              Text(
                _loadingMessages[_loadingStep],
                style: GoogleFonts.quicksand(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "Scanning decentralized data",
                style: GoogleFonts.quicksand(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (_hasError) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _errorMessage,
                style: const TextStyle(color: Colors.redAccent, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: fetchWalletData,
                icon: const Icon(Icons.refresh),
                label: const Text("Retry"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              ),
            ],
          ),
        ),
      );
    }

    if (!_showResults) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.black.withOpacity(0.12),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.black.withOpacity(0.15),
                ),
              ),
              child: Center(
                child: Text(
                  "Enter a wallet address to begin tracking",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.quicksand(
                    color: isDark ? Colors.white70 : Colors.black,
                    fontSize: 18,
                    fontWeight: isDark ? FontWeight.w500 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [_buildPortfolioTab(), _buildHistoryTab()],
    );
  }

  Widget _buildGraph() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_chartData.isEmpty) {
      return const Center(
        child: Text(
          "No chart data available",
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
      );
    }
    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (spot) =>
                isDark ? const Color(0xFF2A2A2A) : Colors.white,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final index = spot.x.toInt();
                if (index < 0 || index >= _chartTimestamps.length) return null;

                final timestamp = _chartTimestamps[index].toInt();
                // CoinStats timestamps are usually in seconds
                final date = DateTime.fromMillisecondsSinceEpoch(
                  timestamp * 1000,
                );
                final formattedDate = DateFormat(
                  'MMM d, yyyy HH:mm',
                ).format(date);

                return LineTooltipItem(
                  "$formattedDate\n\$${spot.y.toStringAsFixed(2)}",
                  GoogleFonts.quicksand(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }).toList();
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withOpacity(0.05)
                : Colors.black.withOpacity(0.05),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              getTitlesWidget: (value, meta) {
                if (value == meta.max || value == meta.min) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      "\$${value.toStringAsFixed(0)}",
                      style: const TextStyle(color: Colors.grey, fontSize: 10),
                    ),
                  );
                }
                return const SizedBox();
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: _chartData,
            isCurved: true,
            color: Colors.greenAccent,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
        ],
      ),
    );
  }

  Widget _buildChainLogo({double size = 36}) {
    final Map<String, String> logoUrls = {
      "Multi-chain":
          "https://coin-images.coingecko.com/coins/images/279/large/ethereum.png",
      "EVM":
          "https://coin-images.coingecko.com/coins/images/279/large/ethereum.png",
      "XRP":
          "https://coin-images.coingecko.com/coins/images/44/large/xrp-symbol-white-128.png",
      "Tron":
          "https://coin-images.coingecko.com/coins/images/1094/large/tron-logo.png",
      "Solana":
          "https://coin-images.coingecko.com/coins/images/4128/large/solana.png",
      "Bitcoin":
          "https://coin-images.coingecko.com/coins/images/1/large/bitcoin.png",
      "Ethereum":
          "https://coin-images.coingecko.com/coins/images/279/large/ethereum.png",
    };
    final Map<String, Color> chainColors = {
      "Multi-chain": const Color(0xFF627EEA),
      "EVM": const Color(0xFF627EEA),
      "XRP": const Color(0xFF23292F),
      "Tron": const Color(0xFFEB0029),
      "Solana": const Color(0xFF9945FF),
      "Bitcoin": const Color(0xFFF7931A),
      "Ethereum": const Color(0xFF627EEA),
    };
    final Map<String, String> chainSymbols = {
      "Multi-chain": "Ξ",
      "EVM": "Ξ",
      "XRP": "✕",
      "Tron": "T",
      "Solana": "◎",
      "Bitcoin": "₿",
      "Ethereum": "Ξ",
    };

    final url = logoUrls[_chain];
    final color = chainColors[_chain] ?? Colors.blue;
    final symbol = chainSymbols[_chain] ?? "◈";

    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(
        child: Text(
          symbol,
          style: TextStyle(
            fontSize: size * 0.45,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );

    if (url == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: Image.network(
        url,
        width: size,
        height: size,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }

  Widget _buildPortfolioTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.black.withOpacity(0.1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Performance",
                      style: GoogleFonts.quicksand(
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        if (_showPriceInfo)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.grey[850]
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark ? Colors.white12 : Colors.black12,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildChainLogo(size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  "\$${_currentPrice.toStringAsFixed(2)}",
                                  style: GoogleFonts.quicksand(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            setState(() => _showPriceInfo = !_showPriceInfo);
                            if (_showPriceInfo) {
                              Future.delayed(const Duration(seconds: 4), () {
                                if (mounted) {
                                  setState(() => _showPriceInfo = false);
                                }
                              });
                            }
                          },
                          child: Icon(
                            Icons.info_outline,
                            color: (isDark ? Colors.white : Colors.black)
                                .withOpacity(0.5),
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildChainLogo(),
                    const SizedBox(width: 12),
                    Text(
                      "\$$_balance",
                      style: GoogleFonts.quicksand(
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _chain,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 24),
                SizedBox(height: 200, child: _buildGraph()),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ["1H", "1D", "1W", "1M", "1Y", "Max"].map((filter) {
                    bool isSelected = _selectedTimeFilter == filter;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedTimeFilter = filter);
                        // Re-fetch chart for new time period
                        if (_scanSnapshot != null) {
                          _fetchChart(filter: filter);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDark
                                    ? const Color(0xFF2A2A2A)
                                    : Colors.blue.withOpacity(0.1))
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          filter,
                          style: GoogleFonts.quicksand(
                            color: isSelected
                                ? (isDark ? Colors.white : Colors.blue)
                                : Colors.grey,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    final rawAddress = _controller.text.trim();
    String address = rawAddress;
    if (address.contains(":")) address = address.split(":").last;
    return HistoryTab(
      address: address,
      chain: _chain,
      scanSnapshot: _scanSnapshot,
      apiCredentials: _walletCreds,
    );
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color backgroundColor;

  _SliverTabBarDelegate(this.tabBar, this.backgroundColor);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: backgroundColor, child: tabBar);
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return backgroundColor != oldDelegate.backgroundColor ||
        tabBar != oldDelegate.tabBar;
  }
}

class _SliverHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;
  final Color backgroundColor;

  _SliverHeaderDelegate({
    required this.child,
    required this.height,
    required this.backgroundColor,
  });

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: backgroundColor, child: child);
  }

  @override
  bool shouldRebuild(_SliverHeaderDelegate oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.child != child;
  }
}
