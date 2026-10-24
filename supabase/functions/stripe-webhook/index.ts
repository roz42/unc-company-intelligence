import Stripe from "npm:stripe@17.7.0";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const stripe=new Stripe(Deno.env.get("STRIPE_SECRET_KEY")??"",{apiVersion:"2024-11-20.acacia"});
const cryptoProvider=Stripe.createSubtleCryptoProvider();
Deno.serve(async req=>{
  if(req.method!=="POST")return new Response("Method not allowed",{status:405});
  const signature=req.headers.get("stripe-signature"),secret=Deno.env.get("STRIPE_WEBHOOK_SECRET");if(!signature||!secret)return new Response("Webhook is not configured",{status:503});
  let event:Stripe.Event;try{event=await stripe.webhooks.constructEventAsync(await req.text(),signature,secret,undefined,cryptoProvider)}catch{ return new Response("Invalid signature",{status:400}) }
  const secretKeys=JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")??"{}");
  const serviceKey=secretKeys.default??Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const db=createClient(Deno.env.get("SUPABASE_URL")!,serviceKey);
  const sync=async(sub:Stripe.Subscription)=>{
    const orgId=sub.metadata.organization_id;const plan=sub.metadata.plan;
    if(!orgId||!(["starter","growth","enterprise"].includes(plan)))throw new Error("Subscription metadata is missing workspace or plan");
    const item=sub.items.data[0];const {error}=await db.from("subscriptions").upsert({organization_id:orgId,stripe_customer_id:String(sub.customer),stripe_subscription_id:sub.id,stripe_price_id:item?.price.id??null,plan,status:sub.status,current_period_end:sub.current_period_end?new Date(sub.current_period_end*1000).toISOString():null,updated_at:new Date().toISOString()},{onConflict:"organization_id"});if(error)throw error;
  };
  try{
    switch(event.type){
      case "checkout.session.completed":{const s=event.data.object as Stripe.Checkout.Session;if(s.subscription)await sync(await stripe.subscriptions.retrieve(String(s.subscription)));break}
      case "customer.subscription.created":case "customer.subscription.updated":await sync(event.data.object as Stripe.Subscription);break;
      case "customer.subscription.deleted":{const s=event.data.object as Stripe.Subscription;const {error}=await db.from("subscriptions").update({status:"canceled",updated_at:new Date().toISOString()}).eq("stripe_subscription_id",s.id);if(error)throw error;break}
      default:break;
    }
  }catch(e){console.error("Subscription sync failed",e);return new Response("Subscription sync failed",{status:500})}
  return new Response(JSON.stringify({received:true}),{headers:{"Content-Type":"application/json"}});
});
