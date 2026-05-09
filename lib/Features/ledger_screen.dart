import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'historytab.dart';

class LedgerScreen extends StatefulWidget {
  final String? initialAddress;
  const LedgerScreen({super.key, this.initialAddress});

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
  String _selectedTimeFilter = "1D";

  List<FlSpot> _chartData = [];

  // History state is now handled by HistoryTab widget.

  final String moralisApiKey =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJub25jZSI6ImYyMTE4N2MxLTE4NzAtNDU0MC1hYzIwLTc3NTc4NDRhYjFjNCIsIm9yZ0lkIjoiNTEzODg4IiwidXNlcklkIjoiNTI4ODExIiwidHlwZUlkIjoiOTQ2YTI0ZGMtODdkNC00YzNiLTlmN2UtNTQzZjA3MDc2OTAyIiwidHlwZSI6IlBST0pFQ1QiLCJpYXQiOjE3Nzc3Mzg0NzMsImV4cCI6NDkzMzQ5ODQ3M30.MRhG1_u1iLfLPI77pteOnlpyQgvNyaDTzt2hm1hwOZA";
  final String covalentApiKey = "YOUR_COVALENT_API_KEY";
  final String coinGeckoApiKey = "CG-aZWy4YFQ6YGD98ookZCRghDF";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _focusNode.addListener(() {
      setState(() => _isFocused = _focusNode.hasFocus);
    });

    _controller.addListener(() {
      if (mounted) setState(() {});
    });

    _hintTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        setState(() {
          _hintIndex = (_hintIndex + 1) % _hintLabels.length;
        });
      }
    });

    if (widget.initialAddress != null) {
      _controller.text = widget.initialAddress!;
      // Use addPostFrameCallback to ensure the widget is built before fetching
      WidgetsBinding.instance.addPostFrameCallback((_) {
        fetchWalletData();
      });
    }
  }

  @override
  void dispose() {
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

  int _getChainId(String chain) {
    switch (chain) {
      case "eth":
        return 1;
      case "polygon":
        return 137;
      case "bsc":
        return 56;
      case "arbitrum":
        return 42161;
      case "optimism":
        return 10;
      case "base":
        return 8453;
      case "avalanche":
        return 43114;
      default:
        return 1;
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December",
    ];
    return "${months[date.month - 1]} ${date.day}, ${date.year}";
  }

  String _formatTime(DateTime date) {
    int hour = date.hour;
    String period = "AM";
    if (hour >= 12) {
      period = "PM";
      if (hour > 12) hour -= 12;
    }
    if (hour == 0) hour = 12;
    String min = date.minute.toString().padLeft(2, '0');
    return "$hour:$min $period";
  }

  // ─── CHAIN DETECTION ───────────────────────────────────────────────────────
  String _detectChain(String address) {
    final cleanAddr = address.trim();
    final lowAddr = cleanAddr.toLowerCase();
    final len = cleanAddr.length;

    // EVM: 0x prefix + 40 hex chars (standard) or just 42 chars total
    if (lowAddr.startsWith("0x") && len == 42) return "Ethereum";

    // Bitcoin bech32
    if (lowAddr.startsWith("bc1")) return "Bitcoin";

    // Solana: Usually 32-44 chars, base58
    if (len >= 32 &&
        len <= 44 &&
        !lowAddr.startsWith("0x") &&
        !lowAddr.startsWith("bc1")) {
      // Very likely Solana if it's not EVM or BTC bech32
      return "Solana";
    }

    // Bitcoin legacy
    if (cleanAddr.startsWith("1") && len >= 26 && len <= 34) return "Bitcoin";
    if (cleanAddr.startsWith("3") && len >= 26 && len <= 35) return "Bitcoin";

    return "Unknown";
  }

  // ─── PRICE HELPERS ─────────────────────────────────────────────────────────
  Future<double> _fetchPrice(String coinId) async {
    try {
      final res = await http.get(
        Uri.parse(
          "https://api.coingecko.com/api/v3/simple/price?ids=$coinId&vs_currencies=usd",
        ),
        headers: {"x-cg-demo-api-key": coinGeckoApiKey},
      );
      if (res.statusCode == 200) {
        return (jsonDecode(res.body)[coinId]['usd'] as num).toDouble();
      }
    } catch (_) {}
    return 0.0;
  }

  Future<void> _fetchCoinGeckoChart(String coinId) async {
    try {
      final res = await http.get(
        Uri.parse(
          "https://api.coingecko.com/api/v3/coins/$coinId/market_chart?vs_currency=usd&days=30&interval=daily",
        ),
        headers: {"x-cg-demo-api-key": coinGeckoApiKey},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final prices = data['prices'] as List;
        List<FlSpot> spots = [];
        for (int i = 0; i < prices.length; i++) {
          double price = (prices[i][1] as num).toDouble();
          spots.add(FlSpot(i.toDouble(), price));
        }
        setState(() {
          _chartData = spots;
        });
      }
    } catch (e) {
      debugPrint("CoinGecko chart error: $e");
    }
  }

  // ─── MAIN ENTRY POINT ──────────────────────────────────────────────────────
  Future<void> fetchWalletData() async {
    final rawAddress = _controller.text.trim();
    String address = rawAddress;
    if (address.contains(":")) {
      address = address.split(":").last;
    }
    if (address.isEmpty) return;

    _focusNode.unfocus();
    final detectedChain = _detectChain(address);

    setState(() {
      _isLoading = true;
      _hasError = false;
      // Maintain showing results if we are just refreshing/switching addresses
      // This prevents the tabs from disappearing and flickering
      if (!_showResults) _showResults = false;
      _chartData = [];
      _chain = detectedChain;
      _balance = "0.00";
      _errorMessage = "Failed to load portfolio data";
    });

    debugPrint("Detected chain: $detectedChain for address: $address");

    try {
      // Run fetching in parallel for better performance
      String coinId = detectedChain.toLowerCase();
      if (coinId == "ethereum") coinId = "ethereum";

      await Future.wait([
        _fetchBalance(address, detectedChain),
        // _fetchTransactions moved to HistoryTab
        _fetchCoinGeckoChart(coinId),
        _updatePrice(detectedChain),
      ]);

      setState(() {
        _showResults = true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _hasError = true;
        _isLoading = false;
        _errorMessage =
            "Failed to load data. Please check the address and try again.";
      });
      debugPrint("fetchWalletData error: $e");
    }
  }

  Future<void> _updatePrice(String chain) async {
    String coinId = chain.toLowerCase();
    if (coinId == "ethereum") coinId = "ethereum";
    if (coinId == "solana") coinId = "solana";
    if (coinId == "bitcoin") coinId = "bitcoin";
    _currentPrice = await _fetchPrice(coinId);
  }

  // ─── BALANCE FETCHING ──────────────────────────────────────────────────────
  Future<void> _fetchBalance(String address, String chain) async {
    if (chain == "Ethereum") {
      await _fetchEvmBalance(address);
    } else if (chain == "Solana") {
      await _fetchSolanaBalance(address);
    } else if (chain == "Bitcoin") {
      await _fetchBitcoinBalance(address);
    }
  }

  Future<void> _fetchEvmBalance(String address) async {
    debugPrint("Fetching EVM balance for $address...");
    final String baseUrl = "https://deep-index.moralis.io/api/v2";
    final Map<String, String> headers = {
      "X-API-Key": moralisApiKey,
      "accept": "application/json"
    };

    double totalNetWorthUsd = 0.0;

    try {
      // 1. Native Balance
      final nativeRes = await http.get(
        Uri.parse("$baseUrl/$address/balance?chain=eth"),
        headers: headers,
      );

      if (nativeRes.statusCode == 200) {
        final nativeData = jsonDecode(nativeRes.body);
        double ethBalance = (double.tryParse(nativeData['balance']?.toString() ?? "0") ?? 0) / 1e18;

        if (ethBalance > 0) {
          // Fetch ETH price
          try {
            final priceRes = await http.get(
              Uri.parse("$baseUrl/erc20/0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2/price?chain=eth"), // WETH
              headers: headers,
            );
            if (priceRes.statusCode == 200) {
              double ethPrice = (jsonDecode(priceRes.body)['usdPrice'] as num?)?.toDouble() ?? 0.0;
              totalNetWorthUsd += (ethBalance * ethPrice);
            }
          } catch (_) {}
        }
      }

      // 2. Token Balances
      final tokenRes = await http.get(
        Uri.parse("$baseUrl/$address/erc20?chain=eth"),
        headers: headers,
      );

      if (tokenRes.statusCode == 200) {
        final List tokens = jsonDecode(tokenRes.body);
        final List<Future<void>> priceFutures = [];

        for (var token in tokens) {
          final String tokenAddress = token['token_address'] ?? "";
          if (tokenAddress.isEmpty) continue;

          final int decimals = int.tryParse(token['decimals']?.toString() ?? "18") ?? 18;
          final double balance = (double.tryParse(token['balance']?.toString() ?? "0") ?? 0) / pow(10, decimals);

          if (balance > 0) {
            priceFutures.add(() async {
              try {
                final priceRes = await http.get(
                  Uri.parse("$baseUrl/erc20/$tokenAddress/price?chain=eth"),
                  headers: headers,
                );
                if (priceRes.statusCode == 200) {
                  double price = (jsonDecode(priceRes.body)['usdPrice'] as num?)?.toDouble() ?? 0.0;
                  totalNetWorthUsd += (balance * price);
                }
              } catch (_) {}
            }());
          }
        }

        await Future.wait(priceFutures);
      }

      setState(() {
        _balance = totalNetWorthUsd.toStringAsFixed(2);
      });

    } catch (e) {
      debugPrint("Net Worth API error: $e");
    }
  }

  Future<void> _fetchSolanaBalance(String address) async {
    try {
      final res = await http.get(
        Uri.parse(
          "https://solana-gateway.moralis.io/account/mainnet/$address/balance",
        ),
        headers: {"X-API-Key": moralisApiKey, "accept": "application/json"},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        // Moralis returns lamports field
        double lamports =
            double.tryParse(data['lamports']?.toString() ?? "0") ?? 0;
        double sol = lamports / 1e9;
        if (sol == 0) {
          // Try solana field as well
          sol = double.tryParse(data['solana']?.toString() ?? "0") ?? 0;
        }
        final solPrice = await _fetchPrice("solana");
        _balance = (sol * solPrice).toStringAsFixed(2);
        return;
      }
    } catch (e) {
      debugPrint("Solana balance error: $e");
    }
    _balance = "0.00";
  }

  Future<void> _fetchBitcoinBalance(String address) async {
    try {
      final res = await http.get(
        Uri.parse("https://mempool.space/api/address/$address"),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final chain = data['chain_stats'] ?? {};
        final mem = data['mempool_stats'] ?? {};
        int funded =
            (chain['funded_txo_sum'] ?? 0) + (mem['funded_txo_sum'] ?? 0);
        int spent = (chain['spent_txo_sum'] ?? 0) + (mem['spent_txo_sum'] ?? 0);
        double btc = (funded - spent) / 100000000;
        final btcPrice = await _fetchPrice("bitcoin");
        _balance = (btc * btcPrice).toStringAsFixed(2);
        return;
      }
    } catch (e) {
      debugPrint("Bitcoin balance error: $e");
    }
    _balance = "0.00";
  }

  // Transaction fetching and filtering moved to HistoryTab.dart

  Future<void> _fetchCovalentGraph(String address, int chainId) async {
    final url = Uri.parse(
      "https://api.covalenthq.com/v1/$chainId/address/$address/portfolio_v2/",
    );

    try {
      final response = await http.get(
        url,
        headers: {"Authorization": "Bearer $covalentApiKey"},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['data']['items'] as List;
        if (items.isNotEmpty) {
          final holdings = items[0]['holdings'] as List;
          final chronological = holdings.reversed.toList();
          List<FlSpot> spots = [];
          for (int i = 0; i < chronological.length; i++) {
            double val = (chronological[i]['close']?['quote'] ?? 0).toDouble();
            spots.add(FlSpot(i.toDouble(), val));
          }
          _chartData = spots;
        }
      }
    } catch (e) {
      debugPrint("Failed to load covalent chart: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF5F5F7),
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                  children: [
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
                  decoration: const InputDecoration(
                    hintText: "Enter wallet address (ETH, SOL...)",
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
      return const Center(child: CircularProgressIndicator(color: Colors.blue));
    }

    if (_hasError) {
      return Center(
        child: Text(
          _errorMessage,
          style: const TextStyle(color: Colors.redAccent, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (!_showResults) {
      return ClipRRect(
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
      );
    }

    return Column(
      children: [
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
        const SizedBox(height: 16),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [_buildPortfolioTab(), _buildHistoryTab()],
          ),
        ),
      ],
    );
  }

  Widget _buildGraph() {
    if (_chartData.isEmpty) {
      return const Center(
        child: Text(
          "No portfolio history available",
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
      );
    }

    return LineChart(
      LineChartData(
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
          show: true,
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                if (value == meta.max || value == meta.min) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Text(
                      "\$${value.toStringAsFixed(2)}",
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
      "Solana":
          "https://coin-images.coingecko.com/coins/images/4128/large/solana.png",
      "Bitcoin":
          "https://coin-images.coingecko.com/coins/images/1/large/bitcoin.png",
      "Ethereum":
          "https://coin-images.coingecko.com/coins/images/279/large/ethereum.png",
    };
    final Map<String, Color> chainColors = {
      "Solana": const Color(0xFF9945FF),
      "Bitcoin": const Color(0xFFF7931A),
      "Ethereum": const Color(0xFF627EEA),
    };
    final Map<String, String> chainSymbols = {
      "Solana": "◎",
      "Bitcoin": "₿",
      "Ethereum": "Ξ",
    };

    final url = logoUrls[_chain];
    final color = chainColors[_chain] ?? Colors.blue;
    final symbol = chainSymbols[_chain] ?? "◈";
    final label = _chain == "Unknown" ? "?" : _chain.substring(0, 1);

    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(
        child: Text(
          symbol.length == 1 ? symbol : label,
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
      padding: const EdgeInsets.only(bottom: 140),
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          // Performance & Balance Card
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
                                  "${_currentPrice.toStringAsFixed(2)}\$",
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
                                if (mounted)
                                  setState(() => _showPriceInfo = false);
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
                const Text(
                  "+0.11% (\$0.00)",
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(height: 200, child: _buildGraph()),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ["1H", "1D", "1W", "1M", "1Y", "Max"].map((filter) {
                    bool isSelected = _selectedTimeFilter == filter;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedTimeFilter = filter),
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

  // --- FILTER UI & BOTTOM SHEETS ---

  // Modals moved below for clarity, but UI code is now in HistoryTab widget.

  // Filter modals moved to HistoryTab.dart

  // Modal filter logic has been moved to HistoryTab.dart

  Widget _buildHistoryTab() {
    final rawAddress = _controller.text.trim();
    String address = rawAddress;
    if (address.contains(":")) {
      address = address.split(":").last;
    }

    return HistoryTab(address: address, chain: _chain);
  }

  Widget _buildTransactionRow(Map<String, dynamic> tx) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool isReceive = tx['type'] == 'Receive';

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          // Left: Status Icon
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: isReceive
                  ? Colors.greenAccent.withOpacity(0.1)
                  : (isDark
                        ? Colors.white.withOpacity(0.05)
                        : Colors.black.withOpacity(0.05)),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isReceive ? Icons.south_west : Icons.north_east,
              color: isReceive
                  ? Colors.greenAccent
                  : (isDark ? Colors.white70 : Colors.black87),
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          // Center: Title + Subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx['summary'] != null && tx['summary'].isNotEmpty
                      ? tx['summary']
                      : (tx['category'] == "P2P"
                            ? (isReceive ? "Received" : "Sent")
                            : tx['category']),
                  style: GoogleFonts.quicksand(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      isReceive ? "From: " : "To: ",
                      style: GoogleFonts.quicksand(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      _shortenAddress(tx['address']),
                      style: GoogleFonts.quicksand(
                        color: Colors.blueAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Right: Address
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isReceive ? "From" : "To",
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    _shortenAddress(tx['address']),
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.open_in_new, color: Colors.grey, size: 14),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
