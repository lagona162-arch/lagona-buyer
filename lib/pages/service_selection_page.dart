import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../services/supabase_service.dart';
import 'merchant_list_page.dart';
import 'padala_booking_page.dart';
import 'padala_tracking_page.dart';
import 'order_tracking_page.dart';
import 'profile_page.dart';
import 'order_history_page.dart';

class ServiceSelectionPage extends StatefulWidget {
  static const String routeName = '/service-selection';
  const ServiceSelectionPage({super.key});

  @override
  State<ServiceSelectionPage> createState() => _ServiceSelectionPageState();
}

class _ServiceSelectionPageState extends State<ServiceSelectionPage> {
  final SupabaseService _service = SupabaseService();
  String? _userName;
  List<Map<String, dynamic>> _activeDeliveries = [];
  bool _loadingDeliveries = true;

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _loadActiveDeliveries();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload deliveries when page becomes visible
    if (mounted) {
      _loadActiveDeliveries();
    }
  }

  Future<void> _loadUserName() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        final response = await Supabase.instance.client
            .from('users')
            .select('firstname')
            .eq('id', user.id)
            .maybeSingle();
        
        if (mounted && response != null) {
          setState(() {
            _userName = response['firstname'] as String?;
          });
        }
      } catch (e) {
        debugPrint('Error loading user name: $e');
      }
    }
  }

  Future<void> _loadActiveDeliveries() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() => _loadingDeliveries = false);
        return;
      }
      
      final allDeliveries = await _service.getCustomerDeliveries(customerId: user.id);
      
      // Filter for active deliveries (not delivered, completed, or cancelled)
      final activeDeliveries = allDeliveries.where((d) {
        final status = (d['status']?.toString().toLowerCase() ?? '').trim();
        final isActive = status != 'delivered' && 
                        status != 'completed' && 
                        status != 'cancelled';
        return isActive;
      }).toList();
      
      
      if (mounted) {
        setState(() {
          _activeDeliveries = activeDeliveries;
          _loadingDeliveries = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading active deliveries: $e');
      if (mounted) {
        setState(() => _loadingDeliveries = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome${_userName != null ? ', $_userName' : ''}! 👋',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'What service would you like to use?',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: _loadingDeliveries
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.refresh, color: Colors.white, size: 24),
                        ),
                        onPressed: _loadingDeliveries ? null : () => _loadActiveDeliveries(),
                        tooltip: 'Refresh',
                      ),
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.person, color: Colors.white, size: 24),
                        ),
                        onPressed: () => Navigator.of(context).pushNamed(ProfilePage.routeName),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Active Deliveries Section
            if (_activeDeliveries.isNotEmpty)
              Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.pending_actions, color: Colors.orange.shade700, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Active Deliveries (${_activeDeliveries.length})',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._activeDeliveries.take(3).map((delivery) {
                      final type = delivery['type'] as String?;
                      final isPadala = type == 'parcel';
                      final status = delivery['status'] as String? ?? 'pending';
                      final deliveryId = delivery['id'] as String;
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isPadala ? Colors.green.shade100 : AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isPadala ? Icons.local_shipping : Icons.restaurant,
                              color: isPadala ? Colors.green : AppColors.primary,
                              size: 24,
                            ),
                          ),
                          title: Text(
                            isPadala ? 'Padala Delivery' : 'Food Order',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'Status: ${status.replaceAll('_', ' ')}',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            if (isPadala) {
                              final result = await Navigator.of(context).pushNamed(
                                PadalaTrackingPage.routeName,
                                arguments: deliveryId,
                              );
                              // Refresh if delivery was cancelled
                              if (result == true && mounted) {
                                _loadActiveDeliveries();
                              }
                            } else {
                              final result = await Navigator.of(context).pushNamed(
                                OrderTrackingPage.routeName,
                                arguments: deliveryId,
                              );
                              // Refresh if delivery was cancelled
                              if (result == true && mounted) {
                                _loadActiveDeliveries();
                              }
                            }
                          },
                        ),
                      );
                    }).toList(),
                    if (_activeDeliveries.length > 3)
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pushNamed(OrderHistoryPage.routeName);
                        },
                        child: Text('View all ${_activeDeliveries.length} deliveries'),
                      ),
                  ],
                ),
              ),
            
            // Service Cards
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Pabili Service Card
                    _buildServiceCard(
                      context: context,
                      icon: Icons.shopping_bag,
                      title: 'Pabili',
                      subtitle: 'Order food & products from local merchants',
                      color: AppColors.primary,
                      onTap: () {
                        Navigator.of(context).pushNamed(MerchantListPage.routeName);
                      },
                    ),
                    const SizedBox(height: 20),
                    
                    // Padala Service Card
                    _buildServiceCard(
                      context: context,
                      icon: Icons.local_shipping_outlined,
                      title: 'Padala',
                      subtitle: 'Send packages & documents to anyone',
                      color: Colors.green,
                      onTap: () async {
                        final result = await Navigator.of(context).pushNamed(PadalaBookingPage.routeName);
                        // Refresh if delivery was cancelled during booking
                        if (result == true && mounted) {
                          _loadActiveDeliveries();
                        }
                      },
                    ),
                    const SizedBox(height: 40),
                    
                    // Quick Links
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pushNamed(OrderHistoryPage.routeName);
                            },
                            icon: const Icon(Icons.history, size: 20),
                            label: const Text('Order History'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pushNamed(ProfilePage.routeName);
                            },
                            icon: const Icon(Icons.person, size: 20),
                            label: const Text('Profile'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.3), width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.1),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 40,
                  color: color,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: color.withOpacity(0.5),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


