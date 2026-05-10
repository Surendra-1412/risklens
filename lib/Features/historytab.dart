import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:math';
 
class HistoryTab extends StatefulWidget {
  final String address;
  final String chain;
 
  const HistoryTab({
    super.key,
    required this.address,
    required this.chain,
  });
 
  @override
  State<HistoryTab> createState() => _HistoryTabState();
}
 
class _HistoryTabState extends State<HistoryTab> {
  // ── API Keys ──────────────────────────────────────────────────────────────
  // Use the FULL key (with typeId) from ledgerscreen.dart
  static const String _moralisApiKey =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJub25jZSI6ImYyMTE4N2MxLTE4NzAtNDU0MC1hYzIwLTc3NTc4NDRhYjFjNCIsIm9yZ0lkIjoiNTEzODg4IiwidXNlcklkIjoiNTI4ODExIiwidHlwZUlkIjoiOTQ2YTI0ZGMtODdkNC00YzNiLTlmN2UtNTQzZjA3MDc2OTAyIiwidHlwZSI6IlBST0pFQ1QiLCJpYXQiOjE3Nzc3Mzg0NzMsImV4cCI6NDkzMzQ5ODQ3M30.MRhG1_u1iLfLPI77pteOnlpyQgvNyaDTzt2hm1hwOZA";
  static const String _coinGeckoApiKey = "CG-aZWy4YFQ6YGD98ookZCRghDF";
 
  // Public Solana RPC — free, no API key required
  static const String _solanaRpc = "https://api.mainnet-beta.solana.com";
 
  bool _isLoading = true;
  String _statusMessage = "Loading transactions...";
  List<Map<String, dynamic>> _allTransactions = [];
  Map<String, List<Map<String, dynamic>>> _groupedTransactions = {};
  Map<String, double> _tokenPrices = {};
 
  // Filters
  DateTime? _selectedDate;
  String _selectedDirection = "All"; // "All" | "Received" | "Sent"
 
  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }
 
  @override
  void didUpdateWidget(HistoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.address != widget.address ||
        oldWidget.chain != widget.chain) {
      _fetchHistory();
    }
  }
 
  // ─── FETCH DISPATCHER ────────────────────────────────────────────────────
  Future<void> _fetchHistory() async {
    if (widget.address.isEmpty) {
      setState(() {
        _isLoading = false;
        _statusMessage = "No address provided";
      });
      return;
    }
 
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _statusMessage = "Fetching ${widget.chain} history…";
      _allTransactions = [];
      _groupedTransactions = {};
    });
 
    try {
      switch (widget.chain) {
        case "Solana":
          await _fetchSolanaHistory();
          break;
        case "Bitcoin":
          await _fetchBitcoinHistory();
          break;
        default:
          await _fetchEvmHistory();
      }
    } catch (e) {
      debugPrint("fetchHistory error: $e");
      if (mounted) setState(() => _statusMessage = "Error: $e");
    }
 
    if (!mounted) return;
    await _fetchTokenPrices();
    if (!mounted) return;
    _applyFilters();
    setState(() {
      _isLoading = false;
      if (_allTransactions.isEmpty) {
        _statusMessage = "No transactions found for this address.";
      } else {
        _statusMessage = "Loaded ${_allTransactions.length} transactions";
      }
    });
  }
 
  // ─── SOLANA via JSON-RPC (no Moralis, no 404) ────────────────────────────
  Future<void> _fetchSolanaHistory() async {
    debugPrint("Fetching Solana history via RPC for ${widget.address}");
    if (!mounted) return;
    setState(() => _statusMessage = "Fetching Solana signatures…");

    try {
      // Step 1: get recent signatures
      final sigRes = await http.post(
        Uri.parse(_solanaRpc),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "jsonrpc": "2.0",
          "id": 1,
          "method": "getSignaturesForAddress",
          "params": [
            widget.address,
            {"limit": 25, "commitment": "finalized"}
          ],
        }),
      );

      if (sigRes.statusCode != 200) {
        if (mounted) {
          setState(() =>
              _statusMessage = "Solana RPC error: ${sigRes.statusCode}");
        }
        return;
      }

      final sigBody = jsonDecode(sigRes.body);
      if (sigBody['error'] != null) {
        if (mounted) {
          setState(
              () => _statusMessage = "RPC Error: ${sigBody['error']['message']}");
        }
        return;
      }

      final List sigs = sigBody['result'] ?? [];
      if (sigs.isEmpty) {
        if (mounted) setState(() => _statusMessage = "No transactions found.");
        return;
      }

      debugPrint("Got ${sigs.length} signatures, fetching details…");
      if (mounted) {
        setState(
            () => _statusMessage = "Loading ${sigs.length} transactions…");
      }

      // Step 2: Batch getTransaction requests
      final List<Map<String, dynamic>> batch = sigs.take(25).map((sig) {
        return {
          "jsonrpc": "2.0",
          "id": sig['signature'],
          "method": "getTransaction",
          "params": [
            sig['signature'],
            {
              "encoding": "jsonParsed",
              "maxSupportedTransactionVersion": 0,
              "commitment": "finalized"
            }
          ],
        };
      }).toList();

      final txRes = await http.post(
        Uri.parse(_solanaRpc),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(batch),
      );

      if (txRes.statusCode != 200) {
        if (mounted) {
          setState(
              () => _statusMessage = "TX fetch error: ${txRes.statusCode}");
        }
        return;
      }

      final List txResults = jsonDecode(txRes.body);
      final List<Map<String, dynamic>> parsed = [];

      for (final result in txResults) {
        if (result == null || result['result'] == null) continue;
        final tx = result['result'] as Map<String, dynamic>;
        final sig = result['id'] as String;

        final blockTime = tx['blockTime'] as int? ?? 0;
        final timestamp = blockTime > 0
            ? DateTime.fromMillisecondsSinceEpoch(blockTime * 1000)
            : DateTime.now();

        // Parse from meta + accountKeys
        final meta = tx['meta'] as Map<String, dynamic>? ?? {};
        final List preBalances = meta['preBalances'] as List? ?? [];
        final List postBalances = meta['postBalances'] as List? ?? [];
        
        final transaction = tx['transaction'] as Map<String, dynamic>? ?? {};
        final message = transaction['message'] as Map<String, dynamic>? ?? {};
        final List accountKeys = message['accountKeys'] as List? ?? [];

        // Find index of our address
        int myIdx = -1;
        for (int i = 0; i < accountKeys.length; i++) {
          final key = accountKeys[i];
          final String pubkey =
              key is Map ? (key['pubkey']?.toString() ?? '') : key.toString();
          // Use exact matching for Solana
          if (pubkey == widget.address) {
            myIdx = i;
            break;
          }
        }

        if (myIdx < 0 ||
            myIdx >= preBalances.length ||
            myIdx >= postBalances.length) continue;

        final double pre = (preBalances[myIdx] as num).toDouble();
        final double post = (postBalances[myIdx] as num).toDouble();
        final double diff = post - pre;
        final double value = diff.abs() / 1e9;

        // Even for 0-value SOL, it might be an interesting transaction
        // But for clarity, we mostly show transfers
        String from = "Unknown";
        String to = "Unknown";

        if (diff > 0) {
          // User received SOL
          to = widget.address;
          for (int i = 0; i < accountKeys.length; i++) {
            if (i == myIdx) continue;
            if (i >= preBalances.length || i >= postBalances.length) continue;
            if ((postBalances[i] as num) < (preBalances[i] as num)) {
              final key = accountKeys[i];
              from = key is Map
                  ? (key['pubkey']?.toString() ?? 'Unknown')
                  : key.toString();
              break;
            }
          }
        } else if (diff < 0) {
          // User sent SOL
          from = widget.address;
          for (int i = 0; i < accountKeys.length; i++) {
            if (i == myIdx) continue;
            if (i >= preBalances.length || i >= postBalances.length) continue;
            if ((postBalances[i] as num) > (preBalances[i] as num)) {
              final key = accountKeys[i];
              to = key is Map
                  ? (key['pubkey']?.toString() ?? 'Unknown')
                  : key.toString();
              break;
            }
          }
        } else {
          // interaction / 0 SOL change
          from = widget.address;
          to = "Contract Interaction";
        }

        parsed.add({
          "from": from,
          "to": to,
          "value": value,
          "symbol": "SOL",
          "timestamp": timestamp,
          "hash": sig,
        });
      }

      debugPrint("Successfully parsed ${parsed.length} Solana transactions");
      _allTransactions = parsed;
    } catch (e) {
      debugPrint("Solana history logic error: $e");
      if (mounted) setState(() => _statusMessage = "Error parsing Solana history");
    }
  }
 
  // ─── EVM via Moralis ─────────────────────────────────────────────────────
  Future<void> _fetchEvmHistory() async {
    final chain = _getMoralisChainCode(widget.chain);
    const baseUrl = "https://deep-index.moralis.io/api/v2";
    final headers = {
      "X-API-Key": _moralisApiKey,
      "accept": "application/json",
    };
 
    debugPrint(
        "Fetching EVM history: chain=$chain address=${widget.address}");
 
    try {
      final results = await Future.wait([
        http.get(
            Uri.parse("$baseUrl/${widget.address}?chain=$chain"),
            headers: headers),
        http.get(
            Uri.parse(
                "$baseUrl/${widget.address}/erc20/transfers?chain=$chain"),
            headers: headers),
      ]);
 
      final nativeRes = results[0];
      final erc20Res = results[1];
 
      debugPrint(
          "Native: ${nativeRes.statusCode}, ERC20: ${erc20Res.statusCode}");
 
      final List<Map<String, dynamic>> combined = [];
 
      // Native ETH transactions
      if (nativeRes.statusCode == 200) {
        final data = jsonDecode(nativeRes.body);
        final List txs = data['result'] ?? [];
        for (var tx in txs) {
          final from = tx['from_address']?.toString() ?? "";
          final to = tx['to_address']?.toString() ?? "";
          final value =
              double.tryParse(tx['value']?.toString() ?? "0") ?? 0;
          final ts =
              DateTime.tryParse(tx['block_timestamp'] ?? "") ?? DateTime.now();
          final double eth = value / 1e18;
          // We include all transactions, even 0 ETH ones (interactions)
          combined.add({
            "from": from,
            "to": to,
            "value": eth,
            "symbol": _getChainSymbol(widget.chain),
            "timestamp": ts,
            "hash": tx['hash'] ?? "",
          });
        }
      }
 
      // ERC-20 transfers
      if (erc20Res.statusCode == 200) {
        final data = jsonDecode(erc20Res.body);
        final List txs = data['result'] ?? [];
        for (var tx in txs) {
          final from = tx['from_address']?.toString() ?? "";
          final to = tx['to_address']?.toString() ?? "";
          final raw = double.tryParse(tx['value']?.toString() ?? "0") ?? 0;
          final int dec =
              int.tryParse(tx['token_decimals']?.toString() ?? "18") ?? 18;
          final String sym =
              tx['token_symbol']?.toString() ?? "ERC20";
          final ts = DateTime.tryParse(tx['block_timestamp'] ?? "") ??
              DateTime.now();
          final double amount = raw / pow(10, dec);
          // Include all token transfers
          combined.add({
            "from": from,
            "to": to,
            "value": amount,
            "symbol": sym,
            "timestamp": ts,
            "hash": tx['transaction_hash'] ?? "",
          });
        }
      }
 
      // Sort newest first
      combined.sort((a, b) {
        final DateTime ta = a['timestamp'];
        final DateTime tb = b['timestamp'];
        return tb.compareTo(ta);
      });
 
      _allTransactions = combined;
      debugPrint("EVM combined: ${combined.length} transactions");
    } catch (e) {
      debugPrint("EVM history error: $e");
      if (mounted) setState(() => _statusMessage = "EVM error: $e");
    }
  }
 
  // ─── BITCOIN via mempool.space ────────────────────────────────────────────
  Future<void> _fetchBitcoinHistory() async {
    debugPrint("Fetching Bitcoin history for ${widget.address}");
    try {
      final res = await http.get(
          Uri.parse("https://mempool.space/api/address/${widget.address}/txs"));
 
      if (res.statusCode != 200) {
        setState(
            () => _statusMessage = "Bitcoin API error: ${res.statusCode}");
        return;
      }
 
      final List results = jsonDecode(res.body);
      debugPrint("Bitcoin raw txs: ${results.length}");
 
      _allTransactions = results.map((tx) {
        final status = tx['status'] as Map? ?? {};
        final blockTime = status['block_time'] as int? ?? 0;
        final timestamp = blockTime > 0
            ? DateTime.fromMillisecondsSinceEpoch(blockTime * 1000)
            : DateTime.now();
 
        int vinSum = 0, voutSum = 0;
        for (var vin in (tx['vin'] as List? ?? [])) {
          if (vin['prevout']?['scriptpubkey_address'] == widget.address) {
            vinSum += (vin['prevout']?['value'] ?? 0) as int;
          }
        }
        for (var vout in (tx['vout'] as List? ?? [])) {
          if (vout['scriptpubkey_address'] == widget.address) {
            voutSum += (vout['value'] ?? 0) as int;
          }
        }
 
        final int net = voutSum - vinSum;
        return {
          "from": net < 0 ? widget.address : "External",
          "to": net > 0 ? widget.address : "External",
          "value": net.abs() / 1e8,
          "symbol": "BTC",
          "timestamp": timestamp,
          "hash": tx['txid'] ?? "",
        };
      }).toList();
    } catch (e) {
      debugPrint("Bitcoin history error: $e");
      if (mounted) setState(() => _statusMessage = "Bitcoin error: $e");
    }
  }
 
  // ─── TOKEN PRICES ─────────────────────────────────────────────────────────
  Future<void> _fetchTokenPrices() async {
    final symbols =
        _allTransactions.map((tx) => tx['symbol'].toString()).toSet();
    if (symbols.isEmpty) return;
 
    const Map<String, String> symbolToId = {
      "ETH":   "ethereum",
      "SOL":   "solana",
      "BTC":   "bitcoin",
      "MATIC": "matic-network",
      "BNB":   "binancecoin",
      "USDT":  "tether",
      "USDC":  "usd-coin",
      "DAI":   "dai",
      "WBTC":  "wrapped-bitcoin",
      "LINK":  "chainlink",
      "UNI":   "uniswap",
      "AAVE":  "aave",
      "SHIB":  "shiba-inu",
    };
 
    final ids = symbols
        .where((s) => symbolToId.containsKey(s.toUpperCase()))
        .map((s) => symbolToId[s.toUpperCase()]!)
        .toSet();
 
    if (ids.isEmpty) return;
 
    try {
      final res = await http.get(
        Uri.parse(
            "https://api.coingecko.com/api/v3/simple/price?ids=${ids.join(',')}&vs_currencies=usd"),
        headers: {"x-cg-demo-api-key": _coinGeckoApiKey},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final Map<String, double> prices = {};
        for (var sym in symbols) {
          final id = symbolToId[sym.toUpperCase()];
          if (id != null && data[id] != null) {
            prices[sym] = (data[id]['usd'] as num).toDouble();
          }
        }
        if (mounted) setState(() => _tokenPrices = prices);
      }
    } catch (e) {
      debugPrint("Token price error: $e");
    }
  }
 
  // ─── HELPERS ──────────────────────────────────────────────────────────────
  String _getMoralisChainCode(String chain) {
    switch (chain.toLowerCase()) {
      case "ethereum": return "eth";
      case "polygon":  return "polygon";
      case "bsc":      return "bsc";
      case "arbitrum": return "arbitrum";
      case "optimism": return "optimism";
      case "base":     return "base";
      default:         return "eth";
    }
  }
 
  String _getChainSymbol(String chain) {
    switch (chain.toLowerCase()) {
      case "ethereum": return "ETH";
      case "polygon":  return "MATIC";
      case "bsc":      return "BNB";
      case "arbitrum": return "ETH";
      case "optimism": return "ETH";
      case "base":     return "ETH";
      default:         return "ETH";
    }
  }
 
  String _shortenAddress(String addr) {
    if (addr == "Unknown" || addr == "External") return addr;
    if (addr.length < 12) return addr;
    return "${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}";
  }
 
  // ─── FILTERING & GROUPING ────────────────────────────────────────────────
  void _applyFilters() {
    final filtered = _allTransactions.where((tx) {
      // Date filter
      if (_selectedDate != null) {
        final d = tx['timestamp'] as DateTime;
        if (d.year != _selectedDate!.year ||
            d.month != _selectedDate!.month ||
            d.day != _selectedDate!.day) return false;
      }
      // Direction filter
      final isReceive =
          tx['to'].toString().toLowerCase() == widget.address.toLowerCase();
      if (_selectedDirection == "Received" && !isReceive) return false;
      if (_selectedDirection == "Sent" && isReceive) return false;
      return true;
    }).toList();
 
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var tx in filtered) {
      final label =
          DateFormat('MMMM d, yyyy').format(tx['timestamp'] as DateTime);
      grouped.putIfAbsent(label, () => []).add(tx);
    }
    if (mounted) setState(() => _groupedTransactions = grouped);
  }
 
  // ─── PICKERS ─────────────────────────────────────────────────────────────
  void _showDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2017),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.blue,
            onPrimary: Colors.white,
            surface: Color(0xFF1E1E1E),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _applyFilters();
    }
  }
 
  void _showDirectionPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Select Direction",
                  style: GoogleFonts.quicksand(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 16),
              for (final val in ["All", "Received", "Sent"])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(val,
                      style: TextStyle(
                          color: _selectedDirection == val
                              ? Colors.blue
                              : Colors.white)),
                  trailing: Icon(
                    _selectedDirection == val
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: _selectedDirection == val
                        ? Colors.blue
                        : Colors.grey,
                  ),
                  onTap: () {
                    setState(() => _selectedDirection = val);
                    _applyFilters();
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
 
  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        _buildFilterRow(isDark),
        const SizedBox(height: 16),
        Expanded(
          child: _isLoading
              ? _buildLoadingState()
              : _groupedTransactions.isEmpty
                  ? _buildEmptyState()
                  : _buildTransactionList(isDark),
        ),
      ],
    );
  }
 
  Widget _buildFilterRow(bool isDark) {
    return Row(
      children: [
        _buildFilterButton(
          label: _selectedDate == null
              ? "All dates"
              : DateFormat('MMM d, yyyy').format(_selectedDate!),
          onTap: _showDatePicker,
          isDark: isDark,
          isSelected: _selectedDate != null,
          trailingIcon: _selectedDate != null
              ? Icons.close
              : Icons.keyboard_arrow_down,
          onTrailingTap: _selectedDate != null
              ? () {
                  setState(() => _selectedDate = null);
                  _applyFilters();
                }
              : null,
        ),
        const SizedBox(width: 12),
        _buildFilterButton(
          label: _selectedDirection == "All" ? "Direction" : _selectedDirection,
          onTap: _showDirectionPicker,
          isDark: isDark,
          isSelected: _selectedDirection != "All",
          trailingIcon: _selectedDirection != "All"
              ? Icons.close
              : Icons.keyboard_arrow_down,
          onTrailingTap: _selectedDirection != "All"
              ? () {
                  setState(() => _selectedDirection = "All");
                  _applyFilters();
                }
              : null,
        ),
      ],
    );
  }
 
  Widget _buildFilterButton({
    required String label,
    required VoidCallback onTap,
    required bool isDark,
    bool isSelected = false,
    IconData trailingIcon = Icons.keyboard_arrow_down,
    VoidCallback? onTrailingTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.blue.withOpacity(0.15)
                : (isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.black.withOpacity(0.05)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? Colors.blue
                  : (isDark ? Colors.white10 : Colors.black12),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.quicksand(
                    color: isSelected
                        ? Colors.blue
                        : (isDark ? Colors.white70 : Colors.black87),
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onTrailingTap ?? onTap,
                child: Icon(trailingIcon,
                    size: 16,
                    color: isSelected ? Colors.blue : Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
 
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.blue),
          const SizedBox(height: 16),
          Text(
            _statusMessage,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
 
  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off,
              color: Colors.grey.withOpacity(0.5), size: 56),
          const SizedBox(height: 16),
          Text(
            "No transactions found",
            style: GoogleFonts.quicksand(
                color: isDark ? Colors.white70 : Colors.black54,
                fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white24, fontSize: 12),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: _fetchHistory,
            icon: const Icon(Icons.refresh, color: Colors.blue),
            label: const Text("Refresh",
                style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }
 
  Widget _buildTransactionList(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      physics: const BouncingScrollPhysics(),
      itemCount: _groupedTransactions.keys.length,
      itemBuilder: (ctx, i) {
        final dateKey = _groupedTransactions.keys.elementAt(i);
        final txs = _groupedTransactions[dateKey]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                dateKey,
                style: GoogleFonts.quicksand(
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...txs.map((tx) => _buildTransactionCard(tx, isDark)),
          ],
        );
      },
    );
  }
 
  Widget _buildTransactionCard(Map<String, dynamic> tx, bool isDark) {
    final isReceive =
        tx['to'].toString().toLowerCase() == widget.address.toLowerCase();
    final double value = tx['value'] as double;
    final String sym = tx['symbol'] as String;
    final double? price = _tokenPrices[sym];
    final double? usdValue = price != null ? value * price : null;
 
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: (isReceive ? Colors.greenAccent : Colors.blue)
                  .withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isReceive ? Icons.arrow_downward : Icons.arrow_upward,
              color: isReceive ? Colors.greenAccent : Colors.blue,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          // Centre
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isReceive ? "Received" : "Sent",
                  style: GoogleFonts.quicksand(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  DateFormat('h:mm a')
                      .format(tx['timestamp'] as DateTime),
                  style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text(
                  isReceive
                      ? "From: ${_shortenAddress(tx['from'])}"
                      : "To: ${_shortenAddress(tx['to'])}",
                  style: TextStyle(
                      color: isDark ? Colors.white24 : Colors.black26,
                      fontSize: 11),
                ),
              ],
            ),
          ),
          // Amount
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "${isReceive ? '+' : '-'}${_formatAmount(value)} $sym",
                style: GoogleFonts.quicksand(
                  color: isReceive
                      ? Colors.greenAccent
                      : (isDark ? Colors.white : Colors.black),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                usdValue != null
                    ? "\$${usdValue.toStringAsFixed(2)}"
                    : "—",
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
 
  /// Smart amount formatting
  String _formatAmount(double v) {
    if (v >= 1000) return v.toStringAsFixed(2);
    if (v >= 1) return v.toStringAsFixed(4);
    if (v >= 0.0001) return v.toStringAsFixed(6);
    return v.toStringAsFixed(8);
  }
}