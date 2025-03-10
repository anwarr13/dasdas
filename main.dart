import 'package:flutter/material.dart';
import 'mood_category.dart';
import 'signup_screen.dart'; // Import the signup screen
import 'package:firebase_core/firebase_core.dart'; // Import Firebase core
import 'package:firebase_auth/firebase_auth.dart'; // Import Firebase authentication
import 'firebase_options.dart'; // Import the Firebase options
import 'package:cloud_firestore/cloud_firestore.dart';
import 'superadmin.dart'; // Import the superadmin dashboard
import 'bar_owner_dashboard.dart'; // Import bar owner dashboard
import 'forgot_password_screen.dart'; // Import forgot password screen

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LoginScreen(), // Show login screen by default
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isPasswordVisible = false;

  Future<void> _validateAndLogin() async {
    if (_formKey.currentState!.validate()) {
      try {
        // Show loading indicator
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );

        // Attempt login
        final UserCredential userCredential =
            await _auth.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        // Remove loading indicator
        if (!mounted) return;
        Navigator.pop(context);

        // Get user data
        final DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .get();

        if (!mounted) return;

        // Check if user exists
        if (!userDoc.exists) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User data not found'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        // Get user role and prepare navigation
        final userData = userDoc.data() as Map<String, dynamic>;
        final String? role = userData['role'];

        // Validate role
        if (role == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid user role. Please contact support.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        Widget destinationScreen;
        String welcomeMessage;

        switch (role) {
          case 'superadmin':
            destinationScreen = const SuperAdminDashboard();
            welcomeMessage = 'Welcome, Super Admin!';
            break;
          case 'bar_owner':
            // Check if bar owner is approved
            final bool isApproved = userData['approved'] ?? false;
            if (!isApproved) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Your account is pending approval from LGU.'),
                  backgroundColor: Colors.orange,
                ),
              );
              return;
            }
            destinationScreen = const BarOwnerDashboard();
            welcomeMessage = 'Welcome, Bar Owner!';
            break;
          case 'user':
            destinationScreen = const MoodCategoryScreen();
            welcomeMessage = 'Welcome back!';
            break;
          default:
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Invalid user role. Please contact support.'),
                backgroundColor: Colors.red,
              ),
            );
            return;
        }

        // Show success dialog
        if (!mounted) return;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Login Successful'),
            content: Text(welcomeMessage),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => destinationScreen),
                  );
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } on FirebaseAuthException catch (e) {
        // Remove loading indicator if still showing
        if (!mounted) return;
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                e.code == 'user-not-found' || e.code == 'wrong-password'
                    ? 'Wrong email or password'
                    : e.message ?? 'Login failed'),
            backgroundColor: Colors.red,
          ),
        );
      } catch (e) {
        // Handle any other errors
        if (!mounted) return;
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An error occurred: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _togglePasswordVisibility() {
    setState(() {
      _isPasswordVisible = !_isPasswordVisible;
    });
  }

  // Create superadmin account
  // Future<void> createSuperAdmin() async {
  //   try {
  //     // Create superadmin credentials
  //     UserCredential userCredential =
  //         await _auth.createUserWithEmailAndPassword(
  //       email: 'anwarrjervis@gmail.com',
  //       password: 'superAdmin',
  //     );

  //     // Add superadmin data to Firestore
  //     await FirebaseFirestore.instance
  //         .collection('users')
  //         .doc(userCredential.user!.uid)
  //         .set({
  //       'email': 'anwarrjervis@gmail.com',
  //       'role': 'superadmin',
  //       'name': 'Super Admin',
  //       'createdAt': DateTime.now(),
  //     });

  //     // Show success message
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(
  //           content: Text('Superadmin account created successfully!'),
  //           backgroundColor: Colors.green,
  //         ),
  //       );
  //     }
  //   } catch (e) {
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('Error creating superadmin: ${e.toString()}'),
  //           backgroundColor: Colors.red,
  //         ),
  //       );
  //     }
  //   }
  // }

  @override
  void initState() {
    super.initState();
    // createSuperAdmin();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.asset(
              'assets/bg7.jpg', // Replace with your background image
              fit: BoxFit.cover,
            ),
          ),
          // Login form
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85, // Adaptive width
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Welcome Back!',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Email TextField
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your email';
                          } else if (!RegExp(r'^[^@]+@[^@]+\.[^@]+')
                              .hasMatch(value)) {
                            return 'Enter a valid email address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      // Password TextField
                      TextFormField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: GestureDetector(
                            onTap: _togglePasswordVisibility,
                            child: Icon(
                              _isPasswordVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                          ),
                        ),
                        obscureText: !_isPasswordVisible,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your password';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 4),
                      // Forgot Password Link
                      Align(
                        alignment: Alignment.center,
                        child: TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const ForgotPasswordScreen(),
                              ),
                            );
                          },
                          child: Text(
                            'Forgot Password?',
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Login Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _validateAndLogin,
                          style: ButtonStyle(
                            backgroundColor:
                                MaterialStateProperty.all(Colors.blue),
                            shape: MaterialStateProperty.all(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                            padding: MaterialStateProperty.all(
                              const EdgeInsets.symmetric(vertical: 15),
                            ),
                          ),
                          child: Text(
                            'Login',
                            style: TextStyle(fontSize: 16, color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Signup link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Don't have an account? "),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => SignupScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              'Sign Up',
                              style: TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
