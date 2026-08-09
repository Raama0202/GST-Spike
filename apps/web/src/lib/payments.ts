import { toast } from 'sonner';
import { api } from '../lib/api';

declare global {
  interface Window {
    Razorpay?: new (options: Record<string, unknown>) => { open: () => void };
  }
}

async function loadRazorpay() {
  if (window.Razorpay) return;
  await new Promise<void>((resolve, reject) => {
    const script = document.createElement('script');
    script.src = 'https://checkout.razorpay.com/v1/checkout.js';
    script.onload = () => resolve();
    script.onerror = () => reject(new Error('Failed to load Razorpay'));
    document.body.appendChild(script);
  });
}

export async function paySubscription(companyCode: string, plan: 'monthly' | 'yearly') {
  const order = await api.createPaymentOrder(companyCode, plan);

  if (order.simulated || !order.keyId) {
    const result = await api.verifyPayment({
      companyCode,
      plan,
      orderId: order.orderId,
      paymentId: `pay_sim_${Date.now()}`,
    });
    toast.success(result.simulated
      ? `Subscription activated (test mode — add Razorpay keys for live payments). Expires ${new Date(result.subscriptionExpiresAt).toLocaleDateString()}`
      : `Subscription activated until ${new Date(result.subscriptionExpiresAt).toLocaleDateString()}`);
    return result;
  }

  await loadRazorpay();
  return new Promise((resolve, reject) => {
    const rzp = new window.Razorpay!({
      key: order.keyId,
      amount: order.amount,
      currency: order.currency,
      name: 'GST Suite',
      description: `${plan} subscription — ${order.companyName}`,
      order_id: order.orderId,
      handler: async (response: { razorpay_order_id: string; razorpay_payment_id: string; razorpay_signature: string }) => {
        try {
          const result = await api.verifyPayment({
            companyCode,
            plan,
            orderId: response.razorpay_order_id,
            paymentId: response.razorpay_payment_id,
            signature: response.razorpay_signature,
          });
          toast.success(`Paid — active until ${new Date(result.subscriptionExpiresAt).toLocaleDateString()}`);
          resolve(result);
        } catch (error) {
          reject(error);
        }
      },
      modal: { ondismiss: () => reject(new Error('Payment cancelled')) },
    });
    rzp.open();
  });
}

export function formatPaise(paise: number) {
  return `₹${(paise / 100).toLocaleString('en-IN')}`;
}
