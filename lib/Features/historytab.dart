import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'dart:async';
import '../wallet/wallet.dart';

class HistoryTab extends StatefulWidget {
  final String address;
  final String chain;
  final WalletScanSnapshot? scanSnapshot;
  final WalletApiCredentials? apiCredentials;

  const HistoryTab({
    super.key,
    required this.address,
    required this.chain,
    this.scanSnapshot,
    this.apiCredentials,
  });

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  // ── API Keys ──────────────────────────────────────────────────────────────
  // Use the FULL key (with typeId) from ledgerscreen.dart

  // Public Solana RPC — free, no API key required
  static const String _solanaRpc = "https://api.mainnet-beta.solana.com";

  bool _isLoading = true;
  String _statusMessage = "Loading transactions...";
  List<Map<String, dynamic>> _allTransactions = [];
  Map<String, List<Map<String, dynamic>>> _groupedTransactions = {};
  Map<String, double> _tokenPrices = {};

  int _loadingStep = 0;
  Timer? _loadingTimer;
  final List<String> _loadingMessages = [
    "Fetching transactions...",
    "Verifying hashes...",
    "Decoding block data...",
    "Syncing history...",
    "Almost complete...",
  ];

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

    // Sort all fetched transactions from nearest date to farthest (newest first)
    _allTransactions.sort((a, b) {
      final DateTime ta = a['timestamp'];
      final DateTime tb = b['timestamp'];
      return tb.compareTo(ta);
    });

    await _fetchTokenPrices();
    if (!mounted) return;
    _applyFilters();
    _loadingTimer?.cancel();
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
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "User-Agent": "RiskLens/1.0"
        },
        body: jsonEncode({
          "jsonrpc": "2.0",
          "id": 1,
          "method": "getSignaturesForAddress",
          "params": [
            widget.address,
            {"limit": 25, "commitment": "finalized"},
          ],
        }),
      );

      if (sigRes.statusCode != 200) {
        if (mounted) {
          setState(
            () => _statusMessage = "Solana RPC error: ${sigRes.statusCode}",
          );
        }
        return;
      }

      final sigBody = jsonDecode(sigRes.body);
      if (sigBody['error'] != null) {
        if (mounted) {
          setState(
            () => _statusMessage = "RPC Error: ${sigBody['error']['message']}",
          );
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
        setState(() => _statusMessage = "Loading ${sigs.length} transactions…");
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
              "commitment": "finalized",
            },
          ],
        };
      }).toList();

      final txRes = await http.post(
        Uri.parse(_solanaRpc),
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "User-Agent": "RiskLens/1.0"
        },
        body: jsonEncode(batch),
      );

      if (txRes.statusCode != 200) {
        if (mounted) {
          setState(
            () => _statusMessage = "TX fetch error: ${txRes.statusCode}",
          );
        }
        return;
      }

      final List txResults = jsonDecode(txRes.body);
      final List<Map<String, dynamic>> parsed = [];

      for (final result in txResults) {
        if (result == null) {
          debugPrint("Solana batch item is null");
          continue;
        }
        if (result['result'] == null) {
          debugPrint("Solana getTransaction returned null for signature: ${result['id']}");
          continue;
        }
        
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
        debugPrint("Searching for address ${widget.address} in ${accountKeys.length} keys");
        for (int i = 0; i < accountKeys.length; i++) {
          final key = accountKeys[i];
          final String pubkey = key is Map
              ? (key['pubkey']?.toString() ?? '')
              : key.toString();
          
          if (pubkey == widget.address) {
            myIdx = i;
            break;
          }
        }

        if (myIdx < 0) {
          debugPrint("Address ${widget.address} not found in transaction $sig");
          continue;
        }
        
        if (myIdx >= preBalances.length || myIdx >= postBalances.length) {
          debugPrint("Balance index out of range for address ${widget.address} in $sig");
          continue;
        }

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
      if (mounted)
        setState(() => _statusMessage = "Error parsing Solana history");
    }
  }

  // ─── EVM via Moralis ─────────────────────────────────────────────────────
  Future<void> _fetchEvmHistory() async {
    debugPrint("EVM history fetch bypassed (Moralis removed)");
    return;
  }



  // ─── BITCOIN via mempool.space ────────────────────────────────────────────
  Future<void> _fetchBitcoinHistory() async {
    debugPrint("Fetching Bitcoin history for ${widget.address}");
    try {
      final res = await http.get(
        Uri.parse("https://mempool.space/api/address/${widget.address}/txs"),
        headers: {
          "Accept": "application/json",
          "User-Agent": "RiskLens/1.0"
        },
      );

      if (res.statusCode != 200) {
        setState(() => _statusMessage = "Bitcoin API error: ${res.statusCode}");
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
    // CoinGecko integration removed as it is no longer used.
  }

  // ─── HELPERS ──────────────────────────────────────────────────────────────
  String _getMoralisChainCode(String chain) {
    switch (chain.toLowerCase()) {
      case "ethereum":
        return "eth";
      case "polygon":
        return "polygon";
      case "bsc":
        return "bsc";
      case "arbitrum":
        return "arbitrum";
      case "optimism":
        return "optimism";
      case "base":
        return "base";
      default:
        return "eth";
    }
  }

  String _getChainSymbol(String chain) {
    switch (chain.toLowerCase()) {
      case "ethereum":
        return "ETH";
      case "polygon":
        return "MATIC";
      case "bsc":
        return "BNB";
      case "arbitrum":
        return "ETH";
      case "optimism":
        return "ETH";
      case "base":
        return "ETH";
      default:
        return "ETH";
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
            d.day != _selectedDate!.day)
          return false;
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
      final label = DateFormat(
        'MMMM d, yyyy',
      ).format(tx['timestamp'] as DateTime);
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          padding: EdgeInsets.all(24.r),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Select Direction",
                style: GoogleFonts.quicksand(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 16.h),
              for (final val in ["All", "Received", "Sent"])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    val,
                    style: TextStyle(
                      color: _selectedDirection == val
                          ? Colors.blue
                          : Colors.white,
                    ),
                  ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _buildFilterRow(isDark),
          SizedBox(height: 16.h),
          Expanded(
            child: _isLoading
                ? _buildLoadingState()
                : _groupedTransactions.isEmpty
                ? _buildEmptyState()
                : _buildTransactionList(isDark),
          ),
        ],
      ),
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
        SizedBox(width: 12.w),
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
          padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 8.w),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.blue.withOpacity(0.15)
                : (isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.black.withOpacity(0.05)),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: isSelected
                  ? Colors.blue
                  : (isDark ? Colors.white10 : Colors.black12),
              width: 1.w,
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
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13.sp,
                  ),
                ),
              ),
              SizedBox(width: 4.w),
              GestureDetector(
                onTap: onTrailingTap ?? onTap,
                child: Icon(
                  trailingIcon,
                  size: 16.w,
                  color: isSelected ? Colors.blue : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: Colors.blue,
            strokeWidth: 3,
            backgroundColor: isDark ? Colors.white10 : Colors.black12,
          ),
          SizedBox(height: 24.h),
          Text(
            _loadingMessages[_loadingStep],
            style: GoogleFonts.quicksand(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
            ),
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
          Icon(
            Icons.history_toggle_off,
            color: Colors.grey.withOpacity(0.5),
            size: 56.w,
          ),
          SizedBox(height: 16.h),
          Text(
            "No transactions found",
            style: GoogleFonts.quicksand(
              color: isDark ? Colors.white70 : Colors.black54,
              fontSize: 16.sp,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white24, fontSize: 12.sp),
          ),
          SizedBox(height: 24.h),
          TextButton.icon(
            onPressed: _fetchHistory,
            icon: const Icon(Icons.refresh, color: Colors.blue),
            label: const Text("Refresh", style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionList(bool isDark) {
    return ListView.builder(
      padding: EdgeInsets.only(bottom: 120.h),
      physics: const BouncingScrollPhysics(),
      itemCount: _groupedTransactions.keys.length,
      itemBuilder: (ctx, i) {
        final dateKey = _groupedTransactions.keys.elementAt(i);
        final txs = _groupedTransactions[dateKey]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 14.h),
              child: Text(
                dateKey,
                style: GoogleFonts.quicksand(
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontSize: 20.sp,
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

    final Map<String, String> tokenLogos = {
      "ETH": "https://assets.coingecko.com/coins/images/279/large/ethereum.png",
      "SOL": "https://assets.coingecko.com/coins/images/4128/large/solana.png",
      "BTC": "https://assets.coingecko.com/coins/images/1/large/bitcoin.png",
      "MATIC":
          "https://assets.coingecko.com/coins/images/4713/large/matic-token-icon.png",
      "BNB":
          "https://assets.coingecko.com/coins/images/825/large/bnb-icon2_2x.png",
      "USDT": "https://assets.coingecko.com/coins/images/325/large/Tether.png",
      "USDC":
          "https://assets.coingecko.com/coins/images/6319/large/USD_Coin_icon.png",
      "DAI": "https://assets.coingecko.com/coins/images/9956/large/4943.png",
      "WBTC":
          "https://assets.coingecko.com/coins/images/7598/large/wrapped_bitcoin_wbtc.png",
      "LINK":
          "https://assets.coingecko.com/coins/images/877/large/chainlink-new-logo.png",
      "UNI":
          "https://assets.coingecko.com/coins/images/12504/large/uniswap-uni.png",
      "AAVE": "https://assets.coingecko.com/coins/images/12645/large/AAVE.png",
      "SHIB": "https://assets.coingecko.com/coins/images/11939/large/shiba.png",
      "PEPE":
          "https://assets.coingecko.com/coins/images/29850/large/pepe-token.jpeg",
    };

    final logoUrl = tokenLogos[sym.toUpperCase()];

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(28.r),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.06),
          width: 1.w,
        ),
      ),
      child: Row(
        children: [
          // Icon
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 44.h,
                width: 44.w,
                decoration: BoxDecoration(
                  color: (isReceive ? Colors.greenAccent : Colors.blue)
                      .withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isReceive ? Icons.south_west : Icons.north_east,
                  color: isReceive ? Colors.greenAccent : Colors.blue,
                  size: 20.w,
                ),
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Container(
                    height: 18.h,
                    width: 18.w,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.1)
                          : Colors.black.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: logoUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(9.r),
                            child: Image.network(
                              logoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.monetization_on,
                                color: Colors.grey,
                                size: 10.w,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.monetization_on,
                            color: Colors.grey,
                            size: 10.w,
                          ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(width: 14.w),
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
                    fontSize: 18.sp,
                  ),
                ),
                SizedBox(height: 3.h),
                Text(
                  DateFormat('h:mm a').format(tx['timestamp'] as DateTime),
                  style: TextStyle(
                    color: isDark ? Colors.white38 : Colors.black38,
                    fontSize: 14.sp,
                  ),
                ),
                SizedBox(height: 3.h),
                Text(
                  isReceive
                      ? "From: ${_shortenAddress(tx['from'])}"
                      : "To: ${_shortenAddress(tx['to'])}",
                  style: TextStyle(
                    color: isDark ? Colors.white24 : Colors.black26,
                    fontSize: 11.sp,
                  ),
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
                  fontSize: 16.sp,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                usdValue != null ? "\$${usdValue.toStringAsFixed(2)}" : "—",
                style: TextStyle(color: Colors.grey, fontSize: 14.sp),
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
