import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'menu.dart';
import 'profile_screen_new.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  final bool isDarkMode;

  const HomeScreen({
    super.key,
    required this.toggleTheme,
    required this.isDarkMode,
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
  Map<String, dynamic>? _domainData;
  String? _error;
  bool _isDetailsExpanded = false;
  bool _isDomainExpanded = false;

  final String _goPlusApiKey = "UStMZSdsgeMpFbkwhWpj";
  Map<String, String> get _headers => {"Authorization": _goPlusApiKey};

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _isFocused = _focusNode.hasFocus);
    });
    _searchController.addListener(_detectInputType);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // --- INPUT DETECTION ---

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

  // --- API INTEGRATION ---

  Future<void> _fetchSecurityData() async {
    final input = _searchController.text.trim();
    if (input.isEmpty || _inputType == "Unknown") return;

    setState(() {
      _isLoading = true;
      _securityData = null;
      _domainData = null;
      _error = null;
    });

    try {
      if (_inputType == "EVM") {
        await _fetchEvmSecurity(input);
      } else if (_inputType == "Solana") {
        await _fetchSolanaSecurity(input);
      } else if (_inputType == "URL") {
        await _fetchUrlSecurity(input);
        await _fetchDomainData(input);
      }
    } catch (e) {
      setState(() => _error = "Unable to analyze input");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchEvmSecurity(String address) async {
    final url = Uri.parse(
      "https://api.gopluslabs.io/api/v1/address_security/$address?chain_id=1",
    );
    final response = await http.get(url, headers: _headers);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(
        () => _securityData = {
          "type": "Wallet",
          "status": _getWalletStatus(data['result']),
          "details": _formatWalletDetails(data['result']),
          "analysis": _getRiskAnalysis(data['result'], "Wallet"),
        },
      );
    } else {
      throw Exception();
    }
  }

  Future<void> _fetchSolanaSecurity(String address) async {
    final url = Uri.parse(
      "https://api.gopluslabs.io/api/v1/address_security/$address?chain_id=solana",
    );
    final response = await http.get(url, headers: _headers);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(
        () => _securityData = {
          "type": "Wallet",
          "status": _getWalletStatus(data['result']),
          "details": _formatWalletDetails(data['result']),
          "analysis": _getRiskAnalysis(data['result'], "Wallet"),
        },
      );
    } else {
      throw Exception();
    }
  }

  Future<void> _fetchUrlSecurity(String siteUrl) async {
    final url = Uri.parse(
      "https://api.gopluslabs.io/api/v1/url_security?url=$siteUrl",
    );
    final response = await http.get(url, headers: _headers);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(
        () => _securityData = {
          "type": "URL",
          "status": _getUrlStatus(data['result']),
          "details": _formatUrlDetails(data['result']),
          "analysis": _getRiskAnalysis(data['result'], "URL"),
        },
      );
    } else {
      throw Exception();
    }
  }

  Future<void> _fetchDomainData(String input) async {
    try {
      final domain = _getDomainFromUrl(input);
      if (domain.isEmpty) return;

      final url = Uri.parse("https://rdap.org/domain/$domain");
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final events = data['events'] as List?;
        final registrationEvent = events?.firstWhere(
          (e) => e['eventAction'] == 'registration',
          orElse: () => null,
        );

        if (registrationEvent != null) {
          final creationDate = DateTime.parse(registrationEvent['eventDate']);
          final now = DateTime.now();
          final ageDays = now.difference(creationDate).inDays;

          setState(() {
            _domainData = {
              "domain": domain,
              "creationDate": _formatDate(creationDate),
              "ageDays": ageDays,
            };
          });
        }
      }
    } catch (_) {}
  }

  String _getDomainFromUrl(String input) {
    try {
      String host = input.trim();
      if (!host.contains("://")) {
        host = "http://$host";
      }
      return Uri.parse(host).host;
    } catch (_) {
      return "";
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
    return "${date.day} ${months[date.month - 1]} ${date.year}";
  }

  // --- STATUS HELPERS ---

  String _getRiskAnalysis(dynamic result, String type) {
    if (result == null) return "No risk data available for this input.";
    
    List<String> reasons = [];
    
    if (type == "Wallet") {
      if (result['honeypot_related'] == "1") reasons.add("associated with honeypot tokens (tokens that cannot be sold)");
      if (result['blacklisted'] == "1") reasons.add("flagged on multiple security blacklists");
      if (result['malicious_address'] == "1") reasons.add("linked to known malicious or fraudulent activity");
      
      if (reasons.isEmpty) {
        return "This address has no known malicious history and appears safe for interaction based on current security intelligence.";
      } else {
        return "Warning: This address is considered risky because it is ${reasons.join(", and ")}. Interacting with it may lead to loss of funds.";
      }
    } else if (type == "URL") {
      if (result['phishing_site'] == "1") reasons.add("identified as a phishing site designed to steal credentials");
      if (result['malicious_site'] == "1") reasons.add("flagged as containing malicious scripts or malware");
      
      if (reasons.isEmpty) {
        return "This URL is currently not flagged by any major security providers and appears safe to visit.";
      } else {
        return "Caution: This site is highly dangerous as it has been ${reasons.join(" and ")}. Avoid entering any sensitive information.";
      }
    }
    
    return "Analysis complete. No immediate threats detected.";
  }

  String _getWalletStatus(dynamic result) {
    if (result == null) return "Safe";
    int risks = 0;
    if (result['honeypot_related'] == "1") risks++;
    if (result['blacklisted'] == "1") risks++;
    if (result['malicious_address'] == "1") risks++;
    if (risks > 1) return "High Risk";
    if (risks == 1) return "Warning";
    return "Safe";
  }

  String _getUrlStatus(dynamic result) {
    if (result == null) return "Safe";
    if (result['phishing_site'] == "1") return "High Risk";
    if (result['malicious_site'] == "1") return "High Risk";
    return "Safe";
  }

  List<Map<String, dynamic>> _formatWalletDetails(dynamic result) {
    return [
      {
        "icon": Icons.security,
        "label": "Token safety",
        "value": result?['honeypot_related'] == "1" ? "Honeypot" : "Secure",
      },
      {
        "icon": Icons.verified_user,
        "label": "Approval risks",
        "value": result?['blacklisted'] == "1" ? "Detected" : "None",
      },
      {
        "icon": Icons.warning_amber,
        "label": "Suspicious indicators",
        "value": result?['malicious_address'] == "1" ? "Found" : "None",
      },
    ];
  }

  List<Map<String, dynamic>> _formatUrlDetails(dynamic result) {
    return [
      {
        "icon": Icons.language,
        "label": "Domain safety score",
        "value": result?['phishing_site'] == "1" ? "Low" : "High",
      },
      {
        "icon": Icons.security,
        "label": "Risk indicators",
        "value": result?['malicious_site'] == "1" ? "Alert" : "Clean",
      },
      {
        "icon": Icons.reorder,
        "label": "Reputation signals",
        "value": result?['phishing_site'] == "1" ? "Poor" : "Good",
      },
    ];
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case "Safe":
        return Colors.greenAccent;
      case "Warning":
        return Colors.orangeAccent;
      case "High Risk":
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  // --- BUILD ---

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const MenuButton(),
        title: Text(
          "RiskLens",
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : Colors.black,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProfileScreen(),
                    ),
                  );
                },
                child: Container(
                  height: 43,
                  width: 43,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.blue.withOpacity(0.5),
                      width: 1.5,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 20.5,
                    backgroundColor: isDark ? Colors.white12 : Colors.black12,
                    child: Text(
                      (FirebaseAuth.instance.currentUser?.displayName ??
                              FirebaseAuth.instance.currentUser?.email ??
                              "U")
                          .substring(0, 1)
                          .toUpperCase(),
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 19,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF5F5F7),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeroHeader(isDark),
              const SizedBox(height: 24),
              _buildFloatingSearchBar(isDark),
              const SizedBox(height: 32),
              if (_domainData != null) ...[
                _buildDomainOverviewCard(isDark),
                const SizedBox(height: 16),
              ],
              _buildSecurityResultCard(isDark),
              const SizedBox(height: 120),
            ],
          ),
        ),
      ),
    );
  }

  // --- HERO HEADER CARD (matches Ledger's glassmorphic card exactly) ---

  Widget _buildHeroHeader(bool isDark) {
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  "Hello, ${FirebaseAuth.instance.currentUser?.displayName?.split(' ')[0] ?? 'User'}!",
                  style: GoogleFonts.quicksand(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 45,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  children: [
                    const TextSpan(text: "Scan before you "),
                    TextSpan(
                      text: "interact",
                      style: const TextStyle(color: Colors.blue),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Find potential threats involved and interactions with malicious contracts",
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

  // --- FLOATING SEARCH BAR (matches Ledger's glass search bar) ---

  Widget _buildFloatingSearchBar(bool isDark) {
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
              if (_inputType != "Unknown") _buildInputBadge(),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _focusNode,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 16,
                  ),
                  decoration: InputDecoration(
                    hintText: "Paste crypto address, Dapp url etc...",
                    hintStyle: GoogleFonts.quicksand(
                      color: isDark ? Colors.grey : Colors.black45,
                      fontSize: 17,
                    ),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _fetchSecurityData(),
                ),
              ),
              GestureDetector(
                onTap: _fetchSecurityData,
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

  Widget _buildInputBadge() {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _inputType,
        style: GoogleFonts.quicksand(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.blue,
        ),
      ),
    );
  }

  // --- SECURITY RESULT CARD (matches Ledger's Performance Card) ---

  Widget _buildSecurityResultCard(bool isDark) {
    if (_isLoading) {
      return _buildResultContainer(
        isDark,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: CircularProgressIndicator(color: Colors.blue),
          ),
        ),
      );
    }

    if (_error != null) {
      return _buildResultContainer(
        isDark,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Text(
              _error!,
              style: GoogleFonts.quicksand(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }

    if (_securityData == null) {
      return _buildResultContainer(
        isDark,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Text(
              "Paste a wallet, contract, or link to begin analysis",
              textAlign: TextAlign.center,
              style: GoogleFonts.quicksand(
                color: isDark ? Colors.white38 : Colors.black38,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    final borderColor = _isDetailsExpanded
        ? (_securityData!['status'] == "Safe"
              ? Colors.greenAccent
              : Colors.redAccent)
        : null;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: _buildResultContainer(
        isDark,
        borderColor: borderColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () =>
                  setState(() => _isDetailsExpanded = !_isDetailsExpanded),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Text(
                    "Security Overview",
                    style: GoogleFonts.quicksand(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildStatusIndicator(
                    _securityData!['status'],
                    _getStatusColor(_securityData!['status']),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _isDetailsExpanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.chevron_right,
                      color: isDark ? Colors.white54 : Colors.black45,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildAnalysisCard(isDark),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Column(
                  children: (_securityData!['details'] as List).map((detail) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _buildDetailRow(
                        isDark,
                        detail['icon'],
                        detail['label'],
                        detail['value'],
                      ),
                    );
                  }).toList(),
                ),
              ),
              crossFadeState: _isDetailsExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDomainOverviewCard(bool isDark) {
    if (_domainData == null) return const SizedBox.shrink();

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: _buildResultContainer(
        isDark,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () =>
                  setState(() => _isDomainExpanded = !_isDomainExpanded),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Text(
                    "Domain Overview",
                    style: GoogleFonts.quicksand(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _isDomainExpanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.chevron_right,
                      color: isDark ? Colors.white54 : Colors.black45,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Column(
                  children: [
                    _buildDetailRow(
                      isDark,
                      Icons.info_outline,
                      "WHOIS information for",
                      _domainData!['domain'],
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow(
                      isDark,
                      Icons.calendar_today,
                      "Domain Creation Date",
                      _domainData!['creationDate'],
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow(
                      isDark,
                      Icons.hourglass_empty,
                      "Domain Age",
                      "${_domainData!['ageDays']} days old",
                    ),
                  ],
                ),
              ),
              crossFadeState: _isDomainExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisCard(bool isDark) {
    if (_securityData?['analysis'] == null) return const SizedBox.shrink();
    
    final status = _securityData!['status'];
    final statusColor = _getStatusColor(status);
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                status == "Safe" ? Icons.verified_user : Icons.gpp_maybe,
                color: statusColor,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                "Risk Analysis Summary",
                style: GoogleFonts.quicksand(
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _securityData!['analysis'],
            style: GoogleFonts.quicksand(
              color: isDark ? Colors.white60 : Colors.black54,
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultContainer(
    bool isDark, {
    required Widget child,
    Color? borderColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.black.withOpacity(0.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color:
              borderColor ??
              (isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.2)),
          width: borderColor != null ? 2 : 1,
        ),
      ),
      child: child,
    );
  }

  Widget _buildStatusIndicator(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        status,
        style: GoogleFonts.quicksand(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    bool isDark,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.black.withOpacity(0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 25,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.quicksand(
                color: isDark ? Colors.white38 : Colors.black54,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: GoogleFonts.quicksand(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
