import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;
  String _errorMessage = '';
  String _successMessage = '';
  bool _obscurePassword = true;
  bool _isVerificationSent = false;

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your email to reset password';
        _successMessage = '';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _successMessage = '';
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      setState(() {
        _successMessage = 'Password reset email sent! Check your inbox.';
      });
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = e.message ?? 'An error occurred';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'An unexpected error occurred';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final username = _usernameController.text.trim();

    if (email.isEmpty || password.isEmpty || (!_isLogin && username.isEmpty)) {
      setState(() {
        if (!_isLogin && username.isEmpty) {
          _errorMessage = 'Please enter a username';
        } else {
          _errorMessage = 'Please enter email and password';
        }
        _successMessage = '';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _successMessage = '';
    });

    try {
      if (_isLogin) {
        UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        if (userCredential.user != null && !userCredential.user!.emailVerified) {
          await userCredential.user!.sendEmailVerification();
          setState(() {
            _isVerificationSent = true;
            _successMessage = 'Please verify your email. A link has been sent.';
          });
        }
      } else {
        UserCredential userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
        await userCredential.user?.updateDisplayName(username);
        await userCredential.user?.sendEmailVerification();
        setState(() {
          _isVerificationSent = true;
          _successMessage = 'Account created! Please check your email for a verification link.';
        });
      }
    } on FirebaseAuthException catch (e) {
      debugPrint("FirebaseAuthException code: ${e.code}");
      setState(() {
        if (e.code == 'invalid-credential' ||
            e.code == 'wrong-password' ||
            e.code == 'user-not-found') {
          _errorMessage = 'The credentials are incorrect';
        } else {
          _errorMessage = e.message ?? 'An error occurred';
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [const Color(0xFF121212), const Color(0xFF1A1A1A)]
                    : [const Color(0xFFFFFBFE), const Color(0xFFF3E5F5)],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo/Title
                    Container(
                      height: 100,
                      width: 100,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        image: DecorationImage(
                          image: AssetImage('1024.png'),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      "RiskLens",
                      style: GoogleFonts.quicksand(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isLogin ? "Welcome Back" : "Create an account",
                      style: GoogleFonts.quicksand(
                        fontSize: 20,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Auth Form
                    if (!_isLogin) ...[
                      _buildGlassTextField(
                        controller: _usernameController,
                        hintText: "Username",
                        icon: Icons.person_outline,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 16),
                    ],
                    _buildGlassTextField(
                      controller: _emailController,
                      hintText: "Email",
                      icon: Icons.email_outlined,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 16),
                    _buildGlassTextField(
                      controller: _passwordController,
                      hintText: "Password",
                      icon: Icons.lock_outline,
                      isDark: isDark,
                      isPassword: true,
                    ),
                    if (_isVerificationSent) ...[
                      const SizedBox(height: 24),
                      Text(
                        "Verification link sent to ${_emailController.text}",
                        style: const TextStyle(color: Colors.blue, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          await FirebaseAuth.instance.currentUser?.reload();
                          if (FirebaseAuth.instance.currentUser?.emailVerified ?? false) {
                            if (mounted) Navigator.of(context).pushReplacementNamed('/');
                          } else {
                            setState(() {
                              _errorMessage = "Email not verified yet. Please check your inbox.";
                            });
                          }
                        },
                        child: const Text(
                          "I have verified my email",
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ],
                    if (_isLogin)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _isLoading ? null : _resetPassword,
                          child: Text(
                            "Forgot Password?",
                            style: TextStyle(
                              color: Colors.blue.withOpacity(0.8),
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                    if (_errorMessage.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (_successMessage.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        _successMessage,
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 32),

                    // Submit Button
                    if (!_isVerificationSent)
                      _buildGlassButton(
                        onTap: _submit,
                        text: _isLogin ? "Login" : "Sign Up",
                        isDark: isDark,
                        isLoading: _isLoading,
                      ),
                    const SizedBox(height: 16),

                    // Toggle Button
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isLogin = !_isLogin;
                          _isVerificationSent = false;
                          _errorMessage = '';
                          _successMessage = '';
                        });
                      },
                      child: Text(
                        _isLogin
                            ? "Don't have an account? Sign Up"
                            : "Already have an account? Login",
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required bool isDark,
    bool isPassword = false,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.black.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.1),
            ),
          ),
          child: TextField(
            controller: controller,
            obscureText: isPassword ? _obscurePassword : false,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 18,
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: Colors.blue),
              suffixIcon: isPassword
                  ? IconButton(
                      iconSize: 28,
                      splashRadius: 24,
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.blue.withOpacity(0.7),
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    )
                  : null,
              hintText: hintText,
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 19),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(20),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassButton({
    required VoidCallback onTap,
    required String text,
    required bool isDark,
    bool isLoading = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: Colors.blue.withOpacity(0.8),
            child: InkWell(
              onTap: isLoading ? null : onTap,
              splashColor: Colors.white.withOpacity(0.2),
              highlightColor: Colors.white.withOpacity(0.1),
              child: Container(
                width: double.infinity,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Center(
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 25,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
