import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:blog/pages/login.dart';
import 'package:blog/services/auth_service.dart';

void main() {
  runApp(const Signup());
}

class Signup extends StatelessWidget {
  const Signup({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sign up',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SimpleFormPage(),
    );
  }
}

class SimpleFormPage extends StatefulWidget {
  const SimpleFormPage({super.key});

  @override
  State<SimpleFormPage> createState() => _SimpleFormPageState();
}

class _SimpleFormPageState extends State<SimpleFormPage> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ==========================================================
  // SIGN UP WITHOUT SUPABASE AUTH
  // ==========================================================

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      // ======================================================
      // GENERATE USER ID
      // ======================================================

      final randomId = DateTime.now().millisecondsSinceEpoch;

      // ======================================================
      // HASH PASSWORD
      // ======================================================

      final hashedPassword = hashPassword(password);

      // ======================================================
      // INSERT DIRECTLY INTO USERS TABLE
      // NO SUPABASE AUTH ACCOUNT IS CREATED
      // ======================================================

      await Supabase.instance.client.from('users').insert({
        'id': randomId,
        'email': email,
        'password': hashedPassword,
      });

      if (!mounted) return;

      // ======================================================
      // SUCCESS MESSAGE
      // ======================================================

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created successfully!')),
      );

      // ======================================================
      // GO TO LOGIN
      // ======================================================

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const Login()),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Database error: ${e.message}')));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unexpected error: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ==================================================
              // LOGO + TITLE
              // ==================================================
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.asset(
                            'assets/images/jv_logo.png',
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: const Icon(Icons.person),
                              );
                            },
                          ),
                        ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: Text(
                            'Jerome Vlog',
                            style: Theme.of(context).textTheme.headlineSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ==================================================
              // SIGN UP FORM
              // ==================================================
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // ==================================================
                          // CREATE ACCOUNT TITLE
                          // ==================================================
                          const Center(
                            child: Text(
                              'Create an account',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // ==================================================
                          // EMAIL
                          // ==================================================
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: SizedBox(
                              width: double.infinity,
                              child: TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.email),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter your email';
                                  }

                                  if (!value.contains('@')) {
                                    return 'Please enter a valid email';
                                  }

                                  return null;
                                },
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // ==================================================
                          // PASSWORD
                          // ==================================================
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: SizedBox(
                              width: double.infinity,
                              child: TextFormField(
                                controller: _passwordController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'Password',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.lock),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter a password';
                                  }

                                  if (value.length < 6) {
                                    return 'Password must be at least 6 characters';
                                  }

                                  return null;
                                },
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // ==================================================
                          // SIGN UP BUTTON
                          // ==================================================
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isSubmitting ? null : _submitForm,
                                child: Text(
                                  _isSubmitting
                                      ? 'Creating account...'
                                      : 'Sign Up',
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // ==================================================
                          // LOGIN
                          // ==================================================
                          TextButton(
                            onPressed: _isSubmitting
                                ? null
                                : () {
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const Login(),
                                      ),
                                    );
                                  },
                            child: const Text(
                              'Already have an account? Log in hehe',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
