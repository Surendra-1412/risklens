import 'package:flutter/material.dart';
import 'dart:async';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'ledger_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isNavigating = false;
  bool _isInvalid = false;
  Timer? _resetTimer;
  TorchState _torchState = TorchState.off;

  @override
  void dispose() {
    _resetTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  bool _isValidAddress(String address) {
    final cleanAddr = address.trim();
    if (cleanAddr.isEmpty) return false;

    // Ethereum / EVM
    if (cleanAddr.startsWith("0x") && cleanAddr.length == 42) {
      return true;
    }

    // Bitcoin
    if (cleanAddr.startsWith("1") ||
        cleanAddr.startsWith("3") ||
        cleanAddr.startsWith("bc1")) {
      // BTC addresses are typically 26-62 chars
      if (cleanAddr.length >= 26 && cleanAddr.length <= 62) {
        return true;
      }
    }

    // Solana
    // Base58 characters: 123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz
    if (cleanAddr.length >= 32 && cleanAddr.length <= 44) {
      final base58Regex = RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$');
      if (base58Regex.hasMatch(cleanAddr)) {
        return true;
      }
    }

    return false;
  }

  void _onDetect(String code) {
    if (_isNavigating || _isInvalid) return;

    if (_isValidAddress(code)) {
      setState(() => _isNavigating = true);
      _controller.stop();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => LedgerScreen(initialAddress: code),
        ),
      );
    } else {
      setState(() => _isInvalid = true);
      _resetTimer?.cancel();
      _resetTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() => _isInvalid = false);
        }
      });
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      final barcodes = await _controller.analyzeImage(image.path);
      if (barcodes != null && barcodes.barcodes.isNotEmpty) {
        final code = barcodes.barcodes.first.displayValue;
        if (code != null) {
          _onDetect(code);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Fullscreen Scanner
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.displayValue != null) {
                  _onDetect(barcode.displayValue!);
                }
              }
            },
          ),

          // Removed dimmed background for clearer view

          // Scanner Border and Animation
          Center(
            child: SizedBox(
              height: 250.h,
              width: 250.w,
              child: CustomPaint(
                painter: _ScannerCornerPainter(
                  color: _isNavigating
                      ? Colors.blue
                      : (_isInvalid ? Colors.red : Colors.white),
                ),
              ),
            ),
          ),

          // Invalid QR Capsule
          if (_isInvalid)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.45,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 24.w,
                    vertical: 10.h,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(30.r),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10.r,
                        offset: Offset(0, 4.h),
                      ),
                    ],
                  ),
                  child: Text(
                    "Invalid QR",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),

          // Top Controls
          Positioned(
            top: 50.h,
            left: 20.w,
            right: 20.w,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _circularButton(
                  icon: Icons.arrow_back,
                  onTap: () => Navigator.pop(context),
                ),
                Column(
                  children: [
                    _circularButton(
                      icon: _torchState == TorchState.on
                          ? Icons.flashlight_on
                          : Icons.flashlight_off,
                      onTap: () async {
                        await _controller.toggleTorch();
                        if (mounted) {
                          setState(() {
                            _torchState = _torchState == TorchState.on
                                ? TorchState.off
                                : TorchState.on;
                          });
                        }
                      },
                    ),
                    SizedBox(height: 16.h),
                    _circularButton(
                      icon: Icons.photo_library,
                      onTap: _pickImage,
                      size: 48.w,
                      iconSize: 24.w,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bottom Controls & Text
          Positioned(
            bottom: 60.h,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  "Scan to track",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30.sp, 
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _circularButton({
    required IconData icon,
    required VoidCallback onTap,
    double? size,
    double? iconSize,
  }) {
    double btnSize = size ?? 48.w;
    double iSize = iconSize ?? 24.w;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: btnSize,
        width: btnSize,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: iSize),
      ),
    );
  }
}

class _ScannerCornerPainter extends CustomPainter {
  final Color color;
  _ScannerCornerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLength = 30.0;
    const radius = 24.0;

    // Top Left
    final topLeftPath = Path()
      ..moveTo(0, cornerLength)
      ..lineTo(0, radius)
      ..arcToPoint(
        const Offset(radius, 0),
        radius: const Radius.circular(radius),
      )
      ..lineTo(cornerLength, 0);
    canvas.drawPath(topLeftPath, paint);

    // Top Right
    final topRightPath = Path()
      ..moveTo(size.width - cornerLength, 0)
      ..lineTo(size.width - radius, 0)
      ..arcToPoint(
        Offset(size.width, radius),
        radius: const Radius.circular(radius),
      )
      ..lineTo(size.width, cornerLength);
    canvas.drawPath(topRightPath, paint);

    // Bottom Left
    final bottomLeftPath = Path()
      ..moveTo(0, size.height - cornerLength)
      ..lineTo(0, size.height - radius)
      ..arcToPoint(
        Offset(radius, size.height),
        radius: const Radius.circular(radius),
        clockwise: false,
      )
      ..lineTo(cornerLength, size.height);
    canvas.drawPath(bottomLeftPath, paint);

    // Bottom Right
    final bottomRightPath = Path()
      ..moveTo(size.width, size.height - cornerLength)
      ..lineTo(size.width, size.height - radius)
      ..arcToPoint(
        Offset(size.width - radius, size.height),
        radius: const Radius.circular(radius),
      )
      ..lineTo(size.width - cornerLength, size.height);
    canvas.drawPath(bottomRightPath, paint);
  }

  @override
  bool shouldRepaint(covariant _ScannerCornerPainter oldDelegate) =>
      oldDelegate.color != color;
}
