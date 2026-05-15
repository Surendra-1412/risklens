import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ─── API Credentials ────────────────────────────────────────────────────────

class WalletApiCredentials {
  final String coinStatsApiKey;

  const WalletApiCredentials({required this.coinStatsApiKey});
}

// ─── Scan Outcome Types ─────────────────────────────────────────────────────

sealed class ScanOutcome {}

class ScanSuccess extends ScanOutcome {
  final WalletScanSnapshot snapshot;
  ScanSuccess(this.snapshot);
}

class ScanFailure extends ScanOutcome {
  final String message;
  ScanFailure(this.message);
}

// ─── History Descriptor ─────────────────────────────────────────────────────

class HistoryDescriptor {
  final String chain;
  final String address;

  const HistoryDescriptor({required this.chain, required this.address});
}

// ─── Token Holding ──────────────────────────────────────────────────────────

class TokenHolding {
  final String symbol;
  final String chain;
  final double balance;
  final double priceUsd;
  final double valueUsd;

  const TokenHolding({
    required this.symbol,
    required this.chain,
    required this.balance,
    required this.priceUsd,
    required this.valueUsd,
  });
}

// ─── Wallet Scan Snapshot ───────────────────────────────────────────────────

class WalletScanSnapshot {
  /// Human-readable label: "Ethereum", "Solana", "Bitcoin", "Multi-chain"
  final String displayLabel;

  /// Total portfolio value in USD
  final double totalUsd;

  /// CoinStats coin id for charting (e.g. "bitcoin", "ethereum")
  final String primaryCoinId;

  /// Per-chain descriptors for the History tab
  final List<HistoryDescriptor> historyDescriptors;

  /// Individual token holdings
  final List<TokenHolding> holdings;

  const WalletScanSnapshot({
    required this.displayLabel,
    required this.totalUsd,
    required this.primaryCoinId,
    required this.historyDescriptors,
    required this.holdings,
  });
}

// ─── Wallet Scan Coordinator (CoinStats only) ───────────────────────────────

class WalletScanCoordinator {
  final WalletApiCredentials _creds;
  static const String _baseUrl = "https://openapiv1.coinstats.app";

  WalletScanCoordinator(this._creds);

  void dispose() {}

  Map<String, String> get _headers => {
        "X-API-KEY": _creds.coinStatsApiKey,
        "Accept": "application/json",
      };

  // ─── PUBLIC: scan a wallet address ──────────────────────────────────

  Future<ScanOutcome> scan(String address) async {
    final cleanAddr = address.trim();
    if (cleanAddr.isEmpty) {
      return ScanFailure("Please enter a wallet address.");
    }

    try {
      final res = await http.get(
        Uri.parse("$_baseUrl/wallet/balance?address=$cleanAddr"),
        headers: _headers,
      );

      if (res.statusCode != 200) {
        debugPrint("CoinStats wallet/balance ${res.statusCode}: ${res.body}");
        return ScanFailure(
          "Could not fetch wallet data (${res.statusCode}). Check the address and try again.",
        );
      }

      final raw = jsonDecode(res.body);

      // CoinStats can return the list directly or nested under a key
      final List balances = raw is List
          ? raw
          : (raw['balances'] as List? ??
              raw['result'] as List? ??
              raw['data'] as List? ??
              []);

      if (balances.isEmpty) {
        return ScanFailure(
          "No tokens found for this address. It may be empty or unsupported.",
        );
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
            token['symbol']?.toString() ??
            token['coinId']?.toString() ??
            "???";
        final String chain =
            token['blockchain']?.toString() ??
            token['chain']?.toString() ??
            "ethereum";

        chains.add(chain);
        totalUsd += value;
        holdings.add(TokenHolding(
          symbol: sym.toUpperCase(),
          chain: chain,
          balance: bal,
          priceUsd: price,
          valueUsd: value,
        ));
      }

      // Sort by value descending
      holdings.sort((a, b) => b.valueUsd.compareTo(a.valueUsd));

      String displayLabel;
      String primaryCoinId;

      if (chains.length > 1) {
        displayLabel = "Multi-chain";
        primaryCoinId = holdings.isNotEmpty
            ? _guessCoinId(holdings.first.symbol)
            : "bitcoin";
      } else {
        final singleChain = _prettifyChainName(chains.first);
        displayLabel = singleChain;
        primaryCoinId = _chainToCoinId(singleChain);
      }

      return ScanSuccess(WalletScanSnapshot(
        displayLabel: displayLabel,
        totalUsd: totalUsd,
        primaryCoinId: primaryCoinId,
        historyDescriptors: chains
            .map((c) => HistoryDescriptor(chain: c, address: cleanAddr))
            .toList(),
        holdings: holdings,
      ));
    } catch (e) {
      debugPrint("WalletScanCoordinator.scan error: $e");
      return ScanFailure("Network error. Please check your connection.");
    }
  }

  // ─── PUBLIC: fetch coin chart via CoinStats ─────────────────────────

  /// Returns list of [timestamp, price] pairs.
  Future<List<List<double>>> fetchCoinChart(
    String coinId, {
    String period = "1m",
  }) async {
    try {
      final res = await http.get(
        Uri.parse("$_baseUrl/coins/$coinId/charts?period=$period"),
        headers: _headers,
      );

      if (res.statusCode == 200) {
        final raw = jsonDecode(res.body);
        final List dataList = raw is List ? raw : (raw['chart'] as List? ?? []);
        final List<List<double>> result = [];
        for (final point in dataList) {
          if (point is List && point.length >= 2) {
            result.add([
              (point[0] as num).toDouble(),
              (point[1] as num).toDouble(),
            ]);
          }
        }
        return result;
      }
    } catch (e) {
      debugPrint("CoinStats chart error: $e");
    }
    return [];
  }

  // ─── PUBLIC: fetch single coin price via CoinStats ──────────────────

  Future<double> fetchCoinPrice(String coinId) async {
    try {
      final res = await http.get(
        Uri.parse("$_baseUrl/coins/$coinId"),
        headers: _headers,
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        // CoinStats returns { "price": 67000.5, ... } or nested under "coin"
        final coin = data['coin'] ?? data;
        return (coin['price'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (e) {
      debugPrint("CoinStats price error for $coinId: $e");
    }
    return 0.0;
  }

  // ─── HELPERS ────────────────────────────────────────────────────────

  String _prettifyChainName(String raw) {
    switch (raw.toLowerCase()) {
      case "ethereum":
        return "Ethereum";
      case "solana":
        return "Solana";
      case "bitcoin":
        return "Bitcoin";
      case "polygon":
        return "Polygon";
      case "bsc":
      case "binance-smart-chain":
        return "BSC";
      case "arbitrum":
        return "Arbitrum";
      case "optimism":
        return "Optimism";
      case "base":
        return "Base";
      case "tron":
        return "Tron";
      case "xrp":
      case "ripple":
        return "XRP";
      case "avalanche":
        return "Avalanche";
      default:
        return raw.isNotEmpty
            ? raw[0].toUpperCase() + raw.substring(1)
            : raw;
    }
  }

  String _chainToCoinId(String chain) {
    switch (chain) {
      case "Ethereum":
      case "EVM":
      case "Arbitrum":
      case "Optimism":
      case "Base":
        return "ethereum";
      case "Solana":
        return "solana";
      case "Bitcoin":
        return "bitcoin";
      case "BSC":
        return "binancecoin";
      case "Polygon":
        return "matic-network";
      case "Tron":
        return "tron";
      case "XRP":
        return "ripple";
      case "Avalanche":
        return "avalanche-2";
      default:
        return "bitcoin";
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
}
