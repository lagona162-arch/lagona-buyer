import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../services/supabase_service.dart';
import 'login_page.dart';
import 'customer_registration_page.dart';
import 'order_history_page.dart';

class ProfilePage extends StatefulWidget {
  static const String routeName = '/profile';
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final SupabaseService _supabase = SupabaseService();
  Map<String, dynamic>? _userData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final response = await Supabase.instance.client
            .from('users')
            .select('firstname, lastname, middle_initial, email, phone, birthdate, address')
            .eq('id', user.id)
            .single();
        
        
        try {
          final customerData = await Supabase.instance.client
              .from('customers')
              .select('address, latitude, longitude')
              .eq('id', user.id)
              .maybeSingle();
          
          if (customerData != null) {
            response['customer_address'] = customerData['address'];
            response['latitude'] = customerData['latitude'];
            response['longitude'] = customerData['longitude'];
          }
        } catch (_) {
          
        }
        
        setState(() {
          _userData = response;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Sign Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await Supabase.instance.client.auth.signOut();
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil(
            LoginPage.routeName,
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error signing out: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          
          SliverAppBar(
            expandedHeight: 200,
            floating: false,
            pinned: true,
            backgroundColor: AppColors.primary,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
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
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.person,
                                size: 40,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _userData != null
                                        ? '${_userData!['firstname'] ?? ''} ${_userData!['lastname'] ?? ''}'.trim()
                                        : 'Loading...',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _userData?['email'] ?? '',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.9),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
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
          ),
          
          SliverToBoxAdapter(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        
                        _buildSectionCard(
                          title: 'Account Settings',
                          icon: Icons.person_outline,
                          children: [
                            _buildListTile(
                              icon: Icons.edit,
                              title: 'Edit Profile',
                              subtitle: 'Update your personal information',
                              onTap: () => _navigateToEditProfile(),
                            ),
                            _buildListTile(
                              icon: Icons.location_on_outlined,
                              title: 'Edit Address',
                              subtitle: _userData?['customer_address'] ?? 'Not set',
                              onTap: () => _navigateToEditAddress(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        
                        _buildSectionCard(
                          title: 'Personal Information',
                          icon: Icons.info_outline,
                          children: [
                            _buildInfoRow('First Name', _userData?['firstname'] ?? 'N/A'),
                            _buildInfoRow('Last Name', _userData?['lastname'] ?? 'N/A'),
                            if (_userData?['middle_initial'] != null)
                              _buildInfoRow('Middle Initial', _userData!['middle_initial']),
                            _buildInfoRow('Email', _userData?['email'] ?? 'N/A'),
                            if (_userData?['phone'] != null)
                              _buildInfoRow('Phone', _userData!['phone']),
                            if (_userData?['birthdate'] != null)
                              _buildInfoRow('Birthdate', _userData!['birthdate']),
                            if (_userData?['customer_address'] != null)
                              _buildInfoRow('Address', _userData!['customer_address']),
                          ],
                        ),
                        const SizedBox(height: 20),
                        
                        _buildSectionCard(
                          title: 'Orders & Activity',
                          icon: Icons.shopping_bag_outlined,
                          children: [
                            _buildListTile(
                              icon: Icons.history,
                              title: 'Order History',
                              subtitle: 'View your past orders',
                              onTap: () {
                                Navigator.of(context).pushNamed(OrderHistoryPage.routeName);
                              },
                            ),
                            _buildListTile(
                              icon: Icons.receipt_long,
                              title: 'Active Orders',
                              subtitle: 'Track your current orders',
                              onTap: () {
                                Navigator.of(context).pushNamed(OrderHistoryPage.routeName);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        
                        _buildSectionCard(
                          title: 'Help & Support',
                          icon: Icons.help_outline,
                          children: [
                            _buildListTile(
                              icon: Icons.contact_support,
                              title: 'Contact Support',
                              subtitle: 'Get help with your account',
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Support contact coming soon!'),
                                  ),
                                );
                              },
                            ),
                            _buildListTile(
                              icon: Icons.info,
                              title: 'About',
                              subtitle: 'App version and information',
                              onTap: () {
                                showAboutDialog(
                                  context: context,
                                  applicationName: 'Lagona Buyer',
                                  applicationVersion: '1.0.0',
                                  applicationLegalese: '© 2024 Lagona',
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _signOut,
                            icon: const Icon(Icons.logout, color: AppColors.error),
                            label: const Text(
                              'Sign Out',
                              style: TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.error, width: 2),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToEditProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const EditProfilePage(),
      ),
    ).then((_) => _loadUserData()); 
  }

  void _navigateToEditAddress() {
    Navigator.of(context).pushNamed(CustomerRegistrationPage.routeName).then(
      (_) => _loadUserData(), 
    );
  }
}


class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _middleInitialController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  DateTime? _selectedBirthdate;
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final response = await Supabase.instance.client
            .from('users')
            .select('firstname, lastname, middle_initial, phone, birthdate')
            .eq('id', user.id)
            .single();

        setState(() {
          _firstNameController.text = response['firstname'] ?? '';
          _lastNameController.text = response['lastname'] ?? '';
          _middleInitialController.text = response['middle_initial'] ?? '';
          _phoneController.text = response['phone'] ?? '';
          
          if (response['birthdate'] != null) {
            try {
              _selectedBirthdate = DateTime.parse(response['birthdate']);
            } catch (_) {
              
            }
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectBirthdate() async {
    final DateTime now = DateTime.now();
    final DateTime firstDate = DateTime(now.year - 100);
    final DateTime lastDate = DateTime(now.year - 13);

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedBirthdate ?? lastDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Select your birthdate',
    );
    if (picked != null && picked != _selectedBirthdate) {
      setState(() => _selectedBirthdate = picked);
    }
  }

  String? _validatePhoneNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }
    final cleaned = value.trim().replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
    final phPattern = RegExp(r'^09\d{9}$');
    if (phPattern.hasMatch(cleaned)) {
      return null;
    }
    if (cleaned.startsWith('639') && cleaned.length == 12) {
      final converted = '0${cleaned.substring(2)}';
      if (phPattern.hasMatch(converted)) {
        _phoneController.text = converted;
        return null;
      }
    }
    return 'Invalid phone number. Must be 11 digits starting with 09';
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final updateData = <String, dynamic>{
        'firstname': _firstNameController.text.trim(),
        'lastname': _lastNameController.text.trim(),
      };

      if (_middleInitialController.text.trim().isNotEmpty) {
        updateData['middle_initial'] = _middleInitialController.text.trim().toUpperCase();
      }

      if (_phoneController.text.trim().isNotEmpty) {
        updateData['phone'] = _phoneController.text.trim();
      }

      if (_selectedBirthdate != null) {
        updateData['birthdate'] = _selectedBirthdate!.toIso8601String().split('T')[0];
      }

      
      final fullName = '${_firstNameController.text.trim()}${_middleInitialController.text.trim().isNotEmpty ? ' ${_middleInitialController.text.trim()}' : ''} ${_lastNameController.text.trim()}';
      updateData['full_name'] = fullName.trim();

      await Supabase.instance.client
          .from('users')
          .update(updateData)
          .eq('id', user.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _saveProfile,
              child: const Text(
                'Save',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _firstNameController,
                      decoration: const InputDecoration(
                        labelText: 'First Name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) =>
                          value?.trim().isEmpty ?? true ? 'First name is required' : null,
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _middleInitialController,
                      maxLength: 1,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Middle Initial (Optional)',
                        prefixIcon: Icon(Icons.badge_outlined),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _lastNameController,
                      decoration: const InputDecoration(
                        labelText: 'Last Name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) =>
                          value?.trim().isEmpty ?? true ? 'Last name is required' : null,
                    ),
                    const SizedBox(height: 20),
                    InkWell(
                      onTap: _selectBirthdate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Birthdate',
                          prefixIcon: Icon(Icons.calendar_today_outlined),
                          suffixIcon: Icon(Icons.arrow_drop_down),
                        ),
                        child: Text(
                          _selectedBirthdate != null
                              ? '${_selectedBirthdate!.year}-${_selectedBirthdate!.month.toString().padLeft(2, '0')}-${_selectedBirthdate!.day.toString().padLeft(2, '0')}'
                              : 'Select birthdate',
                          style: TextStyle(
                            color: _selectedBirthdate != null
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      maxLength: 11,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        hintText: '09XXXXXXXXX',
                        prefixIcon: Icon(Icons.phone_outlined),
                        counterText: '',
                      ),
                      validator: _validatePhoneNumber,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Save Changes'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _middleInitialController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}

