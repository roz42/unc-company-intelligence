# UNC — Company Intelligence

UNC's agent-led company operations workspace, based on the original `lage` repository structure: the left navigation rail, eight-tile overview, and a persistent Agent UNC panel on the right. The middle workspace changes with sidebar navigation. It includes performance charts, priority signals, finance, revenue, team, operations, integrations, and three subscription tiers.

## Open the workspace

Open `index.html` in a browser. Without Supabase configuration, Agent UNC responds from the included sample workspace context and stores conversation history in that browser. To persist sessions across devices and use a model provider, configure Supabase and deploy the Edge Function as described below.

## Session history and Supabase

The workspace stores connected conversations and messages in Supabase, scoped to each organization with row-level security. The History drawer can search, reopen, and continue saved conversations. The browser-only version stores sessions in local storage on that device.

Follow [`supabase/SESSION_MEMORY_SETUP.md`](supabase/SESSION_MEMORY_SETUP.md) to run the SQL migrations in Supabase SQL Editor, configure Auth, add the public client settings to `config.js`, and deploy the `agent-chat` Edge Function. The SQL files are also applied with `supabase link --project-ref YOUR_PROJECT_REF` and `supabase db push` from this folder.

For live company context, add records to `company_facts` through a trusted ingestion path. The agent can only answer from data connected to its workspace; the sample connectors in the interface need provider-specific OAuth, sync jobs, and ingestion code before they can import company records.

## AI provider

Choose Anthropic or xAI for the server-side `agent-chat` function. Store provider keys as Supabase Edge Function Secrets, never in the browser. Set `AI_PROVIDER=anthropic` with `ANTHROPIC_API_KEY`, or `AI_PROVIDER=xai` with `XAI_API_KEY`. The client sends the prompt to the Supabase function, which loads organization facts and recent conversation messages before calling the selected model.

For a complete guided sandbox setup (test prices, Supabase secrets, deployment, webhook, and verification), see [STRIPE_SANDBOX_SETUP.md](STRIPE_SANDBOX_SETUP.md).

## Stripe test subscriptions

Starter and Growth use Stripe Checkout in subscription mode. The browser sends a signed-in workspace administrator to the `create-checkout` Supabase Edge Function, which creates a Checkout Session from Stripe price IDs. The Stripe secret key stays in Supabase. Stripe test mode is selected by using an `sk_test_...` key and test-mode recurring prices.

1. In Stripe, turn on **Test mode**. Create recurring monthly EUR prices for Starter (€29) and Growth (€79), then copy each `price_...` ID from the test catalog.
2. Set Supabase Edge Function secrets (never `config.js`): `STRIPE_SECRET_KEY=sk_test_...`, `STRIPE_STARTER_PRICE_ID=price_...`, `STRIPE_GROWTH_PRICE_ID=price_...`, and `APP_ORIGIN=https://your-hosted-site.example`.
3. Deploy the functions from `outputs/lage`: `supabase functions deploy create-checkout`, `supabase functions deploy stripe-webhook`, and `supabase functions deploy add-company-website`.
4. In Stripe Test mode, add a webhook endpoint `https://YOUR_PROJECT_REF.supabase.co/functions/v1/stripe-webhook`, subscribe to `checkout.session.completed`, `customer.subscription.created`, `customer.subscription.updated`, and `customer.subscription.deleted`, then add the endpoint signing secret as `STRIPE_WEBHOOK_SECRET=whsec_...` in Supabase.
5. Sign in to UNC as a workspace owner or admin, open **Subscription**, and select Starter or Growth. Stripe Checkout should open. Use Stripe's standard test card `4242 4242 4242 4242`, any future expiry, and any CVC.

The webhook stores the resulting subscription status in `public.subscriptions`. Enterprise remains a sales-led plan. Stripe keys and price IDs must all come from the same Stripe mode; test price IDs will not work with a live key.

## Company profile and website knowledge

Run `supabase/migrations/202610240003_company_profile.sql` in Supabase SQL Editor after the two workspace/session migrations. In the app, choose **Connect company** to open the company setup page and request a Supabase email sign-in link. Save the profile fields there to create the workspace, or choose **Load UNC example** to seed the sample company profile and operating figures. The agent answers locally from this UNC example before sign-in; once signed in, it can use the saved Supabase company facts and the configured AI function. **Add website** imports the public homepage text into that workspace's `company_facts`; Agent UNC includes the saved profile and facts in its company context. Website import is a first-page starter source, not a full crawl or a sync integration. The function checks for public HTTP(S) URLs and does not follow redirects.

## Credentials and setup

The browser config needs only the Supabase Project URL and publishable key (or legacy anon key). Do not put service-role keys, Stripe secrets, or model keys in `config.js`. Add the deployed HTTPS origin to Supabase Auth redirect URLs and set `APP_ORIGIN` for the functions. A variable-name template is provided in `.env.example`; it contains no credentials.
