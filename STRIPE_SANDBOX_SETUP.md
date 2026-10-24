# Stripe sandbox checkout setup

This app already creates Stripe Checkout Sessions from the Supabase Edge Function `create-checkout`. The Stripe secret stays server-side. The `stripe-webhook` function verifies Stripe's signature and writes the resulting plan/status to `public.subscriptions`. You only need to configure test prices and secrets, deploy those two functions, and add the webhook endpoint.

## 1. Create test prices in Stripe

1. Open the Stripe Dashboard and switch **Test mode** on.
2. Go to **Product catalog → Add product**. Create **UNC Starter** and add a recurring price of **€29 EUR / month**.
3. Create **UNC Growth** with a recurring price of **€79 EUR / month**.
4. Open each price and copy its **Price ID** (starts with `price_`, not the Product ID).
5. In **Developers → API keys**, copy the test **Secret key** (starts with `sk_test_`). Do not share it in chat or put it in the website files.

## 2. Choose the app origin

The current `file://` preview cannot be used for authenticated checkout. Serve the folder over HTTP or use your hosted HTTPS site.

For local testing, open Terminal and run:

```sh
cd "/Users/robertzirk/Documents/Codex/2026-10-24/re/outputs/lage"
python3 -m http.server 8000
```

Then open **http://localhost:8000/**. Use `http://localhost:8000` as `APP_ORIGIN` below (no trailing slash). If testing on a hosted site, use that exact HTTPS origin instead. The browser origin, `APP_ORIGIN`, and checkout return origin must match.

## 3. Save the secrets in Supabase

Open the Supabase project **vlxgfbdczpktuvxxrdqs → Edge Functions → Secrets** and add these values:

| Name | Value |
| --- | --- |
| `STRIPE_SECRET_KEY` | Stripe test secret starting `sk_test_` |
| `STRIPE_STARTER_PRICE_ID` | Starter monthly test Price ID starting `price_` |
| `STRIPE_GROWTH_PRICE_ID` | Growth monthly test Price ID starting `price_` |
| `APP_ORIGIN` | `http://localhost:8000` or the hosted site origin |

Do not put any of these values in `config.js`. You do not need to send them to me. Confirm the database setup has `public.organizations`, `public.organization_members`, and `public.subscriptions`; the first two are needed for workspace authorization and the last stores the Stripe status.

## 4. Deploy the checkout and webhook functions

Install the [Supabase CLI](https://supabase.com/docs/guides/cli) if it is not already installed, then run these commands in Terminal:

```sh
cd "/Users/robertzirk/Documents/Codex/2026-10-24/re/outputs/lage"
supabase login
supabase link --project-ref vlxgfbdczpktuvxxrdqs
supabase functions deploy create-checkout
supabase functions deploy stripe-webhook
```

Linking may ask for the database password; it is available in the Supabase project settings. The functions read their secrets directly from Supabase, so there are no secret files to create or commit.

## 5. Register the Stripe webhook

1. In Stripe **Test mode**, go to **Developers → Webhooks → Add endpoint**.
2. Set the endpoint URL to:
   ```text
   https://vlxgfbdczpktuvxxrdqs.supabase.co/functions/v1/stripe-webhook
   ```
3. Select these events: `checkout.session.completed`, `customer.subscription.created`, `customer.subscription.updated`, and `customer.subscription.deleted`.
4. Reveal and copy the endpoint signing secret (starts with `whsec_`). Add it in Supabase Edge Function Secrets as `STRIPE_WEBHOOK_SECRET`.

## 6. Allow local sign-in and try checkout

In Supabase **Authentication → URL Configuration**, add `http://localhost:8000/**` to **Redirect URLs**. Keep your production Site URL if one is already configured. Open the app from localhost, request a sign-in link, and sign in as a workspace owner/admin. Open **Subscription**, choose Starter or Growth, and confirm Stripe Checkout opens.

Use Stripe's interactive test card `4242 4242 4242 4242`, any future expiry (for example `12/34`), any 3-digit CVC, and any name. Stripe confirms the checkout return; the webhook then syncs the plan into Supabase. Verify in the Supabase SQL Editor:

```sql
select organization_id, plan, status, stripe_customer_id,
       stripe_subscription_id, current_period_end
from public.subscriptions;
```

## If checkout does not open

- **“Connect your workspace and sign in”**: open the app through localhost/HTTPS, sign in, and save the company profile to create the organization.
- **“That plan is not configured yet”**: check the corresponding `STRIPE_*_PRICE_ID` secret and deploy `create-checkout`.
- **“Billing secrets and APP_ORIGIN must be configured”**: check all four secrets in step 3; `APP_ORIGIN` must be the exact origin with no trailing slash.
- **CORS error**: the URL you opened does not match `APP_ORIGIN`. Use `http://localhost:8000` consistently or update the secret to the hosted origin.
- Checkout succeeds but the plan does not update: verify the webhook endpoint is in Test mode, the `STRIPE_WEBHOOK_SECRET` belongs to that endpoint, and the four events are selected. Check the endpoint's delivery log in Stripe.

For Stripe's current test-card behavior, see [Stripe test cards](https://docs.stripe.com/testing?numbers-or-method-or-token=tokens). For Supabase function deployment and secrets, see [Deploy Edge Functions](https://supabase.com/docs/guides/functions/deploy) and [Edge Function secrets](https://supabase.com/docs/guides/functions/secrets).
