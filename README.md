# UNC — Company Intelligence

UNC's agent-led company operations workspace, based on the original `lage` repository structure: the left navigation rail, eight-tile overview, and a persistent Agent UNC panel on the right. The middle workspace changes with sidebar navigation. It includes performance charts, priority signals, finance, revenue, team, operations, integrations, and three subscription tiers.

## Open the workspace

The app is a static site and can be served from GitHub Pages. A Pages workflow is included under `.github/workflows/deploy-pages.yml`. Enable Pages with **Settings → Pages → Build and deployment → GitHub Actions**; pushes to `main` then publish the site. Supabase handles authentication and private company data, and Supabase Edge Functions handle AI and Stripe server requests.

## Session history and Supabase

The workspace stores connected conversations and messages in Supabase, scoped to each organization with row-level security. The History drawer can search, reopen, and continue saved conversations. The browser-only version stores sessions in local storage on that device.

Follow [`supabase/SESSION_MEMORY_SETUP.md`](supabase/SESSION_MEMORY_SETUP.md) to run the SQL migrations in Supabase SQL Editor, configure Auth, add the public client settings to `config.js`, and deploy the `agent-chat` Edge Function. The SQL files are also applied with `supabase link --project-ref YOUR_PROJECT_REF` and `supabase db push` from this folder.

For live company context, add records to `company_facts` through a trusted ingestion path. The agent can only answer from data connected to its workspace; the sample connectors in the interface need provider-specific OAuth, sync jobs, and ingestion code before they can import company records.

## AI provider

Choose Anthropic or xAI for the server-side `agent-chat` function. Store provider keys as Supabase Edge Function Secrets, never in the browser. Set `AI_PROVIDER=anthropic` with `ANTHROPIC_API_KEY`, or `AI_PROVIDER=xai` with `XAI_API_KEY`. The client sends the prompt to the Supabase function, which loads organization facts and recent conversation messages before calling the selected model.

For a complete guided sandbox setup (test prices, Supabase secrets, deployment, webhook, and verification), see [STRIPE_SANDBOX_SETUP.md](STRIPE_SANDBOX_SETUP.md).

## Stripe test subscriptions

Starter and Growth use Stripe Checkout in subscription mode. The browser sends a signed-in workspace administrator to the `create-checkout` Supabase Edge Function, which creates a Checkout Session from Stripe price IDs. The Stripe secret key stays in Supabase. Stripe test mode is selected by using an `sk_test_...` key and test-mode recurring prices.

1. In Stripe, turn on **Test mode**. Starter uses `price_1UU6X0Q48BaEBlrHOzgjohfq`; Growth uses `price_1UU6XHQ48BaEBlrHS9cZDaT9`.
2. Set Supabase Edge Function secrets (never `config.js`): `STRIPE_SECRET_KEY=sk_test_...` and `APP_ORIGIN=https://roz42.github.io/unc-company-intelligence` for GitHub Pages. For local development, use `http://localhost:8000`. The checkout function uses the base path for Stripe return URLs and reduces it to the origin for CORS. The Price IDs are already configured as non-secret defaults in the checkout function.
3. Deploy the functions from `outputs/lage`: `supabase functions deploy create-checkout`, `supabase functions deploy stripe-webhook`, and `supabase functions deploy add-company-website`.
4. In Stripe Test mode, add a webhook endpoint `https://YOUR_PROJECT_REF.supabase.co/functions/v1/stripe-webhook`, subscribe to `checkout.session.completed`, `customer.subscription.created`, `customer.subscription.updated`, and `customer.subscription.deleted`, then add the endpoint signing secret as `STRIPE_WEBHOOK_SECRET=whsec_...` in Supabase.
5. Sign in or create an account in UNC, save the company profile once to create a workspace, then open **Subscription** and select Starter or Growth. If a user clicks a plan before sign-in or workspace setup, UNC remembers the selected plan and resumes Checkout after setup. Stripe Checkout should open. Use Stripe's standard test card `4242 4242 4242 4242`, any future expiry, and any CVC.

The webhook stores the resulting subscription status in `public.subscriptions`. Enterprise remains a sales-led plan. Stripe keys and price IDs must all come from the same Stripe mode; test price IDs will not work with a live key.

## Company profile and website knowledge

Apply all three SQL files in `supabase/migrations/` in timestamp order in Supabase SQL Editor. Add `https://roz42.github.io/unc-company-intelligence/` to Authentication → URL Configuration → Redirect URLs. For Google OAuth, enable the Google provider in Supabase Auth and configure its OAuth client ID/secret; email sign-in links work without Google setup. In the app, choose **Sign in / Sign up** to continue with Google or request a Supabase email link. Save the profile fields there to create the workspace, or choose **Load UNC example** to seed the sample company profile and operating figures. The agent answers locally from this UNC example before sign-in; once signed in, it can use the saved Supabase company facts and the configured AI function. **Add website** imports the public homepage text into that workspace's `company_facts`; Agent UNC includes the saved profile and facts in its company context. Website import is a first-page starter source, not a full crawl or a sync integration. The function checks for public HTTP(S) URLs and does not follow redirects.

## Credentials and setup

The browser config needs only the Supabase Project URL and publishable key (or legacy anon key). Do not put service-role keys, Stripe secrets, or model keys in `config.js`. Add the full GitHub Pages URL `https://roz42.github.io/unc-company-intelligence/` to Supabase Auth redirect URLs, and set `APP_ORIGIN` to the full GitHub Pages base URL in Supabase Edge Function Secrets. The local redirect `http://localhost:8000/**` can remain for development. A variable-name template is provided in `.env.example`; it contains no credentials.
