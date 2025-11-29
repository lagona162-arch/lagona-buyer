import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'customer_registration_page.dart';
import '../services/supabase_service.dart';
import 'login_page.dart';
import '../widgets/buyer_loading.dart';

class RegisterPage extends StatefulWidget {
  static const String routeName = '/register-auth';
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController middleInitialController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool isLoading = false;
  bool _obscurePassword = true;
  DateTime? selectedBirthdate;
  final SupabaseService _supabase = SupabaseService();

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  String? _validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  PasswordStrength _getPasswordStrength(String password) {
    if (password.isEmpty) return PasswordStrength.none;
    if (password.length < 6) return PasswordStrength.weak;
    if (password.length < 8) return PasswordStrength.fair;
    if (RegExp(r'[A-Z]').hasMatch(password) && 
        RegExp(r'[a-z]').hasMatch(password) && 
        RegExp(r'[0-9]').hasMatch(password)) {
      return PasswordStrength.strong;
    }
    return PasswordStrength.fair;
  }

  Future<void> _selectBirthdate() async {
    final DateTime now = DateTime.now();
    final DateTime firstDate = DateTime(now.year - 100);
    final DateTime lastDate = DateTime(now.year - 13); 
    
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedBirthdate ?? lastDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Select your birthdate',
    );
    if (picked != null && picked != selectedBirthdate) {
      setState(() {
        selectedBirthdate = picked;
      });
    }
  }

  Future<void> submit() async {
    if (!_formKey.currentState!.validate()) {
      debugPrint('Registration form validation failed');
      return;
    }
    
    setState(() => isLoading = true);
    
    
    debugPrint('=== Registration Attempt ===');
    debugPrint('Email: ${emailController.text.trim()}');
    debugPrint('Password length: ${passwordController.text.length}');
    debugPrint('First Name: ${firstNameController.text.trim()}');
    debugPrint('Last Name: ${lastNameController.text.trim()}');
    debugPrint('Middle Initial: ${middleInitialController.text.trim()}');
    debugPrint('Birthdate: $selectedBirthdate');
    debugPrint('===========================');
    
    try {
      await _supabase.signUpWithPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
        firstName: firstNameController.text.trim(),
        lastName: lastNameController.text.trim(),
        middleInitial: middleInitialController.text.trim().isNotEmpty 
            ? middleInitialController.text.trim().toUpperCase() 
            : null,
        birthdate: selectedBirthdate,
      );
      
      debugPrint('✅ Registration successful!');
      
      if (!mounted) return;
      
      Navigator.of(context).pushReplacementNamed(CustomerRegistrationPage.routeName);
    } catch (e, stackTrace) {
      
      debugPrint('❌ Registration Error Occurred:');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error message: ${e.toString()}');
      debugPrint('Error details: $e');
      debugPrint('Stack trace: $stackTrace');
      
      
      if (e.toString().contains('password') || e.toString().contains('Password')) {
        debugPrint('🔒 Password-related error detected');
        debugPrint('Password constraints might be violated');
      }
      
      if (!mounted) return;
      
      
      String errorMessage = e.toString().replaceAll('Exception: ', '');
      if (errorMessage.contains('password')) {
        errorMessage = 'Password does not meet requirements. Please check the password rules.';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registration failed: $errorMessage'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    middleInitialController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.background,
          extendBodyBehindAppBar: false,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: Colors.transparent,
            elevation: 0,
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary,
                    AppColors.primaryDark,
                  ],
                ),
              ),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.shopping_bag,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Join Lagona',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 20),
                      
                      Column(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.shopping_bag_outlined,
                              size: 40,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Join Lagona Today',
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Start shopping from local merchants\nand get your orders delivered fast',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.star, size: 18, color: AppColors.primary),
                                const SizedBox(width: 8),
                                Text(
                                  'What you\'ll get:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildBenefit('Fast delivery from local merchants'),
                            _buildBenefit('Exclusive deals and discounts'),
                            _buildBenefit('Track your orders in real-time'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      
                      TextFormField(
                        controller: firstNameController,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'First Name',
                          prefixIcon: const Icon(Icons.person_outline, color: AppColors.textSecondary),
                          helperText: 'Your given name',
                          helperStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        validator: (value) => _validateRequired(value, 'First name'),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: middleInitialController,
                        textInputAction: TextInputAction.next,
                        maxLength: 1,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: 'Middle Initial (Optional)',
                          prefixIcon: const Icon(Icons.badge_outlined, color: AppColors.textSecondary),
                          helperText: 'Optional middle initial',
                          helperStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: lastNameController,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Last Name',
                          prefixIcon: const Icon(Icons.person_outline, color: AppColors.textSecondary),
                          helperText: 'Your family name',
                          helperStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        validator: (value) => _validateRequired(value, 'Last name'),
                      ),
                      const SizedBox(height: 20),
                      InkWell(
                        onTap: _selectBirthdate,
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Birthdate',
                            prefixIcon: const Icon(Icons.calendar_today_outlined, color: AppColors.textSecondary),
                            helperText: 'Select your date of birth',
                            helperStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            suffixIcon: const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
                          ),
                          child: Text(
                            selectedBirthdate != null
                                ? '${selectedBirthdate!.year}-${selectedBirthdate!.month.toString().padLeft(2, '0')}-${selectedBirthdate!.day.toString().padLeft(2, '0')}'
                                : 'Select birthdate',
                            style: TextStyle(
                              color: selectedBirthdate != null 
                                  ? AppColors.textPrimary 
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: const Icon(Icons.email_outlined, color: AppColors.textSecondary),
                          helperText: 'We\'ll never share your email',
                          helperStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        validator: _validateEmail,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textSecondary),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              color: AppColors.textSecondary,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          helperText: 'At least 6 characters',
                          helperStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        validator: _validatePassword,
                        onChanged: (value) => setState(() {}), 
                      ),
                      
                      if (passwordController.text.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildPasswordStrengthIndicator(),
                      ],
                      const SizedBox(height: 32),
                      
                      ElevatedButton(
                        onPressed: isLoading ? null : submit,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 2,
                        ),
                        child: isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Create Account',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                      const SizedBox(height: 16),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Already have an account? ',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pushReplacementNamed(LoginPage.routeName),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Sign in',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        BuyerLoadingOverlay(show: isLoading, message: 'Creating your account...'),
      ],
    );
  }

  Widget _buildBenefit(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 16, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordStrengthIndicator() {
    final strength = _getPasswordStrength(passwordController.text);
    Color color;
    String label;
    double width;

    switch (strength) {
      case PasswordStrength.none:
        return const SizedBox.shrink();
      case PasswordStrength.weak:
        color = AppColors.error;
        label = 'Weak';
        width = 0.33;
        break;
      case PasswordStrength.fair:
        color = Colors.orange;
        label = 'Fair';
        width = 0.66;
        break;
      case PasswordStrength.strong:
        color = AppColors.success;
        label = 'Strong';
        width = 1.0;
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Password strength: $label',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: width,
            minHeight: 4,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

enum PasswordStrength { none, weak, fair, strong }


