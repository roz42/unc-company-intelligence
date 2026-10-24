# Agent UNC session memory setup

Agent UNC keeps a conversation as one row in `public.conversations` and its ordered prompts and answers as rows in `public.messages`. Both tables are scoped to `organization_id`; the included row-level security policies permit workspace members to read their workspace's history. A trigger updates each conversation's activity time and keeps its title current from the first prompt. The app's session drawer can then list, search, reopen, and continue conversations.

## Apply the SQL

Because earlier attempts may have left a partial schema, use one clean reset query: open Supabase **SQL Editor → New query**, copy the entire `RESET_AND_SETUP.sql` file, and run it once. Do not also run the three individual migrations after it; the reset script already contains the complete setup.

**This reset drops and recreates only the UNC workspace tables. It deletes UNC organizations, memberships, sessions, company facts, subscription rows, data connections, and agent usage records in this project.** Run it only if you are okay starting those records over. It uses `DROP TABLE IF EXISTS`, so it can run whether the tables exist or not.

The individual migration files remain available for an existing installation where you need to preserve data. If the reset query itself errors, send the complete error and line number.

## Connect the app


1. The Project URL and publishable/anon key you supplied are already set in `config.js`. For a different Supabase project, replace those two public values there. Never put a service-role or secret key in the browser config.
2. Deploy the `agent-chat`, `create-checkout`, `stripe-webhook`, and `add-company-website` Edge Functions using `supabase functions deploy agent-chat`, `supabase functions deploy create-checkout`, `supabase functions deploy stripe-webhook`, and `supabase functions deploy add-company-website`.
3. In **Edge Function Secrets**, set `APP_ORIGIN` to the exact HTTPS origin where this app will be hosted, plus one model provider and its server-side API key. For Anthropic use `AI_PROVIDER=anthropic` and `ANTHROPIC_API_KEY`; for xAI use `AI_PROVIDER=xai` and `XAI_API_KEY`. Add the matching model override only if needed.
4. In **Authentication → URL Configuration**, set **Site URL** to the app origin and add that same origin to **Redirect URLs** (for local hosting, add `http://localhost:8000/**`). Confirm the Email provider is enabled. Open the app over HTTP(S), choose **Connect company**, and request the email sign-in link. `file://` is not a valid Supabase auth origin.

The browser only needs the Project URL and publishable/anon key. Keep Supabase secret keys and model provider keys in Supabase Edge Function Secrets. The local disconnected experience stores sessions in this browser's local storage; connected sessions are written to Supabase and available after signing in on another device.

## Stripe test checkout

1. In Stripe, enable **Test mode** and create recurring monthly prices in EUR for Starter (€29) and Growth (€79). Copy their `price_...` IDs.
2. In Supabase **Edge Function Secrets**, set `STRIPE_SECRET_KEY` to an `sk_test_...` key, `STRIPE_STARTER_PRICE_ID` and `STRIPE_GROWTH_PRICE_ID` to the matching test price IDs, and `APP_ORIGIN` to this site's HTTPS origin.
3. In Stripe Test mode, create a webhook for `https://YOUR_PROJECT_REF.supabase.co/functions/v1/stripe-webhook` and subscribe to `checkout.session.completed`, `customer.subscription.created`, `customer.subscription.updated`, and `customer.subscription.deleted`. Save the webhook's `whsec_...` value as `STRIPE_WEBHOOK_SECRET` in Supabase.
4. Sign in as a workspace owner/admin, select Starter or Growth, and verify Stripe Checkout opens. Use test card `4242 4242 4242 4242`, a future expiry, and any CVC. Test-mode prices require an `sk_test_...` secret key.

Enterprise is currently a sales-led plan. A webhook is needed to sync payment status back into the app after checkout.

## Add company knowledge

After applying migration `202610240003_company_profile.sql`, sign in and open **Data connections**. Save the company profile and use **Add website** to import text from the public homepage into `company_facts`. The page import covers one URL per action and does not crawl the whole site. Deploy `add-company-website` after every code update.

## Verify session memory


After signing in, send a message to Agent UNC. Open **History** to find the new conversation, select it to load its messages, then send a follow-up. For a database-side check, run:

```sql
select c.id, c.title, c.created_at, c.updated_at,
       count(m.id) as message_count
from public.conversations c
left join public.messages m on m.conversation_id = c.id
where c.organization_id = 'YOUR_ORGANIZATION_UUID'
group by c.id
order by c.updated_at desc;
```

Replace the organization UUID with the id created for your signed-in workspace. Do not disable row-level security to make the client queries work; the browser queries must remain subject to workspace membership policies.
