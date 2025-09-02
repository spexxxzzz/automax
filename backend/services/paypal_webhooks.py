"""
PayPal webhook handler for payment confirmations
"""

from fastapi import APIRouter, Request, HTTPException
from services.paypal_service import execute_paypal_payment, get_tier_from_stripe_price_id, PAYPAL_SUBSCRIPTION_TIERS
from utils.logger import logger
from services.supabase import DBConnection
from datetime import datetime, timezone, timedelta
import json
import paypalrestsdk

router = APIRouter()

@router.post("/paypal/webhook")
async def handle_paypal_webhook(request: Request):
    """Handle PayPal webhook events"""
    try:
        body = await request.body()
        webhook_data = json.loads(body)
        
        event_type = webhook_data.get("event_type")
        logger.info(f"Received PayPal webhook: {event_type}")
        
        if event_type == "PAYMENT.SALE.COMPLETED":
            # Handle successful payment
            resource = webhook_data.get("resource", {})
            payment_id = resource.get("parent_payment")
            
            if payment_id:
                await upgrade_user_after_paypal_payment(payment_id)
                
        return {"status": "success"}
        
    except Exception as e:
        logger.error(f"Error handling PayPal webhook: {str(e)}")
        raise HTTPException(status_code=500, detail="Webhook processing failed")

@router.get("/paypal/success")
async def paypal_success(paymentId: str, PayerID: str):
    """Handle PayPal payment success callback"""
    try:
        # Execute the payment
        result = execute_paypal_payment(paymentId, PayerID)
        
        if result.get("success"):
            # Upgrade user after successful payment execution
            await upgrade_user_after_paypal_payment(paymentId)
            logger.info(f"PayPal payment executed and user upgraded: {paymentId}")
            return {"status": "success", "message": "Payment completed successfully"}
        else:
            logger.error(f"PayPal payment execution failed: {result.get('error')}")
            return {"status": "error", "message": "Payment execution failed"}
            
    except Exception as e:
        logger.error(f"Error in PayPal success callback: {str(e)}")
        raise HTTPException(status_code=500, detail="Payment processing failed")

async def upgrade_user_after_paypal_payment(payment_id: str):
    """Upgrade user to paid tier after successful PayPal payment"""
    try:
        # Get payment details from PayPal
        payment = paypalrestsdk.Payment.find(payment_id)
        
        if not payment:
            logger.error(f"PayPal payment not found: {payment_id}")
            return
        
        # Extract user_id and tier from payment
        user_id = None
        tier_id = None
        
        for transaction in payment.transactions:
            user_id = transaction.get("custom")  # User ID stored in custom field
            if transaction.get("item_list", {}).get("items"):
                tier_id = transaction["item_list"]["items"][0].get("sku")
                break
        
        if not user_id or not tier_id:
            logger.error(f"Missing user_id ({user_id}) or tier_id ({tier_id}) in PayPal payment {payment_id}")
            return
        
        logger.info(f"Upgrading user {user_id} to tier {tier_id} after PayPal payment {payment_id}")
        
        # Get tier info
        tier_info = PAYPAL_SUBSCRIPTION_TIERS.get(tier_id)
        if not tier_info:
            logger.error(f"Unknown tier_id: {tier_id}")
            return
        
        # Update database
        db = DBConnection()
        client = await db.client
        
        # Create or update billing customer
        customer_data = {
            'id': user_id,
            'account_id': user_id,
            'email': payment.payer.get("payer_info", {}).get("email", ""),
            'active': True,
            'provider': 'paypal'
        }
        
        try:
            # Try to insert new customer
            await client.schema('basejump').from_('billing_customers').insert(customer_data).execute()
            logger.info(f"Created new PayPal customer: {user_id}")
        except Exception:
            # Customer exists, update it
            await client.schema('basejump').from_('billing_customers').update({
                'active': True,
                'provider': 'paypal'
            }).eq('id', user_id).execute()
            logger.info(f"Updated existing customer to active: {user_id}")
        
        # Create subscription record
        now = datetime.now(timezone.utc)
        subscription_data = {
            'id': f"paypal_{payment_id}",
            'account_id': user_id,
            'billing_customer_id': user_id,
            'status': 'active',
            'price_id': f"paypal_{tier_id}",
            'plan_name': tier_info['name'],
            'quantity': 1,
            'cancel_at_period_end': False,
            'created': now.isoformat(),
            'current_period_start': now.isoformat(),
            'current_period_end': (now + timedelta(days=30)).isoformat(),  # 30-day subscription
            'provider': 'paypal',
            'metadata': {
                'paypal_payment_id': payment_id,
                'tier_id': tier_id,
                'amount': tier_info['amount'],
                'hours': tier_info['hours']
            }
        }
        
        try:
            await client.schema('basejump').from_('billing_subscriptions').insert(subscription_data).execute()
            logger.info(f"Created PayPal subscription for user {user_id}: {tier_id}")
        except Exception as e:
            logger.error(f"Failed to create subscription record: {str(e)}")
            # Try to update existing subscription
            await client.schema('basejump').from_('billing_subscriptions').update({
                'status': 'active',
                'current_period_start': now.isoformat(),
                'current_period_end': (now + timedelta(days=30)).isoformat(),
            }).eq('id', f"paypal_{payment_id}").execute()
            logger.info(f"Updated existing PayPal subscription: {user_id}")
        
        logger.info(f"✅ Successfully upgraded user {user_id} to {tier_id} after PayPal payment")
        
    except Exception as e:
        logger.error(f"Error upgrading user after PayPal payment {payment_id}: {str(e)}", exc_info=True)