import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PayMongoWebViewPage extends StatefulWidget {
  final String paymentUrl;
  final String paymentMethod;
  final double amount;

  const PayMongoWebViewPage({
    super.key,
    required this.paymentUrl,
    required this.paymentMethod,
    required this.amount,
  });

  @override
  State<PayMongoWebViewPage> createState() => _PayMongoWebViewPageState();
}

class _PayMongoWebViewPageState extends State<PayMongoWebViewPage> {
  late final WebViewController controller;
  bool isLoading = true;
  bool _hasNavigatedBack = false;

  @override
  void initState() {
    super.initState();
    
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Update loading bar
          },
          onPageStarted: (String url) {
            setState(() {
              isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            print('WebView error: ${error.description}');
          },
          onNavigationRequest: (NavigationRequest request) {
            print('🔗 Navigation request: ${request.url}');
            
            // Handle deep link redirects from PayMongo
            if (request.url.startsWith('ramenxpress://payment/')) {
              print('✅ Payment redirect detected: ${request.url}');
              
              // Prevent duplicate navigation
              if (_hasNavigatedBack) {
                print('🔄 Duplicate navigation prevented');
                return NavigationDecision.prevent;
              }
              
              _hasNavigatedBack = true;
              
              if (request.url.contains('success')) {
                print('✅ Payment successful - returning to app');
                Navigator.pop(context, true); // Return success
              } else if (request.url.contains('failed')) {
                print('❌ Payment failed - returning to app');
                Navigator.pop(context, false); // Return failure
              }
              
              return NavigationDecision.prevent; // Don't navigate to the deep link
            }
            
            // Allow all other navigation for PayMongo
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.paymentUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Row(
          children: [
            _buildPaymentMethodIcon(),
            const SizedBox(width: 8),
            Text('${widget.paymentMethod} Payment'),
          ],
        ),
        backgroundColor: const Color(0xFFD32D43),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () {
            _showExitConfirmation();
          },
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.refresh, size: 18),
              ),
              onPressed: () {
                controller.reload();
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Enhanced payment info bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFD32D43),
                  const Color(0xFFB91C3C),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.security,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Secure ${widget.paymentMethod} Payment',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Amount: ₱${widget.amount.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.95),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: const Text(
                          'PayMongo',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.white.withOpacity(0.9),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Complete your payment in the secure portal below',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Loading indicator
          if (isLoading)
            Container(
              width: double.infinity,
              height: 4,
              child: const LinearProgressIndicator(
                backgroundColor: Color(0xFFE9ECEF),
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD32D43)),
              ),
            ),
          
          // WebView
          Expanded(
            child: WebViewWidget(controller: controller),
          ),
          
          // Enhanced bottom action bar
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                  // Status indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.blue[600]),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Complete payment above, then tap "Payment Done"',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blue[700],
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            _showExitConfirmation();
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.red[300]!, width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            foregroundColor: Colors.red[600],
                            backgroundColor: Colors.red[50],
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            _completePayment();
                          },
                          icon: const Icon(Icons.check_circle, size: 16),
                          label: const Text(
                            'Payment Done',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD32D43),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
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
    );
  }

  Widget _buildPaymentMethodIcon() {
    switch (widget.paymentMethod.toLowerCase()) {
      case 'gcash':
        return Image.asset(
          'assets/gcash_logo.png',
          width: 20,
          height: 20,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(Icons.account_balance_wallet, size: 20);
          },
        );
      case 'maya':
        return Image.asset(
          'assets/maya.png',
          width: 20,
          height: 20,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(Icons.credit_card, size: 20);
          },
        );
      default:
        return const Icon(Icons.payment, size: 20);
    }
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.warning_amber, color: Colors.red[600], size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Cancel Payment?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to cancel this payment? Your order will not be processed and you\'ll return to the checkout page.',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Continue Payment',
              style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context, false); // Return to payment page with false
            },
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Cancel Payment'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  void _completePayment() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.check_circle, color: Colors.green[600], size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Payment Completed?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Have you successfully completed your payment in the secure portal above?',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber[700], size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Only confirm if you received a success message',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Not Yet',
              style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context, true); // Return to payment page with true
            },
            icon: const Icon(Icons.check_circle, size: 16),
            label: const Text('Yes, Completed'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32D43),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }
}
