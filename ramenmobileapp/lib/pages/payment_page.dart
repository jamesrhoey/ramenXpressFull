import 'package:flutter/material.dart';
import 'invoice_page.dart';
import '../services/cart_service.dart';
import '../services/order_service.dart';
import '../services/api_service.dart';
import '../services/menu_service.dart';
import '../services/notification_service.dart';
import '../services/paymongo_service.dart';
import '../models/cart_item.dart';
import '../models/menu_item.dart';
import '../models/delivery_address.dart';
import '../models/payment_method.dart';
import 'paymongo_webview_page.dart';

class PaymentPage extends StatefulWidget {
  final Map<String, dynamic>? orderData;
  
  const PaymentPage({super.key, this.orderData});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  final CartService _cartService = CartService();
  List<PaymentMethod> paymentMethods = [];
  PaymentMethod? selectedPaymentMethod;
  bool isLoading = true;
  String? selectedDeliveryAddress;
  bool _isVerifyingPayment = false;
  final TextEditingController _notesController = TextEditingController();
  
  // Services
  final OrderService _orderService = OrderService();
  final ApiService _apiService = ApiService();
  final MenuService _menuService = MenuService();
  // Note: PayMongoService uses static methods, no instance needed
  List<MenuItem> _addOns = [];

  // API Data
  List<DeliveryAddress> deliveryAddresses = [];
  String selectedDeliveryMethod = 'Pickup'; // Default to pickup
  DeliveryAddress? selectedAddress;


  // Use order data if provided, otherwise use cart service
  List<Map<String, dynamic>> get cartItems {
    if (widget.orderData != null && widget.orderData!['items'] != null) {
      return List<Map<String, dynamic>>.from(widget.orderData!['items']);
    }
    
    // Convert CartService items to the format expected by the UI
    return _cartService.cartItems.map((cartItem) => {
      'name': cartItem.menuItem.name,
      'price': cartItem.menuItem.price,
      'image': cartItem.menuItem.image,
      'quantity': cartItem.quantity,
      'addons': cartItem.selectedAddOns.map((addon) => {
        'name': addon.name,
        'price': addon.price,
      }).toList(),
      'removedIngredients': cartItem.removedIngredients,
    }).toList();
  }

  // ... (rest of the code remains the same)

  // Handle different payment methods
  Future<void> _handlePaymentMethod() async {
    final paymentType = selectedPaymentMethod!.type.toString().split('.').last;
    print('🔍 Selected payment method: ${selectedPaymentMethod!.title}');
    print('🔍 Payment type extracted: $paymentType');
    
    // Map maya to paymaya for backend compatibility
    String backendPaymentMethod = paymentType;
    if (paymentType == 'maya') {
      backendPaymentMethod = 'paymaya';
    }
    print('🔍 Backend payment method: $backendPaymentMethod');
    
    switch (paymentType) {
      case 'cash':
        await _processCashOrder();
        break;
      case 'gcash':
      case 'maya':
        await _processPayMongoPayment(backendPaymentMethod);
        break;
      default:
        print('❌ Unsupported payment method: $paymentType');
        NotificationService.showError(context, 'Unsupported payment method');
    }
  }

  // Process cash on delivery order
  Future<void> _processCashOrder() async {
    // Convert cart items to CartItem objects for OrderService
    final cartItemObjects = cartItems.map((item) {
      final menuItem = MenuItem(
        id: item['id'] ?? '1',
        name: item['name'],
        price: item['price'].toDouble(),
        image: item['image'],
        category: 'Unknown',
      );
      
      final addOns = (item['addons'] as List<dynamic>?)?.map((addon) => 
        AddOn(name: addon['name'], price: addon['price'].toDouble())
      ).toList() ?? [];
      
      return CartItem(
        menuItem: menuItem,
        quantity: item['quantity'],
        selectedAddOns: addOns,
        removedIngredients: List<String>.from(item['removedIngredients'] ?? []),
      );
    }).toList();

    // Create order using OrderService
    final order = await _orderService.createOrder(
      items: cartItemObjects,
      deliveryMethod: selectedDeliveryMethod,
      deliveryAddress: selectedDeliveryMethod == 'Delivery' && selectedAddress != null
          ? '${selectedAddress!.street}, ${selectedAddress!.barangay}, ${selectedAddress!.municipality}, ${selectedAddress!.province}, ${selectedAddress!.zipCode}'
          : null,
      paymentMethod: selectedPaymentMethod?.title ?? 'Cash',
      notes: _notesController.text,
    );

    // Clear cart after successful order
    await _cartService.clearCart();

    // Navigate to invoice page
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InvoicePage(order: order.toJson()),
      ),
    );
    
    if (mounted) {
      setState(() {});
    }
  }

  // Process PayMongo payment (GCash/Maya) - Automation Friendly
  Future<void> _processPayMongoPayment(String paymentMethod) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Setting up payment...'),
            ],
          ),
        ),
      );

      final orderId = PayMongoService.generateOrderId();
      
      // Skip simulation - go directly to real PayMongo payment methods
      print('🚀 Using real PayMongo payment flow (no simulation)');
      
      // Method 1: Try direct payment (no QR code) - ONLY method
      if (await _tryDirectPayment(orderId, paymentMethod)) {
        return;
      } else {
        // If direct payment fails, show error instead of fallback
        Navigator.pop(context); // Close any loading dialogs
        NotificationService.showError(context, 'Payment setup failed. Please try again.');
        return;
      }
      
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      NotificationService.showError(context, 'Payment setup failed: $e');
    }
  }


  // Try direct payment (opens browser - automation friendly)
  Future<bool> _tryDirectPayment(String orderId, String paymentMethod) async {
    try {
      print('🔗 Attempting direct payment...');
      
      final result = await PayMongoService.createDirectPayment(
        amount: total,
        orderId: orderId,
        paymentMethod: paymentMethod,
      );

      if (result['success']) {
        Navigator.pop(context); // Close loading dialog
        
        // Open PayMongo WebView for seamless payment experience
        
        final shouldProceed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => PayMongoWebViewPage(
              paymentUrl: result['checkoutUrl'],
              paymentMethod: selectedPaymentMethod!.title,
              amount: total,
            ),
          ),
        );

        if (shouldProceed == true) {
          // Start payment verification
          await _startPaymentVerification(result['sourceId'], orderId);
          return true;
        }
      }
    } catch (e) {
      print('❌ Direct payment failed: $e');
    }
    return false;
  }


  // Start payment verification process
  Future<void> _startPaymentVerification(String paymentId, String orderId) async {
    // Prevent multiple verification processes
    if (_isVerifyingPayment) {
      print('🔄 Payment verification already in progress, skipping...');
      return;
    }
    
    _isVerifyingPayment = true;
    
    // Show verification dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Verifying payment...'),
            ],
          ),
        ),
      );
    }

    // Poll for payment status
    int attempts = 0;
    const maxAttempts = 30; // 5 minutes max
    
    while (attempts < maxAttempts && mounted && _isVerifyingPayment) {
      await Future.delayed(const Duration(seconds: 10));
      
      // Check if widget is still mounted before continuing
      if (!mounted || !_isVerifyingPayment) {
        print('🛑 Payment verification cancelled - widget unmounted');
        return;
      }
      
      try {
        final result = await PayMongoService.verifyPayment(paymentId);
        
        if (result['success']) {
          if (result['isPaid']) {
            _isVerifyingPayment = false;
            if (mounted) {
              Navigator.pop(context); // Close verification dialog
              NotificationService.showSuccess(context, 
                '✅ ${selectedPaymentMethod!.title} payment successful!');
              await _completeOrder(orderId, paymentId);
            }
            return;
          } else if (result['isFailed']) {
            _isVerifyingPayment = false;
            if (mounted) {
              Navigator.pop(context); // Close verification dialog
              NotificationService.showError(context, 
                '❌ Payment failed. Please try again.');
            }
            return;
          }
          // If still pending, continue polling
        }
      } catch (e) {
        print('❌ Payment verification error: $e');
        // Only show error if widget is still mounted
        if (!mounted) {
          print('🛑 Widget unmounted during verification error');
          _isVerifyingPayment = false;
          return;
        }
      }
      
      attempts++;
    }
    
    // Timeout or cancelled
    _isVerifyingPayment = false;
    if (mounted) {
      Navigator.pop(context); // Close verification dialog
      NotificationService.showWarning(context, 
        '⏰ Payment verification timeout. Please check your payment status.');
    }
  }

  // Complete order after successful payment
  Future<void> _completeOrder(String orderId, String paymentId) async {
    try {
      // Convert cart items to CartItem objects
      final cartItemObjects = cartItems.map((item) {
        final menuItem = MenuItem(
          id: item['id'] ?? '1',
          name: item['name'],
          price: item['price'].toDouble(),
          image: item['image'],
          category: 'Unknown',
        );
        
        final addOns = (item['addons'] as List<dynamic>?)?.map((addon) => 
          AddOn(name: addon['name'], price: addon['price'].toDouble())
        ).toList() ?? [];
        
        return CartItem(
          menuItem: menuItem,
          quantity: item['quantity'],
          selectedAddOns: addOns,
          removedIngredients: List<String>.from(item['removedIngredients'] ?? []),
        );
      }).toList();

      // Create order with payment info
      final order = await _orderService.createOrder(
        items: cartItemObjects,
        deliveryMethod: selectedDeliveryMethod,
        deliveryAddress: selectedDeliveryMethod == 'Delivery' && selectedAddress != null
            ? '${selectedAddress!.street}, ${selectedAddress!.barangay}, ${selectedAddress!.municipality}, ${selectedAddress!.province}, ${selectedAddress!.zipCode}'
            : null,
        paymentMethod: '${selectedPaymentMethod?.title} (${paymentId.substring(0, 8)}...)',
        notes: _notesController.text,
      );

      // Clear cart
      await _cartService.clearCart();

      // Navigate to invoice
      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => InvoicePage(order: order.toJson()),
        ),
      );
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      // Enhanced error handling for inventory issues
      String errorMessage = e.toString();
      if (errorMessage.contains('Insufficient') || 
          errorMessage.contains('out of stock') || 
          errorMessage.contains('Available:')) {
        // Extract clean error message for inventory issues
        final cleanMessage = errorMessage.replaceAll('Exception: ', '').replaceAll('Error 400: ', '');
        NotificationService.showError(context, cleanMessage);
      } else {
        NotificationService.showError(context, 'Error completing order: $errorMessage');
      }
    }
  }

  // Add missing getters and methods
  double get subtotal {
    return cartItems.fold(
      0.0,
      (sum, item) {
        double addonsTotal = 0.0;
        if (item['addons'] != null) {
          for (var addon in item['addons']) {
            addonsTotal += (addon['price'] as double) * item['quantity'];
          }
        }
        return sum + (item['price'] * item['quantity']) + addonsTotal;
      },
    );
  }

  double get shippingFee => selectedDeliveryMethod == 'Delivery' ? 50.0 : 0.0;
  double get total => subtotal + shippingFee;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadAddOns();
  }

  @override
  void dispose() {
    // Cancel any ongoing payment verification
    _isVerifyingPayment = false;
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      isLoading = true;
    });

    try {
      await _cartService.loadCart();
      await Future.wait([
        _loadDeliveryAddresses(),
        _loadPaymentMethods(),
      ]);
    } catch (e) {
      print('Error loading data: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _loadDeliveryAddresses() async {
    try {
      final addresses = await _apiService.getDeliveryAddresses();
      setState(() {
        deliveryAddresses = addresses;
        if (deliveryAddresses.isNotEmpty) {
          final defaultAddress = deliveryAddresses.where((addr) => addr.isDefault).toList();
          if (defaultAddress.isNotEmpty) {
            selectedAddress = defaultAddress.first;
          } else {
            selectedAddress = deliveryAddresses.first;
          }
        }
      });
    } catch (e) {
      print('❌ Error loading delivery addresses: $e');
      setState(() {
        deliveryAddresses = [];
      });
    }
  }

  Future<void> _loadPaymentMethods() async {
    setState(() {
      paymentMethods = [
        PaymentMethod(
          id: 'cash',
          type: PaymentType.cash,
          title: 'Cash on Delivery',
          isDefault: true,
        ),
        PaymentMethod(
          id: 'gcash',
          type: PaymentType.gcash,
          title: 'GCash',
        ),
        PaymentMethod(
          id: 'maya',
          type: PaymentType.maya,
          title: 'Maya',
        ),
      ];
      
      selectedPaymentMethod = paymentMethods.firstWhere(
        (method) => method.type == PaymentType.cash,
        orElse: () => paymentMethods.first,
      );
      
      isLoading = false;
    });
  }

  Future<void> _loadAddOns() async {
    try {
      final addOns = await _menuService.getMenuItemsByCategory('add-ons');
      setState(() {
        _addOns = addOns;
      });
    } catch (e) {
      print('❌ Error loading add-ons: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const CircularProgressIndicator(
                  color: Color(0xFFD32D43),
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Loading payment options...',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (cartItems.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        body: SafeArea(
          child: Column(
            children: [
              _buildModernAppBar(),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(60),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              spreadRadius: 0,
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.shopping_cart_outlined,
                          size: 48,
                          color: Color(0xFFD32D43),
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        'Your cart is empty',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Add some delicious ramen to get started!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: () => Navigator.pushReplacementNamed(context, '/home'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD32D43),
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Browse Menu',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            _buildModernAppBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    _buildOrderSummaryCard(),
                    const SizedBox(height: 20),
                    _buildCartItemsSection(),
                    const SizedBox(height: 20),
                    _buildDeliveryMethodSection(),
                    const SizedBox(height: 20),
                    _buildPaymentMethodSection(),
                    const SizedBox(height: 20),
                    _buildNotesSection(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
            _buildBottomPaymentBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildModernAppBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFD32D43),
            Color(0xFFE85A4F),
          ],
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Checkout',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'Review and complete your order',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.security,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 4),
                const Text(
                  'Secure',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFD32D43).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.receipt_long,
                  color: Color(0xFFD32D43),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Order Summary',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSummaryRow('Subtotal', subtotal),
          if (selectedDeliveryMethod == 'Delivery') ...[
            const SizedBox(height: 8),
            _buildSummaryRow('Delivery Fee', shippingFee),
          ],
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: Colors.grey[200],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
              Text(
                '₱${total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFD32D43),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          '₱${amount.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1F2937),
          ),
        ),
      ],
    );
  }

  Widget _buildCartItemsSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFD32D43).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.shopping_bag_outlined,
                  color: Color(0xFFD32D43),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Your Order (${cartItems.length} ${cartItems.length == 1 ? 'item' : 'items'})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...cartItems.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return Column(
              children: [
                if (index > 0) const SizedBox(height: 12),
                _buildCartItem(item),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCartItem(Map<String, dynamic> item) {

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey[300],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _buildMenuItemImage(item['image'], width: 60, height: 60),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'],
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Qty: ${item['quantity']}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (item['addons'] != null && (item['addons'] as List).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: (item['addons'] as List).map<Widget>((addon) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green[200]!),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_circle, size: 10, color: Colors.green[600]),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                addon['name'],
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
                if (item['removedIngredients'] != null && (item['removedIngredients'] as List).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: (item['removedIngredients'] as List).map<Widget>((ingredient) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.remove_circle, size: 10, color: Colors.orange[600]),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                'No $ingredient',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.orange[700],
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₱${(item['price'] * item['quantity']).toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFD32D43),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryMethodSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFD32D43).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.local_shipping_outlined,
                  color: Color(0xFFD32D43),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Delivery Method',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildDeliveryOption(
                  'Pickup',
                  Icons.store_outlined,
                  'Free',
                  'Ready in 15-20 mins',
                  selectedDeliveryMethod == 'Pickup',
                  () => setState(() => selectedDeliveryMethod = 'Pickup'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDeliveryOption(
                  'Delivery',
                  Icons.delivery_dining,
                  '₱50.00',
                  '30-45 mins',
                  selectedDeliveryMethod == 'Delivery',
                  () => setState(() => selectedDeliveryMethod = 'Delivery'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryOption(String title, IconData icon, String price, String time, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFD32D43).withOpacity(0.1) : const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFD32D43) : Colors.grey[300]!,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFFD32D43) : Colors.grey[600],
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected ? const Color(0xFFD32D43) : const Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              price,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isSelected ? const Color(0xFFD32D43) : Colors.grey[600],
              ),
            ),
            Text(
              time,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFD32D43).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.payment,
                  color: Color(0xFFD32D43),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Payment Method',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...paymentMethods.map((method) => _buildPaymentOption(method)),
        ],
      ),
    );
  }

  Widget _buildPaymentOption(PaymentMethod method) {
    final isSelected = selectedPaymentMethod?.id == method.id;
    final paymentType = method.type.toString().split('.').last;
    
    Color getPaymentColor() {
      switch (paymentType) {
        case 'cash':
          return Colors.green;
        case 'gcash':
          return const Color(0xFF007DFF);
        case 'maya':
          return const Color(0xFF00BF63);
        default:
          return Colors.grey;
      }
    }

    String getPaymentDescription() {
      switch (paymentType) {
        case 'cash':
          return 'Pay when your order arrives';
        case 'gcash':
          return 'Secure digital wallet payment';
        case 'maya':
          return 'Fast and secure payment';
        default:
          return '';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => setState(() => selectedPaymentMethod = method),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFD32D43).withOpacity(0.1) : const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFFD32D43) : Colors.grey[300]!,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: getPaymentColor().withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _buildPaymentIcon(paymentType),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      method.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? const Color(0xFFD32D43) : const Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      getPaymentDescription(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (['gcash', 'maya'].contains(paymentType) && total < PayMongoService.getMinimumAmount()) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Minimum amount: ${PayMongoService.formatAmount(PayMongoService.getMinimumAmount())}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.orange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? const Color(0xFFD32D43) : Colors.grey[400]!,
                    width: 2,
                  ),
                  color: isSelected ? const Color(0xFFD32D43) : Colors.transparent,
                ),
                child: isSelected
                    ? const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 16,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotesSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFD32D43).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.note_add_outlined,
                  color: Color(0xFFD32D43),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Special Instructions',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Add any special instructions for your order...',
              hintStyle: TextStyle(
                color: Colors.grey[500],
                fontSize: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFD32D43), width: 2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              filled: true,
              fillColor: const Color(0xFFF8F9FA),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPaymentBar() {
    final canProceed = selectedPaymentMethod != null;
    final paymentType = selectedPaymentMethod?.type.toString().split('.').last;
    final isDigitalPayment = ['gcash', 'maya'].contains(paymentType);
    final meetsMinimum = !isDigitalPayment || total >= PayMongoService.getMinimumAmount();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Payment summary row
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Amount',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '₱${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                    ],
                  ),
                  if (selectedPaymentMethod != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD32D43).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        selectedPaymentMethod!.title,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFD32D43),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Payment button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canProceed && meetsMinimum ? () async {
                  await _handlePaymentMethod();
                } : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD32D43),
                  disabledBackgroundColor: Colors.grey[300],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isDigitalPayment ? Icons.security : Icons.local_shipping,
                      color: canProceed && meetsMinimum ? Colors.white : Colors.grey[500],
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      canProceed 
                          ? (isDigitalPayment ? 'Pay Securely' : 'Place Order')
                          : 'Select Payment Method',
                      style: TextStyle(
                        color: canProceed && meetsMinimum ? Colors.white : Colors.grey[500],
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!meetsMinimum) ...[
              const SizedBox(height: 8),
              Text(
                'Minimum amount for ${selectedPaymentMethod!.title} is ${PayMongoService.formatAmount(PayMongoService.getMinimumAmount())}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.orange,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItemImage(String imagePath, {double? width, double? height}) {
    final imageUrl = ApiService.getImageUrl(imagePath);
    final isNetwork = ApiService.isNetworkImage(imagePath);
    
    if (isNetwork) {
      return Image.network(
        imageUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: width ?? 60,
            height: height ?? 60,
            color: Colors.grey[300],
            child: const Icon(
              Icons.ramen_dining,
              color: Colors.grey,
              size: 24,
            ),
          );
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: width ?? 60,
            height: height ?? 60,
            color: Colors.grey[200],
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
                strokeWidth: 2,
                color: const Color(0xFFD32D43),
              ),
            ),
          );
        },
      );
    } else {
      return Image.asset(
        imageUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: width ?? 60,
            height: height ?? 60,
            color: Colors.grey[300],
            child: const Icon(
              Icons.ramen_dining,
              color: Colors.grey,
              size: 24,
            ),
          );
        },
      );
    }
  }

  Widget _buildPaymentIcon(String paymentType) {
    switch (paymentType) {
      case 'gcash':
        return Image.asset(
          'assets/gcash_logo.png',
          width: 24,
          height: 24,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              Icons.account_balance_wallet,
              color: const Color(0xFF007DFF),
              size: 24,
            );
          },
        );
      case 'maya':
        return Image.asset(
          'assets/maya.png',
          width: 24,
          height: 24,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              Icons.credit_card,
              color: const Color(0xFF00BF63),
              size: 24,
            );
          },
        );
      case 'cash':
        return const Icon(
          Icons.money,
          color: Colors.green,
          size: 24,
        );
      default:
        return const Icon(
          Icons.payment,
          color: Colors.grey,
          size: 24,
        );
    }
  }

}