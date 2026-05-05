import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late TabController _tabController;

  bool _isFocused = false;
  bool _isLoading = false;
  bool _hasError = false;
  bool _showResults = false;

  String _balance = "0.00";
  String _chain = "Ethereum";
  String _errorMessage = "Invalid address or failed to fetch data";
  String _selectedTimeFilter = "1D";

  List<FlSpot> _chartData = [];

  // History Filter State
  List<Map<String, dynamic>> _allTransactions = [];
  Map<String, List<Map<String, dynamic>>> _historyData = {};
  String _historySearchQuery = "";
  DateTime? _historyFilterDate;
  String _historyFilterType = "All";
  String _historyFilterDirection = "All";

  final String moralisApiKey =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJub25jZSI6ImYyMTE4N2MxLTE4NzAtNDU0MC1hYzIwLTc3NTc4NDRhYjFjNCIsIm9yZ0lkIjoiNTEzODg4IiwidXNlcklkIjoiNTI4ODExIiwidHlwZUlkIjoiOTQ2YTI0ZGMtODdkNC00YzNiLTlmN2UtNTQzZjA3MDc2OTAyIiwidHlwZSI6IlBST0pFQ1QiLCJpYXQiOjE3Nzc3Mzg0NzMsImV4cCI6NDkzMzQ5ODQ3M30.MRhG1_u1iLfLPI77pteOnlpyQgvNyaDTzt2hm1hwOZA";
  final String covalentApiKey = "YOUR_COVALENT_API_KEY";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _focusNode.addListener(() {
      setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _tabController.dispose();
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
    final len = address.length;

    // EVM: unambiguous — 0x prefix + exactly 40 hex chars
    if (address.startsWith("0x") && len == 42) return "Ethereum";

    // Bitcoin bech32 (native segwit): bc1 prefix — unambiguous
    if (address.startsWith("bc1")) return "Bitcoin";

    // Solana: ALWAYS 44 chars, Base58, no 0x — check this BEFORE BTC prefix rules
    // because SOL addresses can start with 1, 2, 3, etc.
    if (len == 44 && !address.startsWith("0x")) return "Solana";

    // Solana can rarely be 43 chars — still check before BTC prefix
    if (len == 43 && !address.startsWith("0x")) return "Solana";

    // Bitcoin legacy (P2PKH): starts with 1, length 26-34
    if (address.startsWith("1") && len >= 26 && len <= 34) return "Bitcoin";

    // Bitcoin P2SH: starts with 3, length 26-35
    if (address.startsWith("3") && len >= 26 && len <= 35) return "Bitcoin";

    // Any remaining Base58 32-50 chars — treat as Solana
    if (!address.startsWith("0x") && len >= 32 && len <= 50) return "Solana";

    return "Unknown";
  }

  // ─── PRICE HELPERS ─────────────────────────────────────────────────────────
  Future<double> _fetchPrice(String coinId) async {
    try {
      final res = await http.get(
        Uri.parse(
          "https://api.coingecko.com/api/v3/simple/price?ids=$coinId&vs_currencies=usd",
        ),
      );
      if (res.statusCode == 200) {
        return (jsonDecode(res.body)[coinId]['usd'] as num).toDouble();
      }
    } catch (_) {}
    return 0.0;
  }

  // ─── MAIN ENTRY POINT ──────────────────────────────────────────────────────
  Future<void> fetchWalletData() async {
    final address = _controller.text.trim();
    if (address.isEmpty) return;

    _focusNode.unfocus();
    final detectedChain = _detectChain(address);

    setState(() {
      _isLoading = true;
      _hasError = false;
      _showResults = false;
      _chartData = [];
      _allTransactions = [];
      _historyData = {};
      _chain = detectedChain;
      _balance = "0.00";
      _errorMessage = "Failed to load portfolio data";
    });

    try {
      await _fetchBalance(address, detectedChain);
      await _fetchTransactions(address, detectedChain);
      await _fetchCovalentGraph(address, 1);

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
    // Try unified Net Worth API first (most accurate)
    try {
      final res = await http.get(
        Uri.parse(
          "https://deep-index.moralis.io/api/v2.2/wallets/$address/net-worth",
        ),
        headers: {"X-API-Key": moralisApiKey, "accept": "application/json"},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        double nw =
            double.tryParse(data['total_networth_usd']?.toString() ?? "0") ?? 0;
        if (nw > 0) {
          _balance = nw.toStringAsFixed(2);
          return;
        }
      }
    } catch (e) {
      debugPrint("Net Worth API error: $e");
    }

    // Fallback: aggregate ETH balance from all EVM chains
    double totalEth = 0;
    for (var chain in [
      "eth",
      "polygon",
      "bsc",
      "arbitrum",
      "optimism",
      "base",
    ]) {
      try {
        final res = await http.get(
          Uri.parse(
            "https://deep-index.moralis.io/api/v2.2/$address/balance?chain=$chain",
          ),
          headers: {"X-API-Key": moralisApiKey, "accept": "application/json"},
        );
        if (res.statusCode == 200) {
          totalEth +=
              (double.tryParse(
                    jsonDecode(res.body)['balance']?.toString() ?? "0",
                  ) ??
                  0) /
              1e18;
        }
      } catch (_) {}
    }
    final ethPrice = await _fetchPrice("ethereum");
    _balance = (totalEth * ethPrice).toStringAsFixed(2);
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

  // ─── TRANSACTION FETCHING ──────────────────────────────────────────────────
  Future<void> _fetchTransactions(String address, String chain) async {
    List<Map<String, dynamic>> tempTxs = [];

    try {
      if (chain == "Bitcoin") {
        tempTxs = await _fetchBitcoinTxs(address);
      } else if (chain == "Solana") {
        tempTxs = await _fetchSolanaTxs(address);
      } else if (chain == "Ethereum") {
        tempTxs = await _fetchEvmTxs(address);
      }
    } catch (e) {
      debugPrint("Transaction fetch error: $e");
    }

    tempTxs.sort(
      (a, b) => (b['rawDate'] as DateTime).compareTo(a['rawDate'] as DateTime),
    );
    _allTransactions = tempTxs;
    _applyFilters();
  }

  Future<List<Map<String, dynamic>>> _fetchBitcoinTxs(String address) async {
    List<Map<String, dynamic>> txs = [];
    try {
      final res = await http.get(
        Uri.parse("https://mempool.space/api/address/$address/txs"),
      );
      if (res.statusCode != 200) return txs;
      final data = jsonDecode(res.body) as List? ?? [];

      for (var tx in data) {
        int vinSum = 0, voutSum = 0;
        for (var vin in (tx['vin'] as List? ?? [])) {
          if (vin['prevout']?['scriptpubkey_address'] == address) {
            vinSum += (vin['prevout']?['value'] ?? 0) as int;
          }
        }
        for (var vout in (tx['vout'] as List? ?? [])) {
          if (vout['scriptpubkey_address'] == address) {
            voutSum += (vout['value'] ?? 0) as int;
          }
        }

        int net = voutSum - vinSum;
        if (net == 0) continue;

        double amount = net / 100000000;
        bool isReceive = net > 0;
        int blockTime = tx['status']?['block_time'] ?? 0;
        DateTime time = blockTime > 0
            ? DateTime.fromMillisecondsSinceEpoch(blockTime * 1000)
            : DateTime.now();

        txs.add({
          "rawDate": time,
          "category": "P2P",
          "type": isReceive ? "Receive" : "Send",
          "time": _formatTime(time),
          "amountCrypto":
              "${isReceive ? '+' : ''}${amount.toStringAsFixed(6)} BTC",
          "amountFiat": "\$0.00",
          "address": isReceive ? "External Address" : "External Address",
          "tokenSymbol": "BTC",
        });
      }
    } catch (e) {
      debugPrint("Bitcoin TX error: $e");
    }
    return txs;
  }

  Future<List<Map<String, dynamic>>> _fetchSolanaTxs(String address) async {
    List<Map<String, dynamic>> txs = [];
    try {
      final res = await http.get(
        Uri.parse(
          "https://solana-gateway.moralis.io/account/mainnet/$address/transactions",
        ),
        headers: {"X-API-Key": moralisApiKey, "accept": "application/json"},
      );
      if (res.statusCode != 200) return txs;

      final data = jsonDecode(res.body);
      final list = data is List ? data : (data['result'] as List? ?? []);

      for (var tx in list) {
        // Parse native SOL transfers
        final nativeTransfers = tx['nativeTransfers'] as List? ?? [];
        for (var transfer in nativeTransfers) {
          double amount =
              (double.tryParse(transfer['amount']?.toString() ?? "0") ?? 0) /
              1e9;
          if (amount <= 0) continue;
          String from = transfer['from']?.toString() ?? "";
          String to = transfer['to']?.toString() ?? "";
          bool isReceive = to == address;

          // Parse timestamp - Moralis returns Unix seconds
          int blockTime = tx['blockTime'] ?? tx['block_time'] ?? 0;
          DateTime time = blockTime > 0
              ? DateTime.fromMillisecondsSinceEpoch(blockTime * 1000)
              : DateTime.now();

          txs.add({
            "rawDate": time,
            "category": "P2P",
            "type": isReceive ? "Receive" : "Send",
            "time": _formatTime(time),
            "amountCrypto":
                "${isReceive ? '+' : '-'}${amount.toStringAsFixed(4)} SOL",
            "amountFiat": "\$0.00",
            "address": isReceive ? from : to,
            "tokenSymbol": "SOL",
          });
        }
      }
    } catch (e) {
      debugPrint("Solana TX error: $e");
    }
    return txs;
  }

  Future<List<Map<String, dynamic>>> _fetchEvmTxs(String address) async {
    List<Map<String, dynamic>> txs = [];
    final chains = ["eth", "polygon", "bsc", "arbitrum", "optimism", "base"];

    List<Future<List<Map<String, dynamic>>>> futures = chains.map((
      chain,
    ) async {
      List<Map<String, dynamic>> chainTxs = [];
      try {
        final res = await http.get(
          Uri.parse(
            "https://deep-index.moralis.io/api/v2.2/$address/transactions?chain=$chain&limit=25",
          ),
          headers: {"X-API-Key": moralisApiKey, "accept": "application/json"},
        );
        if (res.statusCode != 200) return chainTxs;

        final data = jsonDecode(res.body);
        final results = data['result'] as List? ?? [];

        for (var tx in results) {
          String from = tx['from_address']?.toString() ?? "";
          String to = tx['to_address']?.toString() ?? "";
          double value =
              (double.tryParse(tx['value']?.toString() ?? "0") ?? 0) / 1e18;
          bool isReceive = to.toLowerCase() == address.toLowerCase();
          DateTime time =
              DateTime.tryParse(tx['block_timestamp'] ?? "") ?? DateTime.now();

          String input = tx['input']?.toString() ?? "0x";
          String category = "Smart Contract Interactions";
          if (input == "0x" || input.isEmpty)
            category = "P2P";
          else if (input.startsWith("0x095ea7b3"))
            category = "Approvals";
          else if (input.startsWith("0x38ed1739") ||
              input.startsWith("0x7ff36ab5") ||
              input.startsWith("0x5c11d795"))
            category = "Swaps";
          else if (input.startsWith("0x23b872dd") ||
              input.startsWith("0x42842e0e"))
            category = "NFT";

          chainTxs.add({
            "rawDate": time,
            "category": category,
            "type": isReceive ? "Receive" : "Send",
            "time": _formatTime(time),
            "amountCrypto":
                "${isReceive ? '+' : '-'}${value.toStringAsFixed(4)} ${chain.toUpperCase()}",
            "amountFiat": "\$0.00",
            "address": isReceive ? from : to,
            "tokenSymbol": chain == "eth"
                ? "ETH"
                : chain == "polygon"
                ? "MATIC"
                : chain == "bsc"
                ? "BNB"
                : chain.toUpperCase(),
          });
        }
      } catch (e) {
        debugPrint("EVM TX error ($chain): $e");
      }
      return chainTxs;
    }).toList();

    final results = await Future.wait(futures);
    for (var r in results) txs.addAll(r);
    return txs;
  }

  // ─── LEGACY WRAPPER (kept for compatibility) ───────────────────────────────
  Future<void> _fetchMoralisData(String address) async {}
  Future<void> _fetchMoralisTransactions(
    String address,
    bool isSolana,
    bool isBitcoin,
    bool isEVM, {
    Map<String, dynamic>? btcData,
  }) async {}

  // ─── FILTER LOGIC ──────────────────────────────────────────────────────────
  void _applyFilters() {
    List<Map<String, dynamic>> filtered = _allTransactions.where((tx) {
      if (_historySearchQuery.isNotEmpty) {
        String q = _historySearchQuery.toLowerCase();
        bool matchesAddress = (tx['address'] ?? "").toLowerCase().contains(q);
        bool matchesToken = (tx['tokenSymbol'] ?? "").toLowerCase().contains(q);
        if (!matchesAddress && !matchesToken) return false;
      }
      if (_historyFilterDate != null) {
        DateTime txDate = tx['rawDate'] as DateTime;
        if (txDate.year != _historyFilterDate!.year ||
            txDate.month != _historyFilterDate!.month ||
            txDate.day != _historyFilterDate!.day)
          return false;
      }
      if (_historyFilterType != "All") {
        if (tx['category'] != _historyFilterType) return false;
      }
      if (_historyFilterDirection != "All") {
        if (_historyFilterDirection == "Sent" && tx['type'] == "Receive")
          return false;
        if (_historyFilterDirection == "Received" && tx['type'] == "Send")
          return false;
      }
      return true;
    }).toList();

    Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var tx in filtered) {
      String dateStr = _formatDate(tx['rawDate']);
      grouped.putIfAbsent(dateStr, () => []).add(tx);
    }

    setState(() {
      _historyData = grouped;
    });
  }

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
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: const TextSpan(
            style: TextStyle(
              fontSize: 35,
              fontWeight: FontWeight.bold,
              color: Colors.white,
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
        const Text(
          "Enter a wallet address to track portfolio and transactions",
          style: TextStyle(color: Colors.grey, fontSize: 18),
        ),
      ],
    );
  }

  Widget _buildGlassSearchBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 60,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: _isFocused ? Colors.blue : Colors.white.withOpacity(0.1),
              width: _isFocused ? 2 : 1,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.2),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
          child: Row(
            children: [
              const SizedBox(width: 20),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: "Paste wallet address (ETH, SOL...)",
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
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_upward, color: Colors.black),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
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
      return const Center(
        child: Text(
          "Enter a wallet address to begin tracking",
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          dividerColor: Colors.white12,
          labelStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 20,
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
          getDrawingHorizontalLine: (value) =>
              FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
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

  Widget _buildChainLogo() {
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
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(
        child: Text(
          symbol,
          style: const TextStyle(
            fontSize: 16,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );

    if (url == null) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Image.network(
        url,
        width: 36,
        height: 36,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }

  Widget _buildPortfolioTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 120),
      physics: const BouncingScrollPhysics(),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Performance",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Icon(
                  Icons.info_outline,
                  color: Colors.white.withOpacity(0.5),
                  size: 18,
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
                  style: const TextStyle(
                    color: Colors.white,
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
            const SizedBox(height: 32),
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
                          ? const Color(0xFF2A2A2A)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      filter,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey,
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
    );
  }

  // --- FILTER UI & BOTTOM SHEETS ---

  Widget _buildHistoryFilters() {
    return Column(
      children: [
        // Search Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: TextField(
            onChanged: (val) {
              _historySearchQuery = val;
              _applyFilters();
            },
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              icon: Icon(Icons.search, color: Colors.grey, size: 24),
              hintText: "Search address, protocol, asset...",
              hintStyle: TextStyle(color: Colors.grey, fontSize: 18),
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Filter Row
        Row(
          children: [
            _buildFilterButton(
              "Search by date",
              _historyFilterDate != null
                  ? _formatDate(_historyFilterDate!)
                  : null,
              _showDateFilterModal,
            ),
            const SizedBox(width: 8),
            _buildFilterButton(
              "Type",
              _historyFilterType == "All" ? null : _historyFilterType,
              _showTypeFilterModal,
            ),
            const SizedBox(width: 8),
            _buildFilterButton(
              "Direction",
              _historyFilterDirection == "All" ? null : _historyFilterDirection,
              _showDirectionFilterModal,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterButton(
    String defaultText,
    String? selectedText,
    VoidCallback onTap,
  ) {
    bool isSelected = selectedText != null;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.blue.withOpacity(0.2)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.white.withOpacity(0.1),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  isSelected ? selectedText : defaultText,
                  style: TextStyle(
                    color: isSelected ? Colors.blue : Colors.grey,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down,
                color: isSelected ? Colors.blue : Colors.grey,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDateFilterModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text(
                      "All Dates",
                      style: TextStyle(color: Colors.white),
                    ),
                    leading: Icon(
                      _historyFilterDate == null
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: _historyFilterDate == null
                          ? Colors.blue
                          : Colors.grey,
                    ),
                    onTap: () {
                      setState(() {
                        _historyFilterDate = null;
                        _applyFilters();
                      });
                      Navigator.pop(context);
                    },
                  ),
                  const Divider(color: Colors.white12),
                  SizedBox(
                    height: 300,
                    child: Theme(
                      data: ThemeData.dark().copyWith(
                        colorScheme: const ColorScheme.dark(
                          primary: Colors.blue,
                          onPrimary: Colors.white,
                          surface: Color(0xFF1E1E1E),
                          onSurface: Colors.white,
                        ),
                      ),
                      child: CalendarDatePicker(
                        initialDate: _historyFilterDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                        onDateChanged: (date) {
                          setState(() {
                            _historyFilterDate = date;
                            _applyFilters();
                          });
                          Navigator.pop(context);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showTypeFilterModal() {
    final types = [
      "All",
      "P2P",
      "Swaps",
      "NFT",
      "Approvals",
      "Smart Contract Interactions",
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: types.map((type) {
              return ListTile(
                title: Text(type, style: const TextStyle(color: Colors.white)),
                leading: Icon(
                  _historyFilterType == type
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: _historyFilterType == type ? Colors.blue : Colors.grey,
                ),
                onTap: () {
                  setState(() {
                    _historyFilterType = type;
                    _applyFilters();
                  });
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showDirectionFilterModal() {
    final directions = ["All", "Sent", "Received"];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: directions.map((dir) {
              return ListTile(
                title: Text(dir, style: const TextStyle(color: Colors.white)),
                leading: Icon(
                  _historyFilterDirection == dir
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: _historyFilterDirection == dir
                      ? Colors.blue
                      : Colors.grey,
                ),
                onTap: () {
                  setState(() {
                    _historyFilterDirection = dir;
                    _applyFilters();
                  });
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildHistoryTab() {
    return Column(
      children: [
        _buildHistoryFilters(),
        const SizedBox(height: 16),
        Expanded(
          child: _historyData.isEmpty && _allTransactions.isEmpty
              ? const Center(
                  child: Text(
                    "No transactions found",
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : _historyData.isEmpty
              ? const Center(
                  child: Text(
                    "No transactions match your filters",
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 120),
                  physics: const BouncingScrollPhysics(),
                  itemCount: _historyData.keys.length,
                  itemBuilder: (context, index) {
                    String dateKey = _historyData.keys.elementAt(index);
                    List<Map<String, dynamic>> transactions =
                        _historyData[dateKey]!;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dateKey,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...transactions
                              .map((tx) => _buildTransactionRow(tx))
                              .toList(),
                          const Divider(color: Colors.white12, height: 1),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTransactionRow(Map<String, dynamic> tx) {
    bool isReceive = tx['type'] == 'Receive';
    String cryptoSymbol =
        tx['tokenSymbol'] ??
        (_chain == "Solana" ? "SOL" : (_chain == "Bitcoin" ? "BTC" : "ETH"));
    String iconUrl = _chain == "Solana"
        ? "https://cryptologos.cc/logos/solana-sol-logo.png"
        : _chain == "Bitcoin"
        ? "https://cryptologos.cc/logos/bitcoin-btc-logo.png"
        : "https://cryptologos.cc/logos/ethereum-eth-logo.png";

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Icon + Time
          Column(
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: Icon(
                  isReceive ? Icons.arrow_downward : Icons.arrow_upward,
                  color: isReceive ? Colors.greenAccent : Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tx['time'],
                style: const TextStyle(color: Colors.grey, fontSize: 10),
              ),
              const SizedBox(height: 2),
              Text(
                tx['category'],
                style: const TextStyle(color: Colors.blueAccent, fontSize: 8),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          const SizedBox(width: 16),
          // Center: Token + Amount
          Expanded(
            child: Row(
              children: [
                Image.network(
                  iconUrl,
                  width: 20,
                  height: 20,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.circle, size: 20, color: Colors.blue),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${tx['amountCrypto']} $cryptoSymbol",
                      style: TextStyle(
                        color: isReceive ? Colors.greenAccent : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tx['amountFiat'],
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
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
                    style: const TextStyle(color: Colors.white, fontSize: 14),
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
