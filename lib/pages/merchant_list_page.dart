import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;
import '../services/supabase_service.dart';
import '../models/merchant.dart';
import 'customer_registration_page.dart';
import 'merchant_detail_page.dart';
import 'profile_page.dart';
import 'order_history_page.dart';
import 'order_tracking_page.dart';
import 'padala_booking_page.dart';
import 'service_selection_page.dart';
import '../theme/app_colors.dart';

class MerchantListPage extends StatefulWidget {
  static const String routeName = '/';
  const MerchantListPage({super.key});

  @override
  State<MerchantListPage> createState() => _MerchantListPageState();
}

class _MerchantListPageState extends State<MerchantListPage> {
  final SupabaseService _service = SupabaseService();
  late Future<List<Merchant>> _future;
  late Future<bool> _profileCompleteFuture;
  late Future<List<Map<String, dynamic>>> _activeOrdersFuture;
  late Future<Map<String, dynamic>?> _userDataFuture;
  int _currentPage = 0;
  static const int _itemsPerPage = 10;
  bool _isHorizontalScroll = false; 
  String _sortBy = 'alphabetical'; 
  Position? _userPosition;
  List<Merchant> _sortedMerchants = [];

  @override
  void initState() {
    super.initState();
    _future = _service.getMerchants();
    _profileCompleteFuture = _checkProfileComplete();
    _loadData();
    _getUserLocation();
  }


  Future<void> _getUserLocation() async {
    try {
      final hasPermission = await _checkLocationPermission();
      if (!hasPermission) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      setState(() {
        _userPosition = position;
      });
    } catch (e) {
      debugPrint('Error getting user location: $e');
    }
  }

  Future<bool> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }

    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double r = 6371.0; 
    final double dLat = _deg2rad(lat2 - lat1);
    final double dLon = _deg2rad(lon2 - lon1);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) * math.cos(_deg2rad(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  double _deg2rad(double deg) => deg * (math.pi / 180.0);

  List<Merchant> _sortMerchants(List<Merchant> merchants) {
    if (_sortBy == 'alphabetical') {
      return List.from(merchants)..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else if (_sortBy == 'nearest' && _userPosition != null) {
      return List.from(merchants)..sort((a, b) {
        if (a.latitude == null || a.longitude == null) return 1;
        if (b.latitude == null || b.longitude == null) return -1;
        
        final distanceA = _calculateDistance(
          _userPosition!.latitude,
          _userPosition!.longitude,
          a.latitude!,
          a.longitude!,
        );
        final distanceB = _calculateDistance(
          _userPosition!.latitude,
          _userPosition!.longitude,
          b.latitude!,
          b.longitude!,
        );
        return distanceA.compareTo(distanceB);
      });
    }
    return merchants;
  }

  void _loadData() {
    setState(() {
      _activeOrdersFuture = _getActiveOrders();
      _userDataFuture = _getUserData();
    });
  }

  Future<List<Map<String, dynamic>>> _getActiveOrders() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return [];
      
      final allDeliveries = await _service.getCustomerDeliveries(customerId: user.id);
      
      final ongoingOrders = allDeliveries.where((d) {
        final statusRaw = d['status'];
        final status = (statusRaw?.toString().toLowerCase() ?? '').trim();
        
        final isCompleted = status == 'delivered' || status == 'completed';
        final isCancelled = status == 'cancelled';
        
        final isOngoing = !isCompleted && !isCancelled;
        if (isOngoing) {
          debugPrint('Found ongoing order: ${d['id']} with status: $status');
        }
        return isOngoing;
      }).toList();
      
      return ongoingOrders;
    } catch (e) {
      debugPrint('Error loading active orders: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> _getUserData() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return null;
      
      final response = await Supabase.instance.client
          .from('users')
          .select('firstname, lastname')
          .eq('id', user.id)
          .maybeSingle();
      
      return response;
    } catch (e) {
      debugPrint('Error loading user data: $e');
      return null;
    }
  }

  Future<bool> _checkProfileComplete() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;
    return await _service.isCustomerProfileComplete(user.id);
  }

  void _refreshProfileStatus() {
    setState(() {
      _profileCompleteFuture = _checkProfileComplete();
    });
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
                ),
                
                if (badgeCount != null && badgeCount > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      child: Center(
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveOrderCard(Map<String, dynamic> order) {
    final merchant = order['merchants'] as Map<String, dynamic>?;
    final merchantName = merchant?['business_name'] as String? ?? 'Unknown Merchant';
    final status = order['status'] as String? ?? 'pending';
    final createdAt = order['created_at'] as String?;
    final orderId = order['id'] as String;

    Color statusColor;
    String statusText;
    IconData statusIcon;
    
    switch (status) {
      case 'pending':
        statusColor = Colors.orange;
        statusText = 'Pending';
        statusIcon = Icons.pending;
        break;
      case 'assigned':
        statusColor = Colors.blue;
        statusText = 'Rider Assigned';
        statusIcon = Icons.person;
        break;
      case 'picked_up':
        statusColor = Colors.purple;
        statusText = 'Picked Up';
        statusIcon = Icons.inventory;
        break;
      case 'in_transit':
        statusColor = Colors.indigo;
        statusText = 'On the Way';
        statusIcon = Icons.local_shipping;
        break;
      default:
        statusColor = Colors.grey;
        statusText = status.toUpperCase();
        statusIcon = Icons.info;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          Navigator.of(context).pushNamed(
            OrderTrackingPage.routeName,
            arguments: orderId,
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(statusIcon, color: statusColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      merchantName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (createdAt != null)
                          Text(
                            _formatDate(createdAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMerchantCard(Merchant m, {bool isGrid = false}) {
    
    double? distance;
    if (_sortBy == 'nearest' && _userPosition != null && m.latitude != null && m.longitude != null) {
      distance = _calculateDistance(
        _userPosition!.latitude,
        _userPosition!.longitude,
        m.latitude!,
        m.longitude!,
      );
    }
    
    if (isGrid) {
      

      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: () => Navigator.of(context).pushNamed(
            MerchantDetailPage.routeName,
            arguments: m.id,
          ),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                
                Container(
                  width: double.infinity,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: m.photoUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            m.photoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.store,
                              color: AppColors.primary,
                              size: 40,
                            ),
                          ),
                        )
                      : const Icon(
                    Icons.store,
                    color: AppColors.primary,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 12),
                
                Text(
                  m.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                
                if (distance != null)
                  Row(
                    children: [
                      Icon(
                        Icons.near_me,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${distance.toStringAsFixed(1)} km away',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                else if (m.address != null)
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 12,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          m.address!,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
    } else {
      
      return SizedBox(
        width: 280,
        child: Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: m.photoUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        m.photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.store,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : const Icon(
                Icons.store,
                color: AppColors.primary,
              ),
            ),
            title: Text(
              m.name,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (distance != null)
                    Row(
                      children: [
                        Icon(
                          Icons.near_me,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${distance.toStringAsFixed(1)} km away',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            m.address ?? 'No address',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              color: AppColors.textSecondary,
            ),
            onTap: () => Navigator.of(context).pushNamed(
              MerchantDetailPage.routeName,
              arguments: m.id,
            ),
          ),
        ),
      );
    }
  }

  Widget _buildSortButton({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final isSelected = _sortBy == value;
    return InkWell(
      onTap: () {
        setState(() {
          _sortBy = value;
          _currentPage = 0; 
        });
        if (value == 'nearest' && _userPosition == null) {
          _getUserLocation();
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected 
              ? AppColors.primary.withOpacity(0.1) 
              : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected 
                ? AppColors.primary 
                : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected 
                  ? AppColors.primary 
                  : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected 
                    ? FontWeight.w600 
                    : FontWeight.normal,
                color: isSelected 
                    ? AppColors.primary 
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = date.difference(now); 
      
      
      if (difference.isNegative) {
        final absDifference = now.difference(date);
        if (absDifference.inMinutes < 60) {
          return '${absDifference.inMinutes}m ago';
        } else if (absDifference.inHours < 24) {
          return '${absDifference.inHours}h ago';
        } else if (absDifference.inDays < 7) {
          return '${absDifference.inDays}d ago';
        } else {
          return DateFormat('MMM dd').format(date);
        }
      } else {
        
        return DateFormat('MMM dd, yyyy').format(date);
      }
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.background,
          body: RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _future = _service.getMerchants();
                _profileCompleteFuture = _checkProfileComplete();
                _loadData();
                _currentPage = 0; 
              });
              await Future.wait([_future, _profileCompleteFuture, _activeOrdersFuture, _userDataFuture]);
            },
            child: CustomScrollView(
            slivers: [
              
              SliverAppBar(
                expandedHeight: 140,
                floating: false,
                pinned: true,
                automaticallyImplyLeading: false,
                backgroundColor: AppColors.primary,
                leading: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.home, color: Colors.white, size: 20),
                  ),
                  onPressed: () => Navigator.of(context).pushReplacementNamed(ServiceSelectionPage.routeName),
                  tooltip: 'Back to Services',
                ),
                actions: [
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person, color: Colors.white, size: 20),
                    ),
                    onPressed: () => Navigator.of(context).pushNamed(ProfilePage.routeName),
                  ),
                  const SizedBox(width: 8),
                ],
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.shopping_bag,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Lagona',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                      Text(
                                        'Your local marketplace',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.9),
                                          fontSize: 13,
                                          letterSpacing: 0.5,
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
                child: FutureBuilder<Map<String, dynamic>?>(
                  future: _userDataFuture,
                  builder: (context, userSnapshot) {
                    final firstName = userSnapshot.data?['firstname'] as String? ?? 'There';
                    final greeting = _getGreeting();
                    return Container(
                      color: AppColors.background,
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$greeting, $firstName! 👋',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'What would you like to order today?',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          
                          Row(
                            children: [
                              Expanded(
                                child: FutureBuilder<List<Map<String, dynamic>>>(
                                  future: _activeOrdersFuture,
                                  builder: (context, snapshot) {
                                    final ongoingCount = (snapshot.data ?? []).length;
                                    return _buildQuickActionCard(
                                  icon: Icons.history,
                                  label: 'Orders',
                                  color: Colors.blue,
                                      badgeCount: ongoingCount > 0 ? ongoingCount : null,
                                  onTap: () => Navigator.of(context).pushNamed(OrderHistoryPage.routeName),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FutureBuilder<List<Map<String, dynamic>>>(
                                  future: _activeOrdersFuture,
                                  builder: (context, snapshot) {
                                    final hasActiveOrders = (snapshot.data ?? []).isNotEmpty;
                                    return _buildQuickActionCard(
                                      icon: Icons.local_shipping,
                                      label: 'Track',
                                      color: Colors.orange,
                                      onTap: () {
                                        if (hasActiveOrders) {
                                          final firstOrder = (snapshot.data ?? []).first;
                                          Navigator.of(context).pushNamed(
                                            OrderTrackingPage.routeName,
                                            arguments: firstOrder['id'] as String,
                                          );
                                        } else {
                                          
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (context) => const OrderHistoryPage(initialTabIndex: 1),
                                            ),
                                          );
                                        }
                                      },
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildQuickActionCard(
                                  icon: Icons.local_shipping_outlined,
                                  label: 'Padala',
                                  color: Colors.green,
                                  onTap: () => Navigator.of(context).pushNamed(PadalaBookingPage.routeName),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildQuickActionCard(
                                  icon: Icons.person,
                                  label: 'Profile',
                                  color: Colors.purple,
                                  onTap: () => Navigator.of(context).pushNamed(ProfilePage.routeName),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              
              SliverToBoxAdapter(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _activeOrdersFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox.shrink();
                    }
                    final activeOrders = snapshot.data ?? [];
                    if (activeOrders.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      color: AppColors.background,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Active Orders',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => const OrderHistoryPage(initialTabIndex: 1),
                                  ),
                                ),
                                child: const Text('View All'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...activeOrders.take(2).map((order) => _buildActiveOrderCard(order)),
                        ],
                      ),
                    );
                  },
                ),
              ),
              
              SliverToBoxAdapter(
                child: FutureBuilder<List<Merchant>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                
                return const SizedBox(
                  height: 400,
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 64,
                                color: AppColors.error,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Failed to load merchants',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${snapshot.error}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
              }
              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.store_outlined,
                                size: 64,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No merchants available',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Check back later for new merchants',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    
                    final sortedItems = _sortMerchants(items);
                    final totalPages = (sortedItems.length / _itemsPerPage).ceil();
                    final startIndex = _currentPage * _itemsPerPage;
                    final endIndex = (startIndex + _itemsPerPage).clamp(0, sortedItems.length);
                    final paginatedItems = sortedItems.sublist(startIndex, endIndex);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Available Merchants (${items.length})',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        _isHorizontalScroll 
                                            ? Icons.swap_vert 
                                            : Icons.swap_horiz,
                                        size: 20,
                                      ),
                                      tooltip: _isHorizontalScroll 
                                          ? 'Switch to vertical scroll'
                                          : 'Switch to horizontal scroll',
                                      onPressed: () {
                                        setState(() {
                                          _isHorizontalScroll = !_isHorizontalScroll;
                                          _currentPage = 0; 
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildSortButton(
                                        label: 'Alphabetical',
                                        value: 'alphabetical',
                                        icon: Icons.sort_by_alpha,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildSortButton(
                                        label: 'Nearest',
                                        value: 'nearest',
                                        icon: Icons.near_me,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          
                          _isHorizontalScroll
                              ? SizedBox(
                                  height: 120,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: paginatedItems.length,
                                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    itemBuilder: (context, index) {
                                      final m = paginatedItems[index];
                                      return _buildMerchantCard(m, isGrid: false);
                                    },
                                  ),
                                )
                              : GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: paginatedItems.length,
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    childAspectRatio: 0.75,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                  ),
                                  itemBuilder: (context, index) {
                                    final m = paginatedItems[index];
                                    return _buildMerchantCard(m, isGrid: true);
                                  },
                                ),
                          
                          if (totalPages > 1)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.chevron_left),
                                    onPressed: _currentPage > 0
                                        ? () {
                                            setState(() {
                                              _currentPage--;
                                            });
                                          }
                                        : null,
                                  ),
                                  Text(
                                    'Page ${_currentPage + 1} of $totalPages',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.chevron_right),
                                    onPressed: _currentPage < totalPages - 1
                                        ? () {
                                            setState(() {
                                              _currentPage++;
                                            });
                                          }
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 80), 
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
            ),
          ),
          floatingActionButton: FutureBuilder<bool>(
            future: _profileCompleteFuture,
            builder: (context, snapshot) {
              final isComplete = snapshot.data ?? false;
              
              if (isComplete) {
                return const SizedBox.shrink();
              }
              return FloatingActionButton.extended(
                onPressed: () async {
                  await Navigator.of(context).pushNamed(CustomerRegistrationPage.routeName);
                  
                  _refreshProfileStatus();
                },
                backgroundColor: AppColors.primary,
                icon: const Icon(Icons.person_add, color: Colors.white),
                label: const Text(
                  'Complete Profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}


