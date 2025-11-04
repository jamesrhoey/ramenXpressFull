const axios = require('axios');
const QRCode = require('qrcode');

class PayMongoService {
    constructor() {
        this.baseURL = 'https://api.paymongo.com/v1';
        this.secretKey = process.env.PAYMONGO_SECRET_KEY;
        
        if (!this.secretKey) {
            console.warn('⚠️  PayMongo secret key not found. Please set PAYMONGO_SECRET_KEY in your environment variables.');
        }
    }

    // Generate QR code for POS payment using Sources API
    async generatePOSQRCode(amount, orderId, paymentMethod = 'gcash', frontendUrl = null) {
        try {
            console.log(`🔄 Generating ${paymentMethod} QR code for ₱${amount} (Order: ${orderId})`);

            // Map payment method to PayMongo source type
            const sourceTypeMap = {
                'gcash': 'gcash',
                'paymaya': 'gcash', // PayMaya uses same source type as GCash
                'grabpay': 'grab_pay'
            };

            const sourceType = sourceTypeMap[paymentMethod] || 'gcash';

            // Create source for QR code
            const response = await axios.post(`${this.baseURL}/sources`, {
                data: {
                    attributes: {
                        amount: Math.round(amount * 100), // Convert to centavos
                        currency: 'PHP',
                        type: sourceType,
                        redirect: {
                            success: `${frontendUrl || process.env.FRONTEND_URL || 'http://127.0.0.1:5501'}/frontend/html/pos.html?payment=success`,
                            failed: `${frontendUrl || process.env.FRONTEND_URL || 'http://127.0.0.1:5501'}/frontend/html/pos.html?payment=failed`
                        }
                    }
                }
            }, {
                headers: {
                    'Authorization': `Basic ${Buffer.from(this.secretKey + ':').toString('base64')}`,
                    'Content-Type': 'application/json'
                }
            });

            const source = response.data.data;
            console.log(`✅ Source created: ${source.id}`);

            // Get redirect URL for QR code
            const redirectUrl = source.attributes.redirect.checkout_url;
            console.log(`✅ Redirect URL: ${redirectUrl}`);

            // Generate QR code
            const qrCodeDataURL = await QRCode.toDataURL(redirectUrl, {
                width: 400, // Larger for POS display
                margin: 2,
                color: {
                    dark: '#000000',
                    light: '#FFFFFF'
                }
            });

            console.log(`✅ QR code generated for ${paymentMethod}`);

            return {
                success: true,
                data: {
                    sourceId: source.id,
                    redirectUrl: redirectUrl,
                    qrCodeDataURL: qrCodeDataURL,
                    amount: amount,
                    orderId: orderId,
                    paymentMethod: paymentMethod,
                    status: source.attributes.status,
                    createdAt: new Date()
                }
            };

        } catch (error) {
            console.error('❌ PayMongo QR generation error:', error.response?.data || error.message);
            return {
                success: false,
                error: error.response?.data?.errors?.[0]?.detail || error.message
            };
        }
    }

    // Generate direct payment for mobile app (no QR code)
    async generateMobileDirectPayment(amount, orderId, paymentMethod = 'gcash') {
        try {
            console.log(`🔄 Generating mobile ${paymentMethod} payment for ₱${amount} (Order: ${orderId})`);
            
            // Check if secret key is available
            if (!this.secretKey) {
                console.error('❌ PayMongo secret key not configured');
                return {
                    success: false,
                    error: 'PayMongo secret key not configured. Please set PAYMONGO_SECRET_KEY in environment variables.'
                };
            }
            
            console.log('🔑 PayMongo secret key is configured');

            // Map payment method to PayMongo source type
            const sourceTypeMap = {
                'gcash': 'gcash',
                'paymaya': 'gcash', // PayMaya uses same source type as GCash
                'grabpay': 'grab_pay'
            };

            const sourceType = sourceTypeMap[paymentMethod] || 'gcash';

            const requestData = {
                data: {
                    attributes: {
                        amount: Math.round(amount * 100), // Convert to centavos
                        currency: 'PHP',
                        type: sourceType,
                        redirect: {
                            success: 'http://192.168.0.106:3000/api/v1/paymongo/mobile-payment-success',
                            failed: 'http://192.168.0.106:3000/api/v1/paymongo/mobile-payment-failed'
                        }
                    }
                }
            };
            
            console.log('📤 PayMongo API request:', JSON.stringify(requestData, null, 2));
            
            // Create source for mobile payment with simple success page
            const response = await axios.post(`${this.baseURL}/sources`, requestData, {
                headers: {
                    'Authorization': `Basic ${Buffer.from(this.secretKey + ':').toString('base64')}`,
                    'Content-Type': 'application/json'
                }
            });
            
            console.log('📥 PayMongo API response status:', response.status);
            console.log('📥 PayMongo API response data:', JSON.stringify(response.data, null, 2));

            const source = response.data.data;
            console.log(`✅ Mobile source created: ${source.id}`);

            // Get redirect URL for mobile payment
            const redirectUrl = source.attributes.redirect.checkout_url;
            console.log(`✅ Mobile redirect URL: ${redirectUrl}`);

            return {
                success: true,
                data: {
                    sourceId: source.id,
                    redirectUrl: redirectUrl,
                    amount: amount,
                    orderId: orderId,
                    paymentMethod: paymentMethod,
                    status: source.attributes.status,
                    createdAt: new Date()
                }
            };

        } catch (error) {
            console.error('❌ PayMongo mobile payment error:', error.response?.data || error.message);
            return {
                success: false,
                error: error.response?.data?.errors?.[0]?.detail || error.message
            };
        }
    }

    // Verify payment intent status
    async verifyPaymentIntent(paymentIntentId) {
        try {
            const response = await axios.get(`${this.baseURL}/payment_intents/${paymentIntentId}`, {
                headers: {
                    'Authorization': `Basic ${Buffer.from(this.secretKey + ':').toString('base64')}`,
                    'Content-Type': 'application/json'
                }
            });

            return {
                success: true,
                data: response.data.data
            };
        } catch (error) {
            console.error('PayMongo verifyPaymentIntent error:', error.response?.data || error.message);
            return {
                success: false,
                error: error.response?.data || error.message
            };
        }
    }

    // Legacy method for backward compatibility
    async verifyPaymentSource(sourceId) {
        // If it looks like a payment intent ID, use the new method
        if (sourceId && sourceId.startsWith('pi_')) {
            return await this.verifyPaymentIntent(sourceId);
        }
        
        try {
            const response = await axios.get(`${this.baseURL}/sources/${sourceId}`, {
                headers: {
                    'Authorization': `Basic ${Buffer.from(this.secretKey + ':').toString('base64')}`,
                    'Content-Type': 'application/json'
                }
            });

            return {
                success: true,
                data: response.data.data
            };
        } catch (error) {
            console.error('PayMongo verifyPaymentSource error:', error.response?.data || error.message);
            return {
                success: false,
                error: error.response?.data || error.message
            };
        }
    }

    // Charge a chargeable payment source
    async chargePaymentSource(sourceId, amount) {
        try {
            console.log(`💳 Charging payment source: ${sourceId} for ₱${amount}`);

            const response = await axios.post(`${this.baseURL}/payments`, {
                data: {
                    attributes: {
                        amount: Math.round(amount * 100), // Convert to centavos
                        currency: 'PHP',
                        source: {
                            id: sourceId,
                            type: 'source'
                        }
                    }
                }
            }, {
                headers: {
                    'Authorization': `Basic ${Buffer.from(this.secretKey + ':').toString('base64')}`,
                    'Content-Type': 'application/json'
                }
            });

            console.log(`✅ Payment charged successfully: ${response.data.data.id}`);
            return {
                success: true,
                data: response.data.data
            };
        } catch (error) {
            console.error('❌ Payment charging failed:', error.response?.data || error.message);
            return {
                success: false,
                error: error.response?.data || error.message
            };
        }
    }

    // Create payment intent for card payments (if needed later)
    async createPaymentIntent(amount, currency = 'PHP', description = 'RamenXpress POS Order') {
        try {
            const response = await axios.post(`${this.baseURL}/payment_intents`, {
                data: {
                    attributes: {
                        amount: Math.round(amount * 100),
                        currency: currency,
                        description: description,
                        payment_method_allowed: ['card', 'paymaya', 'gcash']
                    }
                }
            }, {
                headers: {
                    'Authorization': `Basic ${Buffer.from(this.secretKey + ':').toString('base64')}`,
                    'Content-Type': 'application/json'
                }
            });

            return {
                success: true,
                data: response.data.data
            };
        } catch (error) {
            console.error('PayMongo createPaymentIntent error:', error.response?.data || error.message);
            return {
                success: false,
                error: error.response?.data || error.message
            };
        }
    }
}

module.exports = new PayMongoService();
