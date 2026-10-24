import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const cors = { "Access-Control-Allow-Origin": Deno.env.get("APP_ORIGIN") ?? "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS", "Content-Type": "application/json" };
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:cors});
Deno.serve(async req=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method!=="POST")return json({error:"Method not allowed"},405);
  const authorization=req.headers.get("Authorization");if(!authorization)return json({error:"Sign in required"},401);
  const url=Deno.env.get("SUPABASE_URL")!,keys=JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")??"{}");
  const userDb=createClient(url,keys.default??Deno.env.get("SUPABASE_ANON_KEY")!,{global:{headers:{Authorization:authorization}}});
  const {data:{user}}=await userDb.auth.getUser();if(!user)return json({error:"Invalid session"},401);
  const {organizationId,website}=await req.json().catch(()=>({}));
  if(typeof organizationId!=="string"||typeof website!=="string")return json({error:"Workspace and website are required"},400);
  let target:URL;try{target=new URL(website.startsWith("http")?website:`https://${website}`)}catch{return json({error:"Enter a valid website URL"},400)}
  if(!["http:","https:"].includes(target.protocol)||target.username||target.password||target.hostname==="localhost"||/^127\.|^10\.|^192\.168\.|^169\.254\.|^172\.(1[6-9]|2\d|3[01])\./.test(target.hostname))return json({error:"Enter a public http or https website"},400);
  const {data:member}=await userDb.from("organization_members").select("role").eq("organization_id",organizationId).eq("user_id",user.id).maybeSingle();
  if(!member||!["owner","admin"].includes(member.role))return json({error:"Workspace administrator access required"},403);
  let response:Response;try{response=await fetch(target,{redirect:"error",headers:{"User-Agent":"UNC-Company-Knowledge/1.0","Accept":"text/html,text/plain"},signal:AbortSignal.timeout(12000)})}catch{return json({error:"Could not read that public website. Check the URL and try again."},422)}
  if(!response.ok)return json({error:`Website returned HTTP ${response.status}`},422);
  const type=response.headers.get("content-type")??"";if(!type.includes("text/html")&&!type.includes("text/plain"))return json({error:"That URL did not return a readable web page"},422);
  const raw=(await response.text()).slice(0,1_000_000);
  const text=raw.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi," ").replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi," ").replace(/<noscript\b[^>]*>[\s\S]*?<\/noscript>/gi," ").replace(/<[^>]+>/g," ").replace(/&nbsp;/gi," ").replace(/&amp;/gi,"&").replace(/&quot;/gi,'"').replace(/&#39;|&apos;/gi,"'").replace(/&lt;/gi,"<").replace(/&gt;/gi,">").replace(/\s+/g," ").trim().slice(0,16000);
  if(text.length<80)return json({error:"The page did not contain enough readable text"},422);
  const secrets=JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")??"{}");const service=createClient(url,secrets.default??Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const {error}=await service.from("company_facts").upsert({organization_id:organizationId,source:"website",fact_key:target.toString(),fact_value:{url:target.toString(),title:raw.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1]?.replace(/<[^>]+>/g,"").trim()??target.hostname,content:text},observed_at:new Date().toISOString()},{onConflict:"organization_id,source,fact_key"});
  if(error){console.error("Website knowledge insert failed",error.code);return json({error:"Could not save website content to company knowledge"},500)}
  return json({url:target.toString(),characters:text.length});
});
