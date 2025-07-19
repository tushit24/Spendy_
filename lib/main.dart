import 'package:flutter/material.dart';

void main() {
  runApp(const SpendyApp());
}

class SpendyApp extends StatelessWidget {
  const SpendyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spendy Login',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF1F2937), // gray-800
        fontFamily: 'Inter',
      ),
      home: const LoginPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isPasswordVisible = false;
  bool _rememberMe = false; // State for the checkbox
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Define colors from the theme
  static const Color spendyRed = Color(0xFFEF4444);
  static const Color spendyYellow = Color(0xFFFBBF24);
  static const Color bgColor = Color(0xFF1F2937); // gray-800
  static const Color formBgColor = Color(0xFF111827); // gray-900
  static const Color fieldBgColor = Color(0xFF1F2937); // gray-800
  static const Color borderColor = Color(0xFF4B5563); // gray-600
  static const Color textColor = Colors.white;
  static const Color hintColor = Color(0xFF9CA3AF); // gray-400

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 48.0,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Header: Logo and Title
                  // THIS IS THE FIX: Use Image.asset for local project images
                  Image.asset(
                    'assets/mario.jpg', // Use the asset path
                    height: 80,
                    errorBuilder: (context, error, stackTrace) {
                      // This will show if the asset isn't found.
                      // Check your pubspec.yaml and file path.
                      print(error); // Helps with debugging
                      return const Icon(
                        Icons.image_not_supported,
                        size: 64,
                        color: hintColor,
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'SPENDY',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      // Assuming you have this font, otherwise change it
                      fontFamily: 'PressStart2P',
                      fontSize: 32,
                      color: textColor,
                      letterSpacing: -1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Sign in to track your coins',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: hintColor),
                  ),
                  const SizedBox(height: 32),

                  // Login Form Container
                  Container(
                    padding: const EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      color: formBgColor.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(16.0),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Email Input
                        _buildTextField(
                          controller: _emailController,
                          hintText: 'Email address',
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 24),

                        // Password Input
                        _buildTextField(
                          controller: _passwordController,
                          hintText: 'Password',
                          obscureText: !_isPasswordVisible,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isPasswordVisible
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: hintColor,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordVisible = !_isPasswordVisible;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Remember Me & Forgot Password
                        _buildExtraOptions(),
                        const SizedBox(height: 24),

                        // Login Button
                        _buildLoginButton(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Sign Up Link
                  _buildSignUpLink(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(color: textColor),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: hintColor),
        filled: true,
        fillColor: fieldBgColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
          borderSide: const BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
          borderSide: const BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
          borderSide: const BorderSide(color: spendyYellow, width: 2.0),
        ),
        suffixIcon: suffixIcon,
      ),
    );
  }

  Widget _buildExtraOptions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              _rememberMe = !_rememberMe;
            });
          },
          child: Row(
            children: [
              SizedBox(
                height: 24.0,
                width: 24.0,
                child: Checkbox(
                  value: _rememberMe,
                  onChanged: (bool? value) {
                    setState(() {
                      _rememberMe = value ?? false;
                    });
                  },
                  activeColor: spendyRed,
                  checkColor: textColor,
                  side: const BorderSide(color: borderColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Remember me',
                style: TextStyle(color: hintColor, fontSize: 14),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () {},
          child: const Text(
            'Forgot password?',
            style: TextStyle(
              color: spendyYellow,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    return ElevatedButton(
      onPressed: () {
        // Handle login logic here
        final email = _emailController.text;
        final password = _passwordController.text;
        print(
          'Login attempt with Email: $email, Password: $password, Remember Me: $_rememberMe',
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: spendyRed,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      ),
      child: const Text(
        'Sign in',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildSignUpLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          "Don't have an account? ",
          style: TextStyle(color: hintColor, fontSize: 14),
        ),
        TextButton(
          onPressed: () {},
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'Sign up',
            style: TextStyle(
              color: spendyYellow,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
