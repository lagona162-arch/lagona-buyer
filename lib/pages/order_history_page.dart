import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import 'order_tracking_page.dart';
import 'package:intl/intl.dart';

class OrderHistoryPage extends StatefulWidget {
  static const String routeName = '/order-history';
  final int? initialTabIndex;
  const OrderHistoryPage({super.key, this.initialTabIndex});

  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage>
    with SingleTickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService();
  late TabController _tabController;
  
  List<Map<String, dynamic>> _allDeliveries = [];
  List<Map<String, dynamic>> _pendingDeliveries = [];
  List<Map<String, dynamic>> _completedDeliveries = [];
  List<Map<String, dynamic>> _cancelledDeliveries = [];
  
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.initialTabIndex ?? 0;
    _tabController = TabController(length: 4, vsync: this, initialIndex: initialIndex.clamp(0, 3));
    _loadDeliveries();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _markAsCompleted(Map<String, dynamic> delivery) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Completed'),
        content: const Text(
          'Are you sure you want to mark this delivery as completed? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Complete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You must be logged in to complete deliveries')),
          );
        }
        return;
      }

      await _supabaseService.completeDelivery(
        deliveryId: delivery['id'] as String,
        customerId: user.id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Delivery marked as completed'),
            backgroundColor: AppColors.success,
          ),
        );
        // Reload deliveries to update status
        _loadDeliveries();
      }
    } catch (e) {
      debugPrint('Error completing delivery: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to complete delivery: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _loadDeliveries() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'User not logged in';
        });
        return;
      }

      final deliveries = await _supabaseService.getCustomerDeliveries(
        customerId: user.id,
      );

      debugPrint('=== Order History Debug ===');
      debugPrint('Total deliveries fetched: ${deliveries.length}');
      
      // Debug: Print all statuses
      for (var i = 0; i < deliveries.length; i++) {
        final delivery = deliveries[i];
        final status = delivery['status'];
        debugPrint('Delivery $i - Status: $status (type: ${status.runtimeType})');
      }

      // Filter by status - convert to string to handle enum types
      final pending = deliveries.where((d) {
        final statusRaw = d['status'];
        final status = statusRaw?.toString().toLowerCase() ?? 'pending';
        debugPrint('Checking pending status: $status');
        // Include all active statuses: pending, accepted, assigned, picked_up, in_transit, etc.
        return status == 'pending' || 
               status == 'accepted' ||
               status == 'assigned' || 
               status == 'picked_up' || 
               status == 'in_transit' ||
               status == 'picked up' ||
               status == 'in transit' ||
               status == 'on_the_way' ||
               status == 'on the way';
      }).toList();

      final completed = deliveries.where((d) {
        final statusRaw = d['status'];
        final status = statusRaw?.toString().toLowerCase() ?? '';
        return status == 'delivered' || status == 'completed';
      }).toList();

      final cancelled = deliveries.where((d) {
        final statusRaw = d['status'];
        final status = statusRaw?.toString().toLowerCase() ?? '';
        return status == 'cancelled';
      }).toList();

      debugPrint('Pending count: ${pending.length}');
      debugPrint('Completed count: ${completed.length}');
      debugPrint('Cancelled count: ${cancelled.length}');

      if (mounted) {
        setState(() {
          _allDeliveries = deliveries;
          _pendingDeliveries = pending;
          _completedDeliveries = completed;
          _cancelledDeliveries = cancelled;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading deliveries: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load orders: $e';
        });
      }
    }
  }

  Color _getStatusColor(String? status) {
    if (status == null) return Colors.grey;
    final normalizedStatus = status.toLowerCase().trim();
    switch (normalizedStatus) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'assigned':
        return Colors.blue.shade700;
      case 'picked_up':
      case 'picked up':
      case 'in_transit':
      case 'in transit':
      case 'on_the_way':
      case 'on the way':
        return Colors.purple;
      case 'delivered':
      case 'completed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String? status) {
    if (status == null) return 'Unknown';
    final normalizedStatus = status.toLowerCase().trim();
    switch (normalizedStatus) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'assigned':
        return 'Rider Assigned';
      case 'picked_up':
      case 'picked up':
        return 'Picked Up';
      case 'in_transit':
      case 'in transit':
      case 'on_the_way':
      case 'on the way':
        return 'On the Way';
      case 'delivered':
        return 'Delivered';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status.toUpperCase();
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MMM dd, yyyy • hh:mm a').format(date);
    } catch (e) {
      return dateString;
    }
  }

  double _calculateTotal(Map<String, dynamic> delivery) {
    try {
      final items = delivery['delivery_items'] as List<dynamic>? ?? [];
      double total = 0;
      for (final item in items) {
        final subtotal = item['subtotal'];
        if (subtotal is num) {
          total += subtotal.toDouble();
        }
      }
      final deliveryFee = delivery['delivery_fee'];
      if (deliveryFee is num) {
        total += deliveryFee.toDouble();
      }
      return total;
    } catch (e) {
      debugPrint('Error calculating total: $e');
      return 0;
    }
  }

  Widget _buildDeliveryCard(Map<String, dynamic> delivery) {
    final merchant = delivery['merchants'] as Map<String, dynamic>?;
    final merchantName = merchant?['business_name'] as String? ?? 'Unknown Merchant';
    final statusRaw = delivery['status'];
    final status = statusRaw?.toString().toLowerCase() ?? 'pending';
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);
    final createdAt = delivery['created_at'] as String?;
    final total = _calculateTotal(delivery);
    final items = delivery['delivery_items'] as List<dynamic>? ?? [];
    final itemCount = items.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          // Navigate to tracking page if order is active
          final normalizedStatus = status.toLowerCase().trim();
          if (normalizedStatus == 'pending' || 
              normalizedStatus == 'accepted' ||
              normalizedStatus == 'assigned' || 
              normalizedStatus == 'picked_up' || 
              normalizedStatus == 'picked up' ||
              normalizedStatus == 'in_transit' ||
              normalizedStatus == 'in transit' ||
              normalizedStatus == 'on_the_way' ||
              normalizedStatus == 'on the way') {
            Navigator.of(context).pushNamed(
              OrderTrackingPage.routeName,
              arguments: delivery['id'] as String,
            );
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
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
                        Text(
                          _formatDate(createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor, width: 1),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Order items summary
              if (items.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$itemCount item${itemCount > 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...items.take(3).map<Widget>((item) {
                        final product = item['merchant_products'] as Map<String, dynamic>?;
                        final productName = product?['name'] as String? ?? 'Unknown';
                        final quantity = item['quantity'] as int? ?? 1;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Text(
                                '• ',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                              Expanded(
                                child: Text(
                                  '$quantity $productName',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      if (items.length > 3)
                        Text(
                          '... and ${items.length - 3} more',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              // Footer with total and action
              Builder(
                builder: (context) {
                  final normalizedStatus = status.toLowerCase().trim();
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            '₱${total.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      // Show Track button for active orders or Complete button for delivered
                      if (normalizedStatus == 'pending' || 
                          normalizedStatus == 'accepted' ||
                          normalizedStatus == 'assigned' || 
                          normalizedStatus == 'picked_up' || 
                          normalizedStatus == 'picked up' ||
                          normalizedStatus == 'in_transit' ||
                          normalizedStatus == 'in transit' ||
                          normalizedStatus == 'on_the_way' ||
                          normalizedStatus == 'on the way')
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pushNamed(
                              OrderTrackingPage.routeName,
                              arguments: delivery['id'] as String,
                            );
                          },
                          icon: const Icon(Icons.location_on, size: 18),
                          label: const Text('Track'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                        )
                      else if (normalizedStatus == 'delivered')
                        ElevatedButton.icon(
                          onPressed: () => _markAsCompleted(delivery),
                          icon: const Icon(Icons.check_circle, size: 18),
                          label: const Text('Mark as Completed'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 80,
              color: AppColors.textSecondary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveriesList(List<Map<String, dynamic>> deliveries, String emptyMessage) {
    if (deliveries.isEmpty) {
      return _buildEmptyState(emptyMessage);
    }

    return RefreshIndicator(
      onRefresh: _loadDeliveries,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: deliveries.length,
        itemBuilder: (context, index) {
          return _buildDeliveryCard(deliveries[index]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Order History'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Pending'),
            Tab(text: 'Completed'),
            Tab(text: 'Cancelled'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadDeliveries,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDeliveriesList(
                      _allDeliveries,
                      'No orders yet',
                    ),
                    _buildDeliveriesList(
                      _pendingDeliveries,
                      'No pending orders',
                    ),
                    _buildDeliveriesList(
                      _completedDeliveries,
                      'No completed orders',
                    ),
                    _buildDeliveriesList(
                      _cancelledDeliveries,
                      'No cancelled orders',
                    ),
                  ],
                ),
    );
  }
}

