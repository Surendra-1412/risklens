import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';

class ProScreen extends StatelessWidget {
  const ProScreen({super.key});

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
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(44),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 30,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.06)
                                : Colors.black.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(44),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withOpacity(0.12)
                                  : Colors.black.withOpacity(0.12),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Extra large image centered
                              Image.asset(
                                'pro.png',
                                height: 330,
                                width: 330,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(height: 0),
                              Row(
                                children: [
                                  Expanded(
                                    child: RichText(
                                      textAlign: TextAlign.left,
                                      text: TextSpan(
                                        style: GoogleFonts.inter(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black,
                                          letterSpacing: -0.5,
                                        ),
                                        children: [
                                          const TextSpan(
                                            text: "Get full wallet ",
                                          ),
                                          const TextSpan(
                                            text: "protection",
                                            style: TextStyle(
                                              color: Colors.blue,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.white.withOpacity(0.08)
                                          : Colors.black.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isDark
                                            ? Colors.white.withOpacity(0.1)
                                            : Colors.black.withOpacity(0.1),
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "\$6.66",
                                          style: GoogleFonts.inter(
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 20,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          "Billed monthly",
                                          style: GoogleFonts.inter(
                                            color: Colors.grey,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 40),

                              // Features list
                              _buildFeatureRow(
                                context,
                                "Integrated AI chatbot",
                                isDark,
                              ),
                              const SizedBox(height: 18),
                              _buildFeatureRow(
                                context,
                                "Get risk alerts",
                                isDark,
                              ),
                              const SizedBox(height: 18),
                              _buildFeatureRow(
                                context,
                                "Exclusive security analysis",
                                isDark,
                              ),
                              const SizedBox(height: 18),
                              _buildFeatureRow(
                                context,
                                "Unlimited wallet tracking",
                                isDark,
                              ),

                              const SizedBox(height: 50),

                              // Button
                              SizedBox(
                                width: double.infinity,
                                height: 70,
                                child: ElevatedButton(
                                  onPressed: () {},
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(22),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: Text(
                                    "Get Pro plan",
                                    style: GoogleFonts.inter(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow(BuildContext context, String text, bool isDark) {
    return Row(
      children: [
        const Icon(Icons.check_circle, color: Colors.greenAccent, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 20,
              color: isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
