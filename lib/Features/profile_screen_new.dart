import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "Profile",
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Center(
              child: CircleAvatar(
                radius: 60,
                backgroundColor: isDark ? Colors.white12 : Colors.black12,
                child: Text(
                  (user?.displayName ?? user?.email ?? "U")
                      .substring(0, 1)
                      .toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              user?.displayName ?? "User Name",
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            Text(
              user?.email ?? "No Email",
              style: GoogleFonts.inter(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 48),
            _buildProfileOption(
              context,
              icon: Icons.security,
              title: "Security Settings",
              isDark: isDark,
            ),
            _buildProfileOption(
              context,
              icon: Icons.notifications,
              title: "Alert Preferences",
              isDark: isDark,
            ),
            _buildProfileOption(
              context,
              icon: Icons.history,
              title: "Scan History",
              isDark: isDark,
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.withOpacity(0.1),
                  foregroundColor: Colors.redAccent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  "Logout",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.blue),
            const SizedBox(width: 16),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right,
              color: isDark ? Colors.white38 : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}
