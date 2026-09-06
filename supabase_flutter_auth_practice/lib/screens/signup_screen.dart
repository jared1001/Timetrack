import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _fullNameController = TextEditingController();
  final _employeeNumberController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasNumber = false;
  bool _hasSpecial = false;

  void _checkPassword(String password) {
    setState(() {
      _hasMinLength = password.length >= 8;
      _hasUppercase = RegExp(r'[A-Z]').hasMatch(password);
      _hasLowercase = RegExp(r'[a-z]').hasMatch(password);
      _hasNumber = RegExp(r'[0-9]').hasMatch(password);
      _hasSpecial = RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password);
    });
  }

  bool get _isStrongPassword {
    return _hasMinLength &&
        _hasUppercase &&
        _hasLowercase &&
        _hasNumber &&
        _hasSpecial;
  }

  Future<void> _signUp() async {
    if (_fullNameController.text.trim().isEmpty ||
        _employeeNumberController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields.')),
      );
      return;
    }

    final email = _emailController.text.trim();

    if (!RegExp(r'^[^\s@]+@gmail\.com$', caseSensitive: false).hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please use a valid @gmail.com email.')),
      );
      return;
    }

    if (!_isStrongPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create a stronger password.')),
      );
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Passwords do not match.')));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _authService.signUp(
        email: email,
        password: _passwordController.text,
        fullName: _fullNameController.text.trim(),
        employeeNumber: _employeeNumberController.text.trim(),
      );

      if (response.user == null) {
        throw Exception('Account creation failed.');
      }

      if (!mounted) return;

      await Supabase.instance.client.auth.signOut();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    } on AuthException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Something went wrong: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _passwordRequirement(String text, bool satisfied) {
    return Row(
      children: [
        Icon(satisfied ? Icons.check_circle : Icons.cancel, size: 18),
        const SizedBox(width: 8),
        Text(text),
      ],
    );
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _employeeNumberController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xffe9edf4),
                borderRadius: BorderRadius.circular(26),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x409ba8bb),
                    offset: Offset(10, 10),
                    blurRadius: 24,
                  ),
                  BoxShadow(
                    color: Colors.white,
                    offset: Offset(-8, -8),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Column(
          children: [
            const Text(
              'Create your account',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Set up your TimeTrack employee profile.',
              style: TextStyle(color: Colors.blueGrey),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _fullNameController,
              decoration: const InputDecoration(labelText: 'Full Name'),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _employeeNumberController,
              decoration: const InputDecoration(labelText: 'Employee Number'),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              onChanged: _checkPassword,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
            ),

            const SizedBox(height: 12),

            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _passwordRequirement('At least 8 characters', _hasMinLength),
                  _passwordRequirement(
                    'At least 1 uppercase letter',
                    _hasUppercase,
                  ),
                  _passwordRequirement(
                    'At least 1 lowercase letter',
                    _hasLowercase,
                  ),
                  _passwordRequirement('At least 1 number', _hasNumber),
                  _passwordRequirement(
                    'At least 1 special character',
                    _hasSpecial,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              decoration: InputDecoration(
                labelText: 'Confirm Password',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureConfirmPassword = !_obscureConfirmPassword;
                    });
                  },
                ),
              ),
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _signUp,
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(),
                      )
                    : const Text('Sign Up'),
              ),
            ),
          ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
