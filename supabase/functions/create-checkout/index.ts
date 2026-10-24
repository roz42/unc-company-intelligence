import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const cors = { "Access-Control-Allow-Origin": Deno.env.get("APP_ORIGIN") ?? "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS", "Content-Type": "application/json" };
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:cors});
Deno.serve(async req=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method!=="POST")return json({error:"Method not allowed"},405);
  const auth=req.headers.get("Authorization");if(!auth)return json({error:"Sign in required"},401);
  const url=Deno.env.get("SUPABASE_URL")!,publishableKeys=JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")??"{}");
  const anon=publishableKeys.default??Deno.env.get("SUPABASE_ANON_KEY")!;
  const userDb=createClient(url,anon,{global:{headers:{Authorization:auth}}});
  const {data:{user}}=await userDb.auth.getUser();if(!user)return json({error:"Invalid session"},401);
  const {plan,organizationId}=await req.json().catch(()=>({}));
  if(!["starter","growth"].includes(plan)||!organizationId)return json({error:"Choose a paid plan and workspace"},400);
  const {data:member}=await userDb.from("organization_members").select("role").eq("organization_id",organizationId).eq("user_id",user.id).maybeSingle();
  if(!member||!(["owner","admin"].includes(member.role)))return json({error:"Workspace administrator access required"},403);
  // Price IDs are public catalog identifiers. Defaults make the configured UNC
  // sandbox plans work immediately; environment overrides support other Stripe accounts.
  const priceId=Deno.env.get(plan==="starter"?"STRIPE_STARTER_PRICE_ID":"STRIPE_GROWTH_PRICE_ID")
    ??(plan==="starter"?"price_1UU6X0Q48BaEBlrHOzgjohfq":"price_1UU6XHQ48BaEBlrHS9cZDaT9");
  const stripeKey=Deno.env.get("STRIPE_SECRET_KEY"),origin=(Deno.env.get("APP_ORIGIN")??"").replace(/\/+$/,"");if(!stripeKey||!origin)return json({error:"Billing secrets and APP_ORIGIN must be configured"},503);
  const {data:sub}=await userDb.from("subscriptions").select("stripe_customer_id").eq("organization_id",organizationId).maybeSingle();
  const form=new URLSearchParams();form.set("mode","subscription");form.set("line_items[0][price]",priceId);form.set("line_items[0][quantity]","1");form.set("success_url",`${origin}/?billing=success`);form.set("cancel_url",`${origin}/?billing=cancelled`);form.set("client_reference_id",organizationId);form.set("metadata[organization_id]",organizationId);form.set("metadata[plan]",plan);form.set("subscription_data[metadata][organization_id]",organizationId);form.set("subscription_data[metadata][plan]",plan);if(sub?.stripe_customer_id)form.set("customer",sub.stripe_customer_id);else form.set("customer_email",user.email??"");
  const response=await fetch("https://api.stripe.com/v1/checkout/sessions",{method:"POST",headers:{Authorization:`Bearer ${stripeKey}`,"Content-Type":"application/x-www-form-urlencoded"},body:form});
  const session=await response.json();if(!response.ok){console.error("Stripe checkout setup failed",session?.error?.type);return json({error:"Could not start secure checkout"},502)}
  return json({url:session.url});
});
