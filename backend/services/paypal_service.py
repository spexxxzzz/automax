"""
PayPal payment service for Suna - replaces Stripe for personal accounts
"""

import paypalrestsdk
from typing import Dict, Optional, Any
from utils.config import config
from utils.logger import logger

# Initialize PayPal SDK with fallback to environment variables
import os
paypal_client_id = config.PAYPAL_CLIENT_ID or os.getenv('PAYPAL_CLIENT_ID')
paypal_client_secret = config.PAYPAL_CLIENT_SECRET or os.getenv('PAYPAL_CLIENT_SECRET')
paypal_mode = config.PAYPAL_MODE or os.getenv('PAYPAL_MODE', 'sandbox')

paypalrestsdk.configure({
    "mode": paypal_mode,
    "client_id": paypal_client_id,
    "client_secret": paypal_client_secret
})

# Subscription tier pricing (same as Stripe tiers)
PAYPAL_SUBSCRIPTION_TIERS = {
    "tier_2_20": {"name": "2h/$1", "amount": 1.00, "hours": 2},  # TEMPORARY: Changed from $20 to $1 for testing
    "tier_6_50": {"name": "6h/$50", "amount": 50.00, "hours": 6},
    "tier_12_100": {"name": "12h/$100", "amount": 100.00, "hours": 12},
    "tier_25_200": {"name": "25h/$200", "amount": 200.00, "hours": 25},
    "tier_50_400": {"name": "50h/$400", "amount": 400.00, "hours": 50},
    "tier_125_800": {"name": "125h/$800", "amount": 800.00, "hours": 125},
    "tier_200_1000": {"name": "200h/$1000", "amount": 1000.00, "hours": 200},
}

def create_paypal_payment(tier_id: str, success_url: str, cancel_url: str, user_id: str = None) -> Dict[str, Any]:
    """Create a PayPal payment for subscription tier"""
    try:
        if tier_id not in PAYPAL_SUBSCRIPTION_TIERS:
            raise ValueError(f"Invalid tier ID: {tier_id}")
        
        tier = PAYPAL_SUBSCRIPTION_TIERS[tier_id]
        
        payment = paypalrestsdk.Payment({
            "intent": "sale",
            "payer": {
                "payment_method": "paypal"
            },
            "redirect_urls": {
                "return_url": success_url,
                "cancel_url": cancel_url
            },
            "transactions": [{
                "item_list": {
                    "items": [{
                        "name": f"Suna AI - {tier['name']}",
                        "sku": tier_id,
                        "price": str(tier['amount']),
                        "currency": "USD",
                        "quantity": 1
                    }]
                },
                "amount": {
                    "total": str(tier['amount']),
                    "currency": "USD"
                },
                "description": f"Suna AI subscription - {tier['name']} ({tier['hours']} hours)",
                "custom": user_id  # Store user_id for later retrieval
            }]
        })

        if payment.create():
            logger.info(f"PayPal payment created successfully: {payment.id}")
            
            # Find approval URL
            approval_url = None
            for link in payment.links:
                if link.rel == "approval_url":
                    approval_url = link.href
                    break
            
            return {
                "success": True,
                "payment_id": payment.id,
                "approval_url": approval_url,
                "status": "created"
            }
        else:
            logger.error(f"PayPal payment creation failed: {payment.error}")
            return {
                "success": False,
                "error": payment.error
            }
            
    except Exception as e:
        logger.error(f"Error creating PayPal payment: {str(e)}")
        return {
            "success": False,
            "error": str(e)
        }

def execute_paypal_payment(payment_id: str, payer_id: str) -> Dict[str, Any]:
    """Execute PayPal payment after user approval"""
    try:
        payment = paypalrestsdk.Payment.find(payment_id)
        
        if payment.execute({"payer_id": payer_id}):
            logger.info(f"PayPal payment executed successfully: {payment_id}")
            return {
                "success": True,
                "payment_id": payment_id,
                "status": "completed",
                "transaction_id": payment.transactions[0].related_resources[0].sale.id
            }
        else:
            logger.error(f"PayPal payment execution failed: {payment.error}")
            return {
                "success": False,
                "error": payment.error
            }
            
    except Exception as e:
        logger.error(f"Error executing PayPal payment: {str(e)}")
        return {
            "success": False,
            "error": str(e)
        }

def get_tier_from_stripe_price_id(stripe_price_id: str) -> Optional[str]:
    """Map Stripe price IDs to PayPal tier IDs"""
    stripe_to_paypal_mapping = {
        # Monthly subscriptions
        config.STRIPE_TIER_2_20_ID: "tier_2_20",
        config.STRIPE_TIER_6_50_ID: "tier_6_50", 
        config.STRIPE_TIER_12_100_ID: "tier_12_100",
        config.STRIPE_TIER_25_200_ID: "tier_25_200",
        config.STRIPE_TIER_50_400_ID: "tier_50_400",
        config.STRIPE_TIER_125_800_ID: "tier_125_800",
        config.STRIPE_TIER_200_1000_ID: "tier_200_1000",
        
        # Yearly subscriptions
        config.STRIPE_TIER_2_17_YEARLY_COMMITMENT_ID: "tier_2_20",
        config.STRIPE_TIER_6_42_YEARLY_COMMITMENT_ID: "tier_6_50",
        config.STRIPE_TIER_25_170_YEARLY_COMMITMENT_ID: "tier_25_200",
        config.STRIPE_TIER_2_20_YEARLY_ID: "tier_2_20",
        config.STRIPE_TIER_6_50_YEARLY_ID: "tier_6_50",
        config.STRIPE_TIER_12_100_YEARLY_ID: "tier_12_100",
        config.STRIPE_TIER_25_200_YEARLY_ID: "tier_25_200",
        config.STRIPE_TIER_50_400_YEARLY_ID: "tier_50_400",
        config.STRIPE_TIER_125_800_YEARLY_ID: "tier_125_800",
        config.STRIPE_TIER_200_1000_YEARLY_ID: "tier_200_1000",
    }
    
    return stripe_to_paypal_mapping.get(stripe_price_id)