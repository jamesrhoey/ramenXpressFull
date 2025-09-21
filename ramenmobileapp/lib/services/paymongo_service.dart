import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class PayMongoService {
  static const String _baseUrl = 'http://192.168.0.106:3000/api/v1/paymongo'; // Correct path with /v1
  
  // Get authentication token
  static Future<String?> _getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('auth_token');
    } catch (e) {
      print('Error getting token: $e');
      return null;
    }
  }
  
  // Method 1: Direct Redirect Payment (No QR Code - Automation Friendly)
  static Future<Map<String, dynamic>> createDirectPayment({
    required double amount,
    required String orderId,
    required String paymentMethod, // 'gcash' or 'paymaya'
  }) async {
    try {
      print('🔄 Creating direct $paymentMethod payment for ₱$amount (Order: $orderId)');
      
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication token not found');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/create-direct-payment'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'amount': amount,
          'orderId': orderId,
          'paymentMethod': paymentMethod,
          'successUrl': 'ramenxpress://payment/success',
          'failureUrl': 'ramenxpress://payment/failed',
        }),
      );

      print('🔍 Response status: ${response.statusCode}');
      print('🔍 Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          print('✅ Direct payment created successfully');
          return {
            'success': true,
            'sourceId': data['data']['sourceId'],
            'checkoutUrl': data['data']['checkoutUrl'], 
            'amount': data['data']['amount'],
            'orderId': data['data']['orderId'],
            'paymentMethod': data['data']['paymentMethod'],
          };
        } else {
          print('❌ Backend returned success=false: ${data['message']}');
          throw Exception(data['message'] ?? 'Failed to create payment');
        }
      } else {
        print('❌ HTTP Error ${response.statusCode}: ${response.body}');
        try {
          final errorData = jsonDecode(response.body);
          throw Exception(errorData['message'] ?? 'Server error: ${response.statusCode}');
        } catch (e) {
          throw Exception('Server error: ${response.statusCode} - ${response.body}');
        }
      }
    } catch (e) {
      print('❌ Direct payment creation error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // Method 2: Payment Intent with Test Cards (Best for Automation)
  static Future<Map<String, dynamic>> createPaymentIntent({
    required double amount,
    required String orderId,
    String description = 'RamenXpress Order',
  }) async {
    try {
      print('🔄 Creating payment intent for ₱$amount (Order: $orderId)');
      
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication token not found');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/create-payment-intent'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'amount': amount,
          'orderId': orderId,
          'description': description,
          'paymentMethods': ['card', 'gcash', 'paymaya'], // Multiple options
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          print('✅ Payment intent created successfully');
          return {
            'success': true,
            'paymentIntentId': data['data']['paymentIntentId'],
            'clientKey': data['data']['clientKey'],
            'checkoutUrl': data['data']['checkoutUrl'],
            'amount': data['data']['amount'],
            'orderId': data['data']['orderId'],
          };
        } else {
          throw Exception(data['message'] ?? 'Failed to create payment intent');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Payment intent creation error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // Method 3: Simulate Payment (Development/Testing Only)
  static Future<Map<String, dynamic>> simulatePayment({
    required double amount,
    required String orderId,
    required String paymentMethod,
    bool shouldSucceed = true, // For testing different outcomes
  }) async {
    try {
      print('🧪 Simulating $paymentMethod payment for ₱$amount (Order: $orderId)');
      
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication token not found');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/simulate-payment'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'amount': amount,
          'orderId': orderId,
          'paymentMethod': paymentMethod,
          'shouldSucceed': shouldSucceed,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          print('✅ Payment simulation completed');
          return {
            'success': true,
            'paymentId': data['data']['paymentId'],
            'status': data['data']['status'],
            'amount': data['data']['amount'],
            'orderId': data['data']['orderId'],
            'paymentMethod': data['data']['paymentMethod'],
            'isSimulated': true,
          };
        } else {
          throw Exception(data['message'] ?? 'Payment simulation failed');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Payment simulation error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // Open payment URL in browser/webview (User-friendly with fallback)
  static Future<bool> openPaymentUrl(String checkoutUrl) async {
    try {
      print('🔗 Attempting to open payment URL: $checkoutUrl');
      
      final uri = Uri.parse(checkoutUrl);
      
      // Try to check if URL can be launched
      bool canLaunch = false;
      try {
        canLaunch = await canLaunchUrl(uri);
      } catch (e) {
        print('⚠️ Cannot check URL launch capability: $e');
        canLaunch = true; // Assume it can be launched
      }
      
      if (canLaunch) {
        try {
          await launchUrl(
            uri,
            mode: LaunchMode.externalApplication, // Opens in external browser
          );
          print('✅ Payment URL opened successfully');
          return true;
        } catch (e) {
          print('⚠️ Failed to launch URL with external app, trying platform default: $e');
          try {
            await launchUrl(uri, mode: LaunchMode.platformDefault);
            print('✅ Payment URL opened with platform default');
            return true;
          } catch (e2) {
            print('❌ All URL launch methods failed: $e2');
            return false;
          }
        }
      } else {
        print('❌ Cannot launch payment URL: $checkoutUrl');
        return false;
      }
    } catch (e) {
      print('❌ Error opening payment URL: $e');
      return false;
    }
  }

  // Verify payment status (works with all methods)
  static Future<Map<String, dynamic>> verifyPayment(String paymentId) async {
    try {
      print('🔍 Verifying payment status for: $paymentId');
      
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication token not found');
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/verify-payment/$paymentId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          final status = data['data']['status'];
          print('📊 Payment status: $status');
          
          return {
            'success': true,
            'id': data['data']['id'],
            'status': status,
            'amount': data['data']['amount'],
            'currency': data['data']['currency'],
            'isPaid': status == 'paid' || status == 'succeeded' || status == 'chargeable',
            'isPending': status == 'pending' || status == 'awaiting_payment_method',
            'isFailed': status == 'failed' || status == 'cancelled',
          };
        } else {
          throw Exception(data['message'] ?? 'Payment verification failed');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Payment verification error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // Get test card information for development
  static Map<String, dynamic> getTestCards() {
    return {
      'success_card': {
        'number': '4242424242424242',
        'expiry': '12/25',
        'cvc': '123',
        'description': 'Always succeeds',
      },
      'decline_card': {
        'number': '4000000000000002',
        'expiry': '12/25',
        'cvc': '123',
        'description': 'Always declines',
      },
      'auth_required_card': {
        'number': '4000000000009995',
        'expiry': '12/25',
        'cvc': '123',
        'description': 'Requires authentication',
      },
    };
  }

  // Check if payment method is supported
  static bool isPaymentMethodSupported(String paymentMethod) {
    return ['gcash', 'paymaya', 'maya', 'card'].contains(paymentMethod.toLowerCase());
  }

  // Get minimum payment amount
  static double getMinimumAmount() {
    return 20.0; // PayMongo requires minimum ₱20
  }

  // Format amount for display
  static String formatAmount(double amount) {
    return '₱${amount.toStringAsFixed(2)}';
  }

  // Generate order ID for PayMongo
  static String generateOrderId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'MOBILE-$timestamp';
  }
}
