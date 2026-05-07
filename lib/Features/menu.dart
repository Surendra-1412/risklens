import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

class MenuButton extends StatelessWidget {
  const MenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.menu),
      iconSize: 28,
      splashRadius: 24,
      onPressed: () => Scaffold.of(context).openDrawer(),
    );
  }
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Drawer(
      child: Container(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.8),
              ),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, color: Colors.blue, size: 40),
              ),
              accountName: Text(
                "RiskLens User",
                style: GoogleFonts.quicksand(fontWeight: FontWeight.bold),
              ),
              accountEmail: Text(
                FirebaseAuth.instance.currentUser?.email ?? "No Email",
                style: GoogleFonts.quicksand(),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home, color: Colors.blue),
              title: Text("Home", style: GoogleFonts.quicksand()),
              onTap: () => Navigator.pop(context),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: Text("Logout",
                  style: GoogleFonts.quicksand(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                FirebaseAuth.instance.signOut();
              },
            ),
          ],
        ),
      ),
    );
  }
}
