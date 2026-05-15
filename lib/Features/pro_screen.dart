import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../wallet/infrastructure/tenderly_service.dart';
import '../wallet/infrastructure/models/contract_intelligence.dart';

class SimulationScreen extends StatefulWidget {
  const SimulationScreen({super.key});

  @override
  State<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends State<SimulationScreen> {
  bool _overrideBlockNumber = false;
  bool _overrideTimestamp = false;
  bool _usePendingBlock = false;
  bool _isLoading = false;
  bool _isBlockHeaderExpanded = false;
  bool _isStateExpanded = false;

  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _blockController = TextEditingController();
  final TextEditingController _timestampController = TextEditingController();
  final TextEditingController _blockNumController = TextEditingController();
  final TextEditingController _txIndexController = TextEditingController();
  final TextEditingController _fromController = TextEditingController(text: "0x0000000000000000000000000000000000000000");
  final TextEditingController _gasController = TextEditingController(text: "8000000");
  final TextEditingController _gasPriceController = TextEditingController(text: "0");
  final TextEditingController _valueController = TextEditingController(text: "0");

  final TenderlyService _tenderly = TenderlyService();

  String _selectedNetwork = "Ethereum";
  final List<Map<String, String>> _networks = [
    {"name": "Ethereum", "symbol": "ETH", "color": "0xFF627EEA"},
    {"name": "Polygon", "symbol": "MATIC", "color": "0xFF8247E5"},
    {"name": "BSC", "symbol": "BNB", "color": "0xFFF3BA2F"},
    {"name": "Optimism", "symbol": "OP", "color": "0xFFFF0420"},
    {"name": "Arbitrum", "symbol": "ARB", "color": "0xFF28A0F0"},
    {"name": "Base", "symbol": "BASE", "color": "0xFF0052FF"},
  ];

  Future<void> _handleSimulate() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(seconds: 2));
    setState(() => _isLoading = false);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Simulation complete. Transaction results ready."),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF5F5F7);
    final cardColor = isDark ? const Color(0xFF151515) : Colors.white;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.blue),
              SizedBox(height: 24.h),
              Text(
                "Simulating...",
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24.r),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildModernHeader(isDark),
              SizedBox(height: 32.h),
              _buildSimulationPanel(isDark, cardColor),
              SizedBox(height: 24.h),
              _buildParametersPanel(isDark, cardColor),
              SizedBox(height: 40.h),
              _buildInfoFooter(isDark),
              SizedBox(height: 120.h),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernHeader(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: GoogleFonts.inter(
              fontSize: 34.sp,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black,
              height: 1.1,
            ),
            children: [
              const TextSpan(text: "Simulate any smart "),
              TextSpan(
                text: "contract",
                style: const TextStyle(color: Colors.blue),
              ),
            ],
          ),
        ),
        SizedBox(height: 10.h),
        Text(
          "Execute simulations to identify hidden security risks",
          style: GoogleFonts.inter(
            color: isDark ? Colors.white60 : Colors.black54,
            fontSize: 18.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildSimulationPanel(bool isDark, Color cardColor) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24.r),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader("Contract", Icons.code_rounded, isDark),
          SizedBox(height: 24.h),
          _buildAddressField(isDark),
          SizedBox(height: 24.h),
          Text(
            "Select network for this address",
            style: GoogleFonts.inter(
              fontSize: 16.sp,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
          SizedBox(height: 12.h),
          _buildNetworkDropdown(isDark),
        ],
      ),
    );
  }

  Widget _buildParametersPanel(bool isDark, Color cardColor) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24.r),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Transaction Parameters",
            style: GoogleFonts.inter(
              fontSize: 22.sp,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white.withOpacity(0.9) : Colors.black,
            ),
          ),
          SizedBox(height: 24.h),
          _buildOverrideToggle("Use Pending Block", _usePendingBlock, (v) => setState(() => _usePendingBlock = v), isDark),
          SizedBox(height: 16.h),
          _buildLabelInputField("Block Number", _blockNumController, isDark),
          SizedBox(height: 16.h),
          _buildLabelInputField("Tx Index", _txIndexController, isDark),
          SizedBox(height: 16.h),
          _buildLabelInputField("From", _fromController, isDark),
          SizedBox(height: 16.h),
          _buildLabelInputField("Gas", _gasController, isDark),
          Padding(
            padding: EdgeInsets.only(left: 120.w, top: 4.h),
            child: Text(
              "Use custom gas value",
              style: GoogleFonts.inter(color: Colors.blue, fontSize: 13.sp, fontWeight: FontWeight.w500),
            ),
          ),
          SizedBox(height: 16.h),
          _buildLabelInputField("Gas Price", _gasPriceController, isDark),
          SizedBox(height: 16.h),
          _buildLabelInputField("Value", _valueController, isDark),
          SizedBox(height: 32.h),
          const Divider(color: Colors.white10),
          SizedBox(height: 16.h),
          _buildNestedCollapsible(
            "Block Header Overrides",
            _isBlockHeaderExpanded,
            () => setState(() => _isBlockHeaderExpanded = !_isBlockHeaderExpanded),
            _buildBlockHeaderContent(isDark),
            isDark,
          ),
          SizedBox(height: 16.h),
          _buildNestedCollapsible(
            "State Overrides",
            _isStateExpanded,
            () => setState(() => _isStateExpanded = !_isStateExpanded),
            _buildStateOverridesContent(isDark),
            isDark,
          ),
          SizedBox(height: 40.h),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              height: 54.h,
              width: 220.w,
              child: ElevatedButton(
                onPressed: _handleSimulate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                ),
                child: Text(
                  "Simulate Transaction",
                  style: GoogleFonts.inter(fontSize: 16.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNestedCollapsible(String title, bool isExpanded, VoidCallback onTap, Widget content, bool isDark) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8.r),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8.h),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white.withOpacity(0.9) : Colors.black,
                  ),
                ),
                AnimatedRotation(
                  duration: const Duration(milliseconds: 200),
                  turns: isExpanded ? 0.25 : 0,
                  child: Icon(Icons.chevron_right, color: Colors.grey, size: 24.r),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Padding(
            padding: EdgeInsets.only(top: 16.h),
            child: content,
          ),
      ],
    );
  }

  Widget _buildBlockHeaderContent(bool isDark) {
    return Column(
      children: [
        _buildOverrideToggle("Override Block Number", _overrideBlockNumber, (v) => setState(() => _overrideBlockNumber = v), isDark),
        SizedBox(height: 16.h),
        _buildLabelInputField("Block Number", _blockController, isDark),
        SizedBox(height: 24.h),
        _buildOverrideToggle("Override Timestamp", _overrideTimestamp, (v) => setState(() => _overrideTimestamp = v), isDark),
        SizedBox(height: 16.h),
        _buildLabelInputField("Timestamp", _timestampController, isDark),
      ],
    );
  }

  Widget _buildStateOverridesContent(bool isDark) {
    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Text(
        "soon",
        style: GoogleFonts.inter(color: Colors.grey, fontSize: 14.sp),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData? icon, bool isDark) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: Colors.blue, size: 24.r),
          SizedBox(width: 16.w),
        ],
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 22.sp,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white.withOpacity(0.9) : Colors.black,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOverrideToggle(String label, bool value, ValueChanged<bool> onChanged, bool isDark) {
    return Row(
      children: [
        SizedBox(
          width: 44.w,
          height: 24.h,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.blue,
            activeTrackColor: Colors.blue.withOpacity(0.2),
            inactiveThumbColor: isDark ? Colors.white24 : Colors.grey.shade400,
            inactiveTrackColor: isDark ? Colors.white10 : Colors.black12,
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 16.sp,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLabelInputField(String label, TextEditingController controller, bool isDark) {
    return Row(
      children: [
        SizedBox(
          width: 120.w,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 15.sp,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 48.h,
            decoration: BoxDecoration(
              color: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
            ),
            child: TextField(
              controller: controller,
              style: GoogleFonts.inter(color: isDark ? Colors.white : Colors.black, fontSize: 15.sp),
              cursorColor: Colors.blue,
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16.w),
                hintText: "/",
                hintStyle: TextStyle(color: isDark ? Colors.white12 : Colors.black12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddressField(bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12.r),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
          ),
          child: TextField(
            controller: _addressController,
            cursorColor: Colors.blue,
            style: GoogleFonts.inter(color: isDark ? Colors.white : Colors.black, fontSize: 16.sp),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 18.h),
              hintText: "Paste contract address",
              hintStyle: GoogleFonts.inter(color: isDark ? Colors.white12 : Colors.black12, fontSize: 16.sp),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNetworkDropdown(bool isDark) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.2) : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedNetwork,
          isExpanded: true,
          dropdownColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey, size: 24.r),
          onChanged: (String? newValue) {
            if (newValue != null) setState(() => _selectedNetwork = newValue);
          },
          items: _networks.map<DropdownMenuItem<String>>((Map<String, String> network) {
            return DropdownMenuItem<String>(
              value: network["name"],
              child: Row(
                children: [
                  Container(
                    width: 24.w,
                    height: 24.h,
                    decoration: BoxDecoration(
                      color: Color(int.parse(network["color"]!)),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        network["symbol"]![0],
                        style: TextStyle(color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Text(
                    network["name"]!,
                    style: GoogleFonts.inter(
                      fontSize: 16.sp,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildInfoFooter(bool isDark) {
    return Container(
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.blue.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.blue, size: 24.r),
          SizedBox(width: 16.w),
          Expanded(
            child: Text(
              "Execution overrides allow you to test contract behavior under custom network conditions.",
              style: GoogleFonts.inter(
                color: isDark ? Colors.white60 : Colors.black54,
                fontSize: 14.sp,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
