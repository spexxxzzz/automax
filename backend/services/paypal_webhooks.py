"""
PayPal webhook handler for payment confirmations
"""

from fastapi import APIRouter, Request, HTTPException
from services.paypal_service import execute_paypal_payment
from utils.logger import logger
from services.supabase import DBConnection
import json

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
                # Update user subscription status in database
                db = DBConnection()
                client = await db.client
                
                # Here you would update the user's subscription status
                # This is a simplified version - you'd need to track user_id with payment_id
                logger.info(f"PayPal payment completed: {payment_id}")
                
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
            # Update user subscription in database
            # You'd need to track which user made this payment
            logger.info(f"PayPal payment executed successfully: {paymentId}")
            return {"status": "success", "message": "Payment completed successfully"}
        else:
            logger.error(f"PayPal payment execution failed: {result.get('error')}")
            return {"status": "error", "message": "Payment execution failed"}
            
    except Exception as e:
        logger.error(f"Error in PayPal success callback: {str(e)}")
        raise HTTPException(status_code=500, detail="Payment processing failed")