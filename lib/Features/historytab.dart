import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:ui';
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
  final String _moralisApiKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJub25jZSI6ImYyMTE4N2MxLTE4NzAtNDU0MC1hYzIwLTc3NTc4NDRhYjFjNCIsIm9yZ0lkIjoiNTEzODg4IiwidXNlcklkIjoiNTI4ODExIiwidHlwZSI6IlBST0pFQ1QiLCJpYXQiOjE3Nzc3Mzg0NzMsImV4cCI6NDkzMzQ5ODQ3M30.MRhG1_u1iLfLPI77pteOnlpyQgvNyaDTzt2hm1hwOZA";
  final String _coinGeckoApiKey = "CG-aZWy4YFQ6YGD98ookZCRghDF";
  
  bool _isLoading = true;
  String _debugInfo = "Initializing...";
  List<Map<String, dynamic>> _allTransactions = [];
  Map<String, List<Map<String, dynamic>>> _groupedTransactions = {};
  Map<String, double> _tokenPrices = {};
  
  // Filters
  DateTime? _selectedDate;
  String _selectedDirection = "All"; // "All", "Received", "Sent"

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  @override
  void didUpdateWidget(HistoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.address != widget.address || oldWidget.chain != widget.chain) {
      _fetchHistory();
    }
  }

  Future<void> _fetchHistory() async {
    if (widget.address.isEmpty) {
      setState(() {
        _isLoading = false;
        _debugInfo = "No address provided";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _debugInfo = "Fetching history for ${widget.chain}...\nAddress: ${widget.address}";
      _allTransactions = [];
      _groupedTransactions = {};
    });

    try {
      if (widget.chain == "Solana") {
        await _fetchSolanaHistory();
      } else if (widget.chain == "Bitcoin") {
        await _fetchBitcoinHistory();
      } else {
        await _fetchEvmHistory();
      }
    } catch (e) {
      setState(() => _debugInfo = "Error: $e");
    } finally {
      if (mounted) {
        await _fetchTokenPrices();
        if (!mounted) return;
        _applyFilters();
        setState(() {
          _isLoading = false;
          if (_allTransactions.isEmpty && _debugInfo.startsWith("Fetching")) {
            _debugInfo = "No transactions found for this address.";
          }
        });
      }
    }
  }

  Future<void> _fetchTokenPrices() async {
    final symbols = _allTransactions.map((tx) => tx['symbol'].toString()).toSet();
    if (symbols.isEmpty) return;

    final Map<String, String> symbolToId = {
      "ETH": "ethereum",
      "SOL": "solana",
      "BTC": "bitcoin",
      "MATIC": "matic-network",
      "BNB": "binancecoin",
      "USDT": "tether",
      "USDC": "usd-coin",
    };

    List<String> idsToFetch = [];
    for (var symbol in symbols) {
      if (symbolToId.containsKey(symbol.toUpperCase())) {
        idsToFetch.add(symbolToId[symbol.toUpperCase()]!);
      }
    }

    if (idsToFetch.isEmpty) return;

    final String idsParam = idsToFetch.join(",");
    final url = Uri.parse("https://api.coingecko.com/api/v3/simple/price?ids=$idsParam&vs_currencies=usd");

    try {
      final res = await http.get(url, headers: {"x-cg-demo-api-key": _coinGeckoApiKey});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        Map<String, double> newPrices = {};
        for (var symbol in symbols) {
          final id = symbolToId[symbol.toUpperCase()];
          if (id != null && data[id] != null) {
            newPrices[symbol] = (data[id]['usd'] as num).toDouble();
          }
        }
        setState(() {
          _tokenPrices = newPrices;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchEvmHistory() async {
    final chain = _getMoralisChainCode(widget.chain);
    final String baseUrl = "https://deep-index.moralis.io/api/v2";
    final Map<String, String> headers = {
      "X-API-Key": _moralisApiKey,
      "accept": "application/json",
    };

    try {
      final List<Map<String, dynamic>> combinedTransactions = [];

      // Fetch Native and ERC20 in parallel
      final results = await Future.wait([
        http.get(Uri.parse("$baseUrl/${widget.address}?chain=$chain"), headers: headers),
        http.get(Uri.parse("$baseUrl/${widget.address}/erc20/transfers?chain=$chain"), headers: headers),
      ]);

      final nativeRes = results[0];
      final erc20Res = results[1];

      if (nativeRes.statusCode == 200) {
        final data = jsonDecode(nativeRes.body);
        final List txs = data['result'] ?? [];
        for (var tx in txs) {
          final from = tx['from_address']?.toString() ?? "";
          final to = tx['to_address']?.toString() ?? "";
          final value = double.tryParse(tx['value']?.toString() ?? "0") ?? 0;
          final timestamp = DateTime.tryParse(tx['block_timestamp'] ?? "") ?? DateTime.now();

          double adjustedValue = value / 1e18;
          if (adjustedValue > 0) {
              combinedTransactions.add({
                "from": from,
                "to": to,
                "value": adjustedValue,
                "symbol": _getChainSymbol(widget.chain),
                "timestamp": timestamp,
                "hash": tx['hash'],
              });
          }
        }
      }

      if (erc20Res.statusCode == 200) {
        final data = jsonDecode(erc20Res.body);
        final List txs = data['result'] ?? [];
        for (var tx in txs) {
          final from = tx['from_address']?.toString() ?? "";
          final to = tx['to_address']?.toString() ?? "";
          final value = double.tryParse(tx['value']?.toString() ?? "0") ?? 0;
          final int decimals = int.tryParse(tx['token_decimals']?.toString() ?? "18") ?? 18;
          final String symbol = tx['token_symbol']?.toString() ?? "ERC20";
          final timestamp = DateTime.tryParse(tx['block_timestamp'] ?? "") ?? DateTime.now();

          double adjustedValue = value / pow(10, decimals);
          
          if (adjustedValue > 0) {
              combinedTransactions.add({
                "from": from,
                "to": to,
                "value": adjustedValue,
                "symbol": symbol,
                "timestamp": timestamp,
                "hash": tx['transaction_hash'],
              });
          }
        }
      }

      // Sort combined by timestamp DESC (latest first)
      combinedTransactions.sort((a, b) {
        final DateTime timeA = a['timestamp'];
        final DateTime timeB = b['timestamp'];
        return timeB.compareTo(timeA);
      });

      _allTransactions = combinedTransactions;
      
    } catch (e) {
       setState(() => _debugInfo = "EVM Error: $e");
    }
  }

  Future<void> _fetchSolanaHistory() async {
    // Attempt 1: Gateway
    final url = Uri.parse("https://solana-gateway.moralis.io/account/mainnet/${widget.address}/transactions");
    try {
      final response = await http.get(url, headers: {
        "X-API-Key": _moralisApiKey,
        "accept": "application/json",
      });

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        final List results = decoded is List ? decoded : (decoded['result'] ?? []);
        _allTransactions = _parseSolanaResults(results);
        return;
      }
    } catch (_) {}

    // Attempt 2: V2 Fallback
    final fallbackUrl = Uri.parse("https://deep-index.moralis.io/api/v2/solana/mainnet/account/${widget.address}/transactions");
    final fallbackRes = await http.get(fallbackUrl, headers: {
      "X-API-Key": _moralisApiKey,
      "accept": "application/json",
    });

    if (fallbackRes.statusCode == 200) {
      final data = jsonDecode(fallbackRes.body);
      final List results = data is List ? data : (data['result'] ?? []);
      _allTransactions = _parseSolanaResults(results);
    } else {
      setState(() => _debugInfo = "Solana Error: ${fallbackRes.statusCode}");
    }
  }

  List<Map<String, dynamic>> _parseSolanaResults(List results) {
    return results.map((tx) {
      final blockTime = tx['blockTime'] ?? tx['block_timestamp'] ?? 0;
      final timestamp = blockTime is int 
          ? DateTime.fromMillisecondsSinceEpoch(blockTime * 1000)
          : (DateTime.tryParse(blockTime.toString()) ?? DateTime.now());
          
      final transfers = tx['nativeTransfers'] as List? ?? [];
      
      String from = tx['from_address']?.toString() ?? "Unknown";
      String to = tx['to_address']?.toString() ?? "Unknown";
      double value = (double.tryParse(tx['value']?.toString() ?? "0") ?? 0) / 1e9;
      
      if (transfers.isNotEmpty) {
        from = transfers[0]['from'] ?? from;
        to = transfers[0]['to'] ?? to;
        value = (double.tryParse(transfers[0]['amount']?.toString() ?? "0") ?? 0) / 1e9;
      }

      return {
        "from": from,
        "to": to,
        "value": value,
        "symbol": "SOL",
        "timestamp": timestamp,
        "hash": tx['signature'] ?? tx['hash'],
      };
    }).toList();
  }

  Future<void> _fetchBitcoinHistory() async {
    final url = Uri.parse("https://mempool.space/api/address/${widget.address}/txs");
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final List results = jsonDecode(response.body);
      
      _allTransactions = results.map((tx) {
        final status = tx['status'] ?? {};
        final blockTime = status['block_time'] ?? 0;
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

        final net = voutSum - vinSum;
        
        return {
          "from": net < 0 ? widget.address : "External",
          "to": net > 0 ? widget.address : "External",
          "value": net.abs() / 1e8,
          "symbol": "BTC",
          "timestamp": timestamp,
          "hash": tx['txid'],
        };
      }).toList();
    }
  }

  String _getMoralisChainCode(String chain) {
    switch (chain.toLowerCase()) {
      case "ethereum": return "eth";
      case "polygon": return "polygon";
      case "bsc": return "bsc";
      default: return "eth";
    }
  }

  String _getChainSymbol(String chain) {
    switch (chain.toLowerCase()) {
      case "ethereum": return "ETH";
      case "polygon": return "MATIC";
      case "bsc": return "BNB";
      default: return "ETH";
    }
  }

  void _applyFilters() {
    List<Map<String, dynamic>> filtered = _allTransactions.where((tx) {
      // Date Filter
      if (_selectedDate != null) {
        final txDate = tx['timestamp'] as DateTime;
        if (txDate.year != _selectedDate!.year || 
            txDate.month != _selectedDate!.month || 
            txDate.day != _selectedDate!.day) {
          return false;
        }
      }

      // Direction Filter
      final isReceive = tx['to'].toString().toLowerCase() == widget.address.toLowerCase();
      if (_selectedDirection == "Received" && !isReceive) return false;
      if (_selectedDirection == "Sent" && isReceive) return false;

      return true;
    }).toList();

    // Grouping logic
    Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var tx in filtered) {
      final date = DateFormat('MMMM d, yyyy').format(tx['timestamp'] as DateTime);
      grouped.putIfAbsent(date, () => []).add(tx);
    }
    
    setState(() {
      _groupedTransactions = grouped;
    });
  }

  void _showDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blue,
              onPrimary: Colors.white,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _applyFilters();
      });
    }
  }

  void _showDirectionPicker() {
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
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Select Direction",
                    style: GoogleFonts.quicksand(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildDirectionOption("All", setModalState),
                  _buildDirectionOption("Received", setModalState),
                  _buildDirectionOption("Sent", setModalState),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDirectionOption(String value, StateSetter setModalState) {
    final isSelected = _selectedDirection == value;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        value,
        style: TextStyle(color: isSelected ? Colors.blue : Colors.white),
      ),
      trailing: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: isSelected ? Colors.blue : Colors.grey,
      ),
      onTap: () {
        setState(() {
          _selectedDirection = value;
          _applyFilters();
        });
        Navigator.pop(context);
      },
    );
  }

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
        ),
        const SizedBox(width: 12),
        _buildFilterButton(
          label: _selectedDirection == "All" ? "Direction" : _selectedDirection,
          onTap: _showDirectionPicker,
          isDark: isDark,
          isSelected: _selectedDirection != "All",
        ),
      ],
    );
  }

  Widget _buildFilterButton({
    required String label,
    required VoidCallback onTap,
    required bool isDark,
    bool isSelected = false,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected 
                ? Colors.blue.withOpacity(0.2) 
                : (isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.blue : (isDark ? Colors.white10 : Colors.black12),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: GoogleFonts.quicksand(
                  color: isSelected ? Colors.blue : (isDark ? Colors.white70 : Colors.black87),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: isSelected ? Colors.blue : Colors.grey,
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
          Text(_debugInfo, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "No transactions found",
            style: GoogleFonts.quicksand(
              color: Colors.grey,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _debugInfo,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white24, fontSize: 12),
          ),
          const SizedBox(height: 24),
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
      padding: const EdgeInsets.only(bottom: 120),
      physics: const BouncingScrollPhysics(),
      itemCount: _groupedTransactions.keys.length,
      itemBuilder: (context, index) {
        final dateKey = _groupedTransactions.keys.elementAt(index);
        final txs = _groupedTransactions[dateKey]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                dateKey,
                style: GoogleFonts.quicksand(
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...txs.map((tx) => _buildTransactionCard(tx, isDark)).toList(),
          ],
        );
      },
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx, bool isDark) {
    final isReceive = tx['to'].toString().toLowerCase() == widget.address.toLowerCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark 
            ? Colors.white.withOpacity(0.05) 
            : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: (isReceive ? Colors.greenAccent : Colors.blue).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isReceive ? Icons.arrow_downward : Icons.arrow_upward,
              color: isReceive ? Colors.greenAccent : Colors.blue,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          // Center Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isReceive ? "Receive" : "Send",
                  style: GoogleFonts.quicksand(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('h:mm a').format(tx['timestamp'] as DateTime),
                  style: TextStyle(
                    color: isDark ? Colors.white38 : Colors.black38,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isReceive 
                      ? "From: ${_shortenAddress(tx['from'])}" 
                      : "To: ${_shortenAddress(tx['to'])}",
                  style: TextStyle(
                    color: isDark ? Colors.white24 : Colors.black26,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Right Amount
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "${isReceive ? '+' : '-'}${tx['value'].toStringAsFixed(4)} ${tx['symbol']}",
                style: GoogleFonts.quicksand(
                  color: isReceive ? Colors.greenAccent : (isDark ? Colors.white : Colors.black),
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _tokenPrices.containsKey(tx['symbol'])
                    ? "\$${(tx['value'] * _tokenPrices[tx['symbol']]!).toStringAsFixed(2)}"
                    : "-\$--",
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _shortenAddress(String addr) {
    if (addr == "Unknown" || addr == "External") return addr;
    if (addr.length < 12) return addr;
    return "${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}";
  }
}
