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
 
  // ── API Keys ──────────────────────────────────────────────────────────────
  final String moralisApiKey =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJub25jZSI6ImYyMTE4N2MxLTE4NzAtNDU0MC1hYzIwLTc3NTc4NDRhYjFjNCIsIm9yZ0lkIjoiNTEzODg4IiwidXNlcklkIjoiNTI4ODExIiwidHlwZUlkIjoiOTQ2YTI0ZGMtODdkNC00YzNiLTlmN2UtNTQzZjA3MDc2OTAyIiwidHlwZSI6IlBST0pFQ1QiLCJpYXQiOjE3Nzc3Mzg0NzMsImV4cCI6NDkzMzQ5ODQ3M30.MRhG1_u1iLfLPI77pteOnlpyQgvNyaDTzt2hm1hwOZA";
  final String coinGeckoApiKey = "CG-aZWy4YFQ6YGD98ookZCRghDF";
 
  // Solana public RPC (free, no key needed)
  static const String _solanaRpc = "https://api.mainnet-beta.solana.com";
 
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
 
  // ─── CHAIN DETECTION ──────────────────────────────────────────────────────
  String _detectChain(String address) {
    final cleanAddr = address.trim();
    final lowAddr = cleanAddr.toLowerCase();
    final len = cleanAddr.length;
 
    if (lowAddr.startsWith("0x") && len == 42) return "Ethereum";
    if (lowAddr.startsWith("bc1")) return "Bitcoin";
    if (cleanAddr.startsWith("1") && len >= 26 && len <= 34) return "Bitcoin";
    if (cleanAddr.startsWith("3") && len >= 26 && len <= 35) return "Bitcoin";
 
    // Solana: base58, 32–44 chars, no 0x/bc1 prefix
    if (len >= 32 && len <= 44 && !lowAddr.startsWith("0x") && !lowAddr.startsWith("bc1")) {
      return "Solana";
    }
    return "Unknown";
  }
 
  // ─── PRICE HELPERS ────────────────────────────────────────────────────────
  Future<double> _fetchPrice(String coinId) async {
    try {
      final res = await http.get(
        Uri.parse(
            "https://api.coingecko.com/api/v3/simple/price?ids=$coinId&vs_currencies=usd"),
        headers: {"x-cg-demo-api-key": coinGeckoApiKey},
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body[coinId] != null && body[coinId]['usd'] != null) {
          return (body[coinId]['usd'] as num).toDouble();
        }
      }
    } catch (e) {
      debugPrint("Price fetch error for $coinId: $e");
    }
    return 0.0;
  }
 
  Future<void> _fetchCoinGeckoChart(String coinId) async {
    try {
      final res = await http.get(
        Uri.parse(
            "https://api.coingecko.com/api/v3/coins/$coinId/market_chart?vs_currency=usd&days=30&interval=daily"),
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
        if (mounted) setState(() => _chartData = spots);
      }
    } catch (e) {
      debugPrint("CoinGecko chart error: $e");
    }
  }
 
  // ─── MAIN ENTRY POINT ────────────────────────────────────────────────────
  Future<void> fetchWalletData() async {
    final rawAddress = _controller.text.trim();
    String address = rawAddress;
    if (address.contains(":")) address = address.split(":").last;
    if (address.isEmpty) return;
 
    _focusNode.unfocus();
    final detectedChain = _detectChain(address);
 
    setState(() {
      _isLoading = true;
      _hasError = false;
      _chartData = [];
      _chain = detectedChain;
      _balance = "0.00";
      _errorMessage = "Failed to load portfolio data";
    });
 
    debugPrint("Detected chain: $detectedChain for address: $address");
 
    try {
      String coinId = _coinIdForChain(detectedChain);
 
      await Future.wait([
        _fetchBalance(address, detectedChain),
        _fetchCoinGeckoChart(coinId),
        _updatePrice(detectedChain),
      ]);
 
      if (mounted) {
        setState(() {
          _showResults = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
          _errorMessage = "Failed to load data. Check address and try again.";
        });
      }
      debugPrint("fetchWalletData error: $e");
    }
  }
 
  String _coinIdForChain(String chain) {
    switch (chain) {
      case "Solana":   return "solana";
      case "Bitcoin":  return "bitcoin";
      case "Ethereum": return "ethereum";
      default:         return "ethereum";
    }
  }
 
  Future<void> _updatePrice(String chain) async {
    _currentPrice = await _fetchPrice(_coinIdForChain(chain));
  }
 
  // ─── BALANCE FETCHING ────────────────────────────────────────────────────
  Future<void> _fetchBalance(String address, String chain) async {
    if (chain == "Ethereum") {
      await _fetchEvmBalance(address);
    } else if (chain == "Solana") {
      await _fetchSolanaBalance(address);
    } else if (chain == "Bitcoin") {
      await _fetchBitcoinBalance(address);
    }
  }
 
  // ── EVM: native ETH balance via Moralis, multiply by price ────────────────
  Future<void> _fetchEvmBalance(String address) async {
    debugPrint("Fetching EVM balance for $address...");
    try {
      // 1. Fetch native ETH balance
      final nativeRes = await http.get(
        Uri.parse(
            "https://deep-index.moralis.io/api/v2/$address/balance?chain=eth"),
        headers: {"X-API-Key": moralisApiKey, "accept": "application/json"},
      );
 
      double totalUsd = 0.0;
 
      if (nativeRes.statusCode == 200) {
        final nativeData = jsonDecode(nativeRes.body);
        double weiBalance =
            double.tryParse(nativeData['balance']?.toString() ?? "0") ?? 0;
        double ethBalance = weiBalance / 1e18;
 
        if (ethBalance > 0) {
          double ethPrice = await _fetchPrice("ethereum");
          totalUsd += ethBalance * ethPrice;
          debugPrint("ETH balance: $ethBalance × \$$ethPrice = \$$totalUsd");
        }
      } else {
        debugPrint("Native balance status: ${nativeRes.statusCode}");
      }
 
      // 2. Fetch ERC-20 token balances (best-effort; don't block on failure)
      try {
        final tokenRes = await http.get(
          Uri.parse(
              "https://deep-index.moralis.io/api/v2/$address/erc20?chain=eth"),
          headers: {"X-API-Key": moralisApiKey, "accept": "application/json"},
        );
 
        if (tokenRes.statusCode == 200) {
          final List tokens = jsonDecode(tokenRes.body);
 
          // Only price tokens that have a known USD price from CoinGecko
          final Map<String, String> symbolToId = {
            "USDT":  "tether",
            "USDC":  "usd-coin",
            "DAI":   "dai",
            "WBTC":  "wrapped-bitcoin",
            "LINK":  "chainlink",
            "UNI":   "uniswap",
            "AAVE":  "aave",
            "MATIC": "matic-network",
            "BNB":   "binancecoin",
            "SHIB":  "shiba-inu",
            "PEPE":  "pepe",
          };
 
          // Collect unique coin IDs needed
          Set<String> idsNeeded = {};
          List<Map<String, dynamic>> enriched = [];
 
          for (var token in tokens) {
            final int decimals =
                int.tryParse(token['decimals']?.toString() ?? "18") ?? 18;
            final double balance =
                (double.tryParse(token['balance']?.toString() ?? "0") ?? 0) /
                    pow(10, decimals);
            final String symbol =
                (token['symbol']?.toString() ?? "").toUpperCase();
            final String? coinId = symbolToId[symbol];
            if (balance > 0 && coinId != null) {
              idsNeeded.add(coinId);
              enriched.add({"symbol": symbol, "balance": balance, "coinId": coinId});
            }
          }
 
          // Batch price fetch via CoinGecko simple price
          if (idsNeeded.isNotEmpty) {
            final String ids = idsNeeded.join(",");
            final pricesRes = await http.get(
              Uri.parse(
                  "https://api.coingecko.com/api/v3/simple/price?ids=$ids&vs_currencies=usd"),
              headers: {"x-cg-demo-api-key": coinGeckoApiKey},
            );
            if (pricesRes.statusCode == 200) {
              final pricesData = jsonDecode(pricesRes.body);
              for (var item in enriched) {
                final price =
                    (pricesData[item['coinId']]?['usd'] as num?)?.toDouble() ??
                        0.0;
                totalUsd += (item['balance'] as double) * price;
              }
            }
          }
        }
      } catch (e) {
        debugPrint("Token balance error (non-fatal): $e");
      }
 
      if (mounted) {
        setState(() => _balance = totalUsd.toStringAsFixed(2));
      }
    } catch (e) {
      debugPrint("EVM balance error: $e");
      if (mounted) setState(() => _balance = "0.00");
    }
  }
 
  // ── SOLANA: use public JSON-RPC (no API key needed) ───────────────────────
  Future<void> _fetchSolanaBalance(String address) async {
    debugPrint("Fetching Solana balance via RPC for $address...");
    try {
      final res = await http.post(
        Uri.parse(_solanaRpc),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "jsonrpc": "2.0",
          "id": 1,
          "method": "getBalance",
          "params": [address],
        }),
      );
 
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final error = data['error'];
        if (error != null) {
          debugPrint("Solana RPC error: $error");
          if (mounted) setState(() => _balance = "0.00");
          return;
        }
        final lamports = (data['result']?['value'] as num?)?.toDouble() ?? 0;
        final sol = lamports / 1e9;
        debugPrint("SOL balance: $sol");
        final solPrice = await _fetchPrice("solana");
        if (mounted) {
          setState(() => _balance = (sol * solPrice).toStringAsFixed(2));
        }
        return;
      }
    } catch (e) {
      debugPrint("Solana RPC balance error: $e");
    }
    if (mounted) setState(() => _balance = "0.00");
  }
 
  // ── BITCOIN: mempool.space (unchanged, was working) ───────────────────────
  Future<void> _fetchBitcoinBalance(String address) async {
    debugPrint("Fetching Bitcoin balance for $address...");
    try {
      final res = await http.get(
          Uri.parse("https://mempool.space/api/address/$address"));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final chain = data['chain_stats'] ?? {};
        final mem = data['mempool_stats'] ?? {};
        int funded =
            (chain['funded_txo_sum'] ?? 0) + (mem['funded_txo_sum'] ?? 0);
        int spent =
            (chain['spent_txo_sum'] ?? 0) + (mem['spent_txo_sum'] ?? 0);
        double btc = (funded - spent) / 100000000;
        final btcPrice = await _fetchPrice("bitcoin");
        if (mounted) {
          setState(() => _balance = (btc * btcPrice).toStringAsFixed(2));
        }
        return;
      }
    } catch (e) {
      debugPrint("Bitcoin balance error: $e");
    }
    if (mounted) setState(() => _balance = "0.00");
  }
 
  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F7),
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
                  children: const [
                    TextSpan(text: "Track before you "),
                    TextSpan(
                        text: "trust",
                        style: TextStyle(color: Colors.blue)),
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
                  style:
                      TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: const InputDecoration(
                    hintText: "Enter wallet address (ETH, SOL, BTC...)",
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
      return const Center(
          child: CircularProgressIndicator(color: Colors.blue));
    }
 
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_errorMessage,
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 16),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: fetchWalletData,
              icon: const Icon(Icons.refresh),
              label: const Text("Retry"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            ),
          ],
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
              fontSize: 20, fontWeight: FontWeight.bold),
          unselectedLabelStyle: GoogleFonts.quicksand(
              fontSize: 22, fontWeight: FontWeight.w500),
          tabs: const [Tab(text: "Portfolio"), Tab(text: "History")],
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
        child: Text("No chart data available",
            style: TextStyle(color: Colors.grey, fontSize: 14)),
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
          leftTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              getTitlesWidget: (value, meta) {
                if (value == meta.max || value == meta.min) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text("\$${value.toStringAsFixed(0)}",
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 10)),
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
 
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(
        child: Text(symbol,
            style: TextStyle(
                fontSize: size * 0.45,
                color: Colors.white,
                fontWeight: FontWeight.bold)),
      ),
    );
 
    if (url == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: Image.network(url, width: size, height: size,
          errorBuilder: (_, __, ___) => fallback),
    );
  }
 
  Widget _buildPortfolioTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 140),
      physics: const BouncingScrollPhysics(),
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
                    Text("Performance",
                        style: GoogleFonts.quicksand(
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        if (_showPriceInfo)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.grey[850]
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: isDark
                                      ? Colors.white12
                                      : Colors.black12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildChainLogo(size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  "\$${_currentPrice.toStringAsFixed(2)}",
                                  style: GoogleFonts.quicksand(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            setState(
                                () => _showPriceInfo = !_showPriceInfo);
                            if (_showPriceInfo) {
                              Future.delayed(const Duration(seconds: 4),
                                  () {
                                if (mounted) {
                                  setState(
                                      () => _showPriceInfo = false);
                                }
                              });
                            }
                          },
                          child: Icon(Icons.info_outline,
                              color: (isDark ? Colors.white : Colors.black)
                                  .withOpacity(0.5),
                              size: 20),
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
                          fontWeight: FontWeight.bold),
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
                  children:
                      ["1H", "1D", "1W", "1M", "1Y", "Max"].map((filter) {
                    bool isSelected = _selectedTimeFilter == filter;
                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selectedTimeFilter = filter),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
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
    return HistoryTab(address: address, chain: _chain);
  }
}