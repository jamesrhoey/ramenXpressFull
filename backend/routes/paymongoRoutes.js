const express = require('express');
const router = express.Router();
const paymongoService = require('../services/paymongoService');
const authMiddleware = require('../middleware/authMiddleware');

// Generate QR code for POS payment
router.post('/pos/generate-qr', authMiddleware, async (req, res) => {
    try {
        const { amount, orderId, paymentMethod } = req.body;

        // Validation
        if (!amount || amount <= 0) {
            return res.status(400).json({
                success: false,
                message: 'Invalid amount provided'
            });
        }

        if (!paymentMethod || !['gcash', 'paymaya'].includes(paymentMethod)) {
            return res.status(400).json({
                success: false,
                message: 'Payment method must be gcash or paymaya'
            });
        }

        // Minimum amount check (PayMongo requires at least 20 PHP)
        if (amount < 20) {
            return res.status(400).json({
                success: false,
                message: 'Minimum amount is ₱20.00'
            });
        }

        console.log(`📱 POS QR Request: ${paymentMethod} - ₱${amount} (${orderId})`);

        // Get frontend URL from request headers or use default
        let frontendUrl = req.headers.origin || req.headers.referer?.replace(/\/[^/]*$/, '');
        
        // If no origin/referer, use Live Server default
        if (!frontendUrl) {
            frontendUrl = 'http://127.0.0.1:5501';
        }
        
        console.log(`🌐 Using frontend URL: ${frontendUrl}`);

        const result = await paymongoService.generatePOSQRCode(
            amount, 
            orderId || `POS-${Date.now()}`, 
            paymentMethod,
            frontendUrl
        );

        if (result.success) {
            console.log(`✅ QR Code generated successfully for ${paymentMethod}`);
            res.json({
                success: true,
                data: {
                    sourceId: result.data.sourceId,
                    redirectUrl: result.data.redirectUrl,
                    qrCodeDataURL: result.data.qrCodeDataURL,
                    amount: result.data.amount,
                    orderId: result.data.orderId,
                    paymentMethod: result.data.paymentMethod,
                    status: result.data.status
                }
            });
        } else {
            console.error(`❌ QR Code generation failed:`, result.error);
            res.status(400).json({
                success: false,
                message: 'Failed to generate QR code',
                error: result.error
            });
        }
    } catch (error) {
        console.error('Generate POS QR code error:', error);
        res.status(500).json({
            success: false,
            message: 'Internal server error'
        });
    }
});

// Verify payment status (supports both Payment Intent and Source IDs)
router.get('/pos/verify-payment/:paymentId', authMiddleware, async (req, res) => {
    try {
        const { paymentId } = req.params;

        if (!paymentId) {
            return res.status(400).json({
                success: false,
                message: 'Payment ID is required'
            });
        }

        console.log(`🔍 Verifying payment status for: ${paymentId}`);

        const result = await paymongoService.verifyPaymentSource(paymentId);

        if (result.success) {
            const status = result.data.attributes.status;
            console.log(`📊 Payment status: ${status}`);
            
            res.json({
                success: true,
                data: {
                    id: result.data.id,
                    status: status,
                    amount: result.data.attributes.amount / 100,
                    currency: result.data.attributes.currency,
                    createdAt: result.data.attributes.created_at,
                    updatedAt: result.data.attributes.updated_at || result.data.attributes.created_at
                }
            });
        } else {
            console.error(`❌ Payment verification failed:`, result.error);
            res.status(400).json({
                success: false,
                message: 'Payment verification failed',
                error: result.error
            });
        }
    } catch (error) {
        console.error('Verify POS payment error:', error);
        res.status(500).json({
            success: false,
            message: 'Internal server error'
        });
    }
});

// Get payment source details
router.get('/pos/payment-details/:sourceId', authMiddleware, async (req, res) => {
    try {
        const { sourceId } = req.params;

        if (!sourceId) {
            return res.status(400).json({
                success: false,
                message: 'Source ID is required'
            });
        }

        const result = await paymongoService.verifyPaymentSource(sourceId);

        if (result.success) {
            res.json({
                success: true,
                data: result.data
            });
        } else {
            res.status(400).json({
                success: false,
                message: 'Failed to retrieve payment details',
                error: result.error
            });
        }
    } catch (error) {
        console.error('Get payment details error:', error);
        res.status(500).json({
            success: false,
            message: 'Internal server error'
        });
    }
});

// Charge a chargeable payment source
router.post('/pos/charge-payment', authMiddleware, async (req, res) => {
    try {
        const { sourceId, amount } = req.body;

        if (!sourceId || !amount) {
            return res.status(400).json({
                success: false,
                message: 'Source ID and amount are required'
            });
        }

        console.log(`💳 Charging payment: ${sourceId} for ₱${amount}`);

        const result = await paymongoService.chargePaymentSource(sourceId, amount);

        if (result.success) {
            console.log(`✅ Payment charged successfully`);
            res.json({
                success: true,
                data: {
                    paymentId: result.data.id,
                    status: result.data.attributes.status,
                    amount: result.data.attributes.amount / 100,
                    currency: result.data.attributes.currency
                }
            });
        } else {
            console.error(`❌ Payment charging failed:`, result.error);
            res.status(400).json({
                success: false,
                message: 'Failed to charge payment',
                error: result.error
            });
        }
    } catch (error) {
        console.error('Charge payment error:', error);
        res.status(500).json({
            success: false,
            message: 'Internal server error'
        });
    }
});

// Create direct payment (no QR code - automation friendly)
router.post('/create-direct-payment', authMiddleware, async (req, res) => {
    try {
        const { amount, orderId, paymentMethod, successUrl, failureUrl } = req.body;

        // Validation
        if (!amount || amount <= 0) {
            return res.status(400).json({
                success: false,
                message: 'Invalid amount provided'
            });
        }

        if (!paymentMethod || !['gcash', 'paymaya'].includes(paymentMethod)) {
            return res.status(400).json({
                success: false,
                message: 'Payment method must be gcash or paymaya'
            });
        }

        if (amount < 20) {
            return res.status(400).json({
                success: false,
                message: 'Minimum amount is ₱20.00'
            });
        }

        console.log(`📱 Direct Payment Request: ${paymentMethod} - ₱${amount} (${orderId})`);
        console.log('📋 Request body:', req.body);

        // Create source for mobile payment (no QR code, mobile-friendly redirect)
        const result = await paymongoService.generateMobileDirectPayment(
            amount, 
            orderId || `MOBILE-${Date.now()}`, 
            paymentMethod
        );
        
        console.log('🔍 PayMongo service result:', result);

        if (result.success) {
            console.log(`✅ Direct payment created successfully for ${paymentMethod}`);
            res.json({
                success: true,
                data: {
                    sourceId: result.data.sourceId,
                    checkoutUrl: result.data.redirectUrl, // Direct URL instead of QR
                    amount: result.data.amount,
                    orderId: result.data.orderId,
                    paymentMethod: result.data.paymentMethod,
                    status: result.data.status
                }
            });
        } else {
            console.error(`❌ Direct payment creation failed:`, result.error);
            res.status(400).json({
                success: false,
                message: 'Failed to create direct payment',
                error: result.error
            });
        }
    } catch (error) {
        console.error('Create direct payment error:', error);
        res.status(500).json({
            success: false,
            message: 'Internal server error'
        });
    }
});

// Create payment intent (best for automation with test cards)
router.post('/create-payment-intent', authMiddleware, async (req, res) => {
    try {
        const { amount, orderId, description, paymentMethods } = req.body;

        if (!amount || amount <= 0) {
            return res.status(400).json({
                success: false,
                message: 'Invalid amount provided'
            });
        }

        if (amount < 20) {
            return res.status(400).json({
                success: false,
                message: 'Minimum amount is ₱20.00'
            });
        }

        console.log(`💳 Payment Intent Request: ₱${amount} (${orderId})`);

        const result = await paymongoService.createPaymentIntent(
            amount,
            'PHP',
            description || `RamenXpress Order ${orderId}`
        );

        if (result.success) {
            const paymentIntent = result.data;
            console.log(`✅ Payment intent created: ${paymentIntent.id}`);
            
            res.json({
                success: true,
                data: {
                    paymentIntentId: paymentIntent.id,
                    clientKey: paymentIntent.attributes.client_key,
                    checkoutUrl: `https://api.paymongo.com/v1/payment_intents/${paymentIntent.id}/attach`,
                    amount: amount,
                    orderId: orderId,
                    status: paymentIntent.attributes.status
                }
            });
        } else {
            console.error(`❌ Payment intent creation failed:`, result.error);
            res.status(400).json({
                success: false,
                message: 'Failed to create payment intent',
                error: result.error
            });
        }
    } catch (error) {
        console.error('Create payment intent error:', error);
        res.status(500).json({
            success: false,
            message: 'Internal server error'
        });
    }
});

// Simulate payment (development/testing only)
router.post('/simulate-payment', authMiddleware, async (req, res) => {
    try {
        const { amount, orderId, paymentMethod, shouldSucceed } = req.body;

        if (!amount || amount <= 0) {
            return res.status(400).json({
                success: false,
                message: 'Invalid amount provided'
            });
        }

        console.log(`🧪 Simulating ${paymentMethod} payment: ₱${amount} (${orderId}) - ${shouldSucceed ? 'SUCCESS' : 'FAILURE'}`);

        // Simulate payment processing delay
        await new Promise(resolve => setTimeout(resolve, 2000));

        const simulatedPaymentId = `sim_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
        const status = shouldSucceed ? 'paid' : 'failed';

        console.log(`✅ Payment simulation completed: ${status}`);

        res.json({
            success: true,
            data: {
                paymentId: simulatedPaymentId,
                status: status,
                amount: amount,
                orderId: orderId,
                paymentMethod: paymentMethod,
                isSimulated: true,
                simulatedAt: new Date().toISOString()
            }
        });

    } catch (error) {
        console.error('Simulate payment error:', error);
        res.status(500).json({
            success: false,
            message: 'Internal server error'
        });
    }
});

// Enhanced verify payment (supports all payment types)
router.get('/verify-payment/:paymentId', authMiddleware, async (req, res) => {
    try {
        const { paymentId } = req.params;

        if (!paymentId) {
            return res.status(400).json({
                success: false,
                message: 'Payment ID is required'
            });
        }

        console.log(`🔍 Verifying payment status for: ${paymentId}`);

        // Handle simulated payments
        if (paymentId.startsWith('sim_')) {
            console.log(`🧪 Simulated payment verification: ${paymentId}`);
            
            // Extract status from simulated payment ID or assume success
            const status = paymentId.includes('fail') ? 'failed' : 'paid';
            
            return res.json({
                success: true,
                data: {
                    id: paymentId,
                    status: status,
                    amount: 0, // Would need to store this in real implementation
                    currency: 'PHP',
                    createdAt: new Date().toISOString(),
                    updatedAt: new Date().toISOString(),
                    isSimulated: true
                }
            });
        }

        // Handle real PayMongo payments
        const result = await paymongoService.verifyPaymentSource(paymentId);

        if (result.success) {
            const status = result.data.attributes.status;
            console.log(`📊 Payment status: ${status}`);
            
            res.json({
                success: true,
                data: {
                    id: result.data.id,
                    status: status,
                    amount: result.data.attributes.amount / 100,
                    currency: result.data.attributes.currency,
                    createdAt: result.data.attributes.created_at,
                    updatedAt: result.data.attributes.updated_at || result.data.attributes.created_at
                }
            });
        } else {
            console.error(`❌ Payment verification failed:`, result.error);
            res.status(400).json({
                success: false,
                message: 'Payment verification failed',
                error: result.error
            });
        }
    } catch (error) {
        console.error('Verify payment error:', error);
        res.status(500).json({
            success: false,
            message: 'Internal server error'
        });
    }
});

// Get test card information for development
router.get('/test-cards', (req, res) => {
    res.json({
        success: true,
        data: {
            success_card: {
                number: '4242424242424242',
                expiry: '12/25',
                cvc: '123',
                description: 'Always succeeds - Use for automated testing'
            },
            decline_card: {
                number: '4000000000000002',
                expiry: '12/25',
                cvc: '123',
                description: 'Always declines - Use for failure testing'
            },
            auth_required_card: {
                number: '4000000000009995',
                expiry: '12/25',
                cvc: '123',
                description: 'Requires authentication - Use for 3DS testing'
            }
        }
    });
});

// Mobile payment success redirect handler
router.get('/mobile-payment-success', (req, res) => {
    console.log('✅ Mobile payment success redirect received');
    console.log('📋 Query params:', req.query);
    
    // Return HTML page that triggers deep link
    res.send(`
        <!DOCTYPE html>
        <html>
        <head>
            <title>Payment Successful</title>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    text-align: center;
                    padding: 50px 20px;
                    background: linear-gradient(135deg, #28a745, #20c997);
                    color: white;
                    margin: 0;
                    min-height: 100vh;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                }
                .container {
                    background: rgba(255, 255, 255, 0.1);
                    padding: 40px;
                    border-radius: 20px;
                    backdrop-filter: blur(10px);
                    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
                    max-width: 400px;
                }
                .icon {
                    font-size: 64px;
                    margin-bottom: 20px;
                }
                h1 {
                    margin: 0 0 10px 0;
                    font-size: 24px;
                }
                p {
                    margin: 0 0 30px 0;
                    opacity: 0.9;
                }
                .btn {
                    background: rgba(255, 255, 255, 0.2);
                    border: 2px solid rgba(255, 255, 255, 0.3);
                    color: white;
                    padding: 12px 24px;
                    border-radius: 25px;
                    text-decoration: none;
                    font-weight: bold;
                    transition: all 0.3s ease;
                }
                .btn:hover {
                    background: rgba(255, 255, 255, 0.3);
                    transform: translateY(-2px);
                }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="icon">✅</div>
                <h1>Payment Successful!</h1>
                <p>Your payment has been completed successfully.</p>
                <a href="ramenxpress://payment/success" class="btn" onclick="handleReturn()">Return to App</a>
                <script>
                    function handleReturn() {
                        // Try to open the app
                        window.location.href = 'ramenxpress://payment/success';
                        // Fallback: close window after a delay
                        setTimeout(() => {
                            window.close();
                        }, 1000);
                    }
                    
                    // Auto-redirect after 3 seconds
                    setTimeout(() => {
                        handleReturn();
                    }, 3000);
                </script>
            </div>
        </body>
        </html>
    `);
});

// Mobile payment failed redirect handler
router.get('/mobile-payment-failed', (req, res) => {
    console.log('❌ Mobile payment failed redirect received');
    console.log('📋 Query params:', req.query);
    
    // Return HTML page that triggers deep link
    res.send(`
        <!DOCTYPE html>
        <html>
        <head>
            <title>Payment Failed</title>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    text-align: center;
                    padding: 50px 20px;
                    background: linear-gradient(135deg, #dc3545, #e74c3c);
                    color: white;
                    margin: 0;
                    min-height: 100vh;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                }
                .container {
                    background: rgba(255, 255, 255, 0.1);
                    padding: 40px;
                    border-radius: 20px;
                    backdrop-filter: blur(10px);
                    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
                    max-width: 400px;
                }
                .icon {
                    font-size: 64px;
                    margin-bottom: 20px;
                }
                h1 {
                    margin: 0 0 10px 0;
                    font-size: 24px;
                }
                p {
                    margin: 0 0 30px 0;
                    opacity: 0.9;
                }
                .btn {
                    background: rgba(255, 255, 255, 0.2);
                    border: 2px solid rgba(255, 255, 255, 0.3);
                    color: white;
                    padding: 12px 24px;
                    border-radius: 25px;
                    text-decoration: none;
                    font-weight: bold;
                    transition: all 0.3s ease;
                }
                .btn:hover {
                    background: rgba(255, 255, 255, 0.3);
                    transform: translateY(-2px);
                }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="icon">❌</div>
                <h1>Payment Failed</h1>
                <p>Your payment could not be completed. Please try again.</p>
                <a href="ramenxpress://payment/failed" class="btn" onclick="handleReturn()">Return to App</a>
                <script>
                    function handleReturn() {
                        // Try to open the app
                        window.location.href = 'ramenxpress://payment/failed';
                        // Fallback: close window after a delay
                        setTimeout(() => {
                            window.close();
                        }, 1000);
                    }
                    
                    // Auto-redirect after 3 seconds
                    setTimeout(() => {
                        handleReturn();
                    }, 3000);
                </script>
            </div>
        </body>
        </html>
    `);
});

module.exports = router;
