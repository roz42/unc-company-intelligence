-- UNC workspace reset and full setup.
-- This intentionally deletes data from the UNC workspace tables listed below.
-- Use only if you are okay resetting all UNC workspaces, sessions, company facts,
-- subscriptions, and usage records in this Supabase project.
begin;

drop table if exists public.agent_usage cascade;
drop table if exists public.plan_entitlements cascade;
drop table if exists public.data_connections cascade;
drop table if exists public.subscriptions cascade;
drop table if exists public.messages cascade;
drop table if exists public.conversations cascade;
drop table if exists public.company_facts cascade;
drop table if exists public.organization_members cascade;
drop table if exists public.organizations cascade;

create extension if not exists pgcrypto;

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);
create table if not exists public.organization_members (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','admin','member','viewer')),
  created_at timestamptz not null default now(),
  primary key (organization_id,user_id)
);
create table if not exists public.company_facts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  source text not null,
  fact_key text not null,
  fact_value jsonb not null,
  observed_at timestamptz not null default now(),
  unique (organization_id,source,fact_key)
);
create index if not exists company_facts_org_observed on public.company_facts(organization_id, observed_at desc);
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete restrict,
  title text not null default 'New conversation',
  created_at timestamptz not null default now()
);
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  role text not null check (role in ('user','assistant')),
  content text not null,
  model text,
  created_at timestamptz not null default now()
);
-- CREATE TABLE IF NOT EXISTS does not add columns to an older table. Ensure
-- the conversation link exists if a prior/legacy messages table was present.
alter table public.messages
  add column if not exists conversation_id uuid references public.conversations(id) on delete cascade;
create index if not exists messages_conversation_created on public.messages(conversation_id,created_at);
create table if not exists public.subscriptions (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  stripe_customer_id text unique,
  stripe_subscription_id text unique,
  stripe_price_id text,
  plan text not null default 'starter' check (plan in ('starter','growth','enterprise')),
  status text not null default 'trialing',
  current_period_end timestamptz,
  updated_at timestamptz not null default now()
);
create table if not exists public.data_connections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider text not null,
  status text not null default 'pending',
  credentials_ref text,
  last_synced_at timestamptz,
  created_at timestamptz not null default now(),
  unique(organization_id,provider)
);

create or replace function public.is_org_member(org_id uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.organization_members m where m.organization_id=org_id and m.user_id=auth.uid()) $$;
create or replace function public.is_org_admin(org_id uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.organization_members m where m.organization_id=org_id and m.user_id=auth.uid() and m.role in ('owner','admin')) $$;
create or replace function public.add_organization_creator()
returns trigger language plpgsql security definer set search_path=public
as $$ begin insert into public.organization_members(organization_id,user_id,role) values(new.id,new.created_by,'owner'); return new; end $$;
drop trigger if exists organization_owner_membership on public.organizations;
create trigger organization_owner_membership after insert on public.organizations for each row execute function public.add_organization_creator();
revoke all on function public.is_org_member(uuid) from public;
revoke all on function public.is_org_admin(uuid) from public;
grant execute on function public.is_org_member(uuid) to authenticated;
grant execute on function public.is_org_admin(uuid) to authenticated;

alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.company_facts enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.subscriptions enable row level security;
alter table public.data_connections enable row level security;
drop policy if exists "members read organizations" on public.organizations;
create policy "members read organizations" on public.organizations for select to authenticated using (public.is_org_member(id));
drop policy if exists "users create organization" on public.organizations;
create policy "users create organization" on public.organizations for insert to authenticated with check (created_by=auth.uid());
drop policy if exists "admins update organization" on public.organizations;
create policy "admins update organization" on public.organizations for update to authenticated using (public.is_org_admin(id)) with check (public.is_org_admin(id));
drop policy if exists "members read memberships" on public.organization_members;
create policy "members read memberships" on public.organization_members for select to authenticated using (public.is_org_member(organization_id));
drop policy if exists "admins manage memberships" on public.organization_members;
create policy "admins manage memberships" on public.organization_members for all to authenticated using (public.is_org_admin(organization_id)) with check (public.is_org_admin(organization_id));
drop policy if exists "members read facts" on public.company_facts;
create policy "members read facts" on public.company_facts for select to authenticated using (public.is_org_member(organization_id));
drop policy if exists "admins manage facts" on public.company_facts;
create policy "admins manage facts" on public.company_facts for all to authenticated using (public.is_org_admin(organization_id)) with check (public.is_org_admin(organization_id));
drop policy if exists "members read conversations" on public.conversations;
create policy "members read conversations" on public.conversations for select to authenticated using (public.is_org_member(organization_id));
drop policy if exists "members create conversations" on public.conversations;
create policy "members create conversations" on public.conversations for insert to authenticated with check (public.is_org_member(organization_id) and created_by=auth.uid());
drop policy if exists "members read messages" on public.messages;
create policy "members read messages" on public.messages for select to authenticated using (exists(select 1 from public.conversations c where c.id=messages.conversation_id and public.is_org_member(c.organization_id)));
drop policy if exists "members create messages" on public.messages;
create policy "members create messages" on public.messages for insert to authenticated with check (messages.role='user' and exists(select 1 from public.conversations c where c.id=messages.conversation_id and public.is_org_member(c.organization_id)));
drop policy if exists "members read subscription" on public.subscriptions;
create policy "members read subscription" on public.subscriptions for select to authenticated using (public.is_org_member(organization_id));
drop policy if exists "members read connections" on public.data_connections;
create policy "members read connections" on public.data_connections for select to authenticated using (public.is_org_member(organization_id));
drop policy if exists "admins manage connections" on public.data_connections;
create policy "admins manage connections" on public.data_connections for all to authenticated using (public.is_org_admin(organization_id)) with check (public.is_org_admin(organization_id));

create table if not exists public.plan_entitlements (
  plan text primary key check (plan in ('starter','growth','enterprise')),
  max_members integer,
  max_connections integer,
  monthly_agent_requests integer
);
insert into public.plan_entitlements(plan,max_members,max_connections,monthly_agent_requests) values
  ('starter',3,3,500),('growth',25,null,5000),('enterprise',null,null,null)
on conflict(plan) do update set max_members=excluded.max_members,max_connections=excluded.max_connections,monthly_agent_requests=excluded.monthly_agent_requests;
create table if not exists public.agent_usage (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete restrict,
  conversation_id uuid references public.conversations(id) on delete set null,
  model text not null,
  created_at timestamptz not null default now()
);
create index if not exists agent_usage_month on public.agent_usage(organization_id,created_at desc);
alter table public.plan_entitlements enable row level security;
alter table public.agent_usage enable row level security;
drop policy if exists "authenticated read plan entitlements" on public.plan_entitlements;
create policy "authenticated read plan entitlements" on public.plan_entitlements for select to authenticated using (true);
drop policy if exists "members read usage" on public.agent_usage;
create policy "members read usage" on public.agent_usage for select to authenticated using (public.is_org_member(organization_id));

create or replace function public.enforce_workspace_limits()
returns trigger language plpgsql security definer set search_path=public
as $$
declare org_id uuid; plan_name text; max_allowed integer; current_count integer;
begin
  org_id := new.organization_id;
  perform pg_advisory_xact_lock(hashtextextended(org_id::text,0));
  select coalesce(s.plan,'starter') into plan_name from (select 1) seed left join public.subscriptions s on s.organization_id=org_id;
  if tg_table_name='organization_members' then
    select max_members into max_allowed from public.plan_entitlements where plan=plan_name;
    if max_allowed is not null and not exists(select 1 from public.organization_members where organization_id=org_id and user_id=new.user_id) then
      select count(*) into current_count from public.organization_members where organization_id=org_id;
      if current_count >= max_allowed then raise exception 'Workspace member limit reached for the % plan', plan_name using errcode='P0001'; end if;
    end if;
  elsif tg_table_name='data_connections' then
    select max_connections into max_allowed from public.plan_entitlements where plan=plan_name;
    if max_allowed is not null and not exists(select 1 from public.data_connections where organization_id=org_id and provider=new.provider) then
      select count(*) into current_count from public.data_connections where organization_id=org_id;
      if current_count >= max_allowed then raise exception 'Data connection limit reached for the % plan', plan_name using errcode='P0001'; end if;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists enforce_member_limit on public.organization_members;
create trigger enforce_member_limit before insert on public.organization_members for each row execute function public.enforce_workspace_limits();
drop trigger if exists enforce_connection_limit on public.data_connections;
create trigger enforce_connection_limit before insert on public.data_connections for each row execute function public.enforce_workspace_limits();

create or replace function public.reserve_agent_request(p_organization_id uuid,p_user_id uuid,p_conversation_id uuid,p_model text)
returns boolean language plpgsql security definer set search_path=public set row_security=off
as $$
declare plan_name text; plan_status text; max_requests integer; used integer;
begin
  perform 1 from public.organizations where id=p_organization_id for update;
  if not found then return false; end if;
  select coalesce(s.plan,'starter'),coalesce(s.status,'trialing') into plan_name,plan_status from (select 1) seed left join public.subscriptions s on s.organization_id=p_organization_id;
  if plan_status not in ('active','trialing') then return false; end if;
  select monthly_agent_requests into max_requests from public.plan_entitlements where plan=plan_name;
  if max_requests is not null then
    select count(*) into used from public.agent_usage where organization_id=p_organization_id and created_at>=date_trunc('month',now());
    if used>=max_requests then return false; end if;
  end if;
  insert into public.agent_usage(organization_id,user_id,conversation_id,model) values(p_organization_id,p_user_id,p_conversation_id,p_model);
  return true;
end $$;
revoke all on function public.reserve_agent_request(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.reserve_agent_request(uuid,uuid,uuid,text) to service_role;

-- Session history: sort conversations by recent activity and title them from
-- their first user prompt. Existing organization-scoped RLS stays in place.
alter table public.conversations
  add column if not exists updated_at timestamptz not null default now();

create index if not exists conversations_org_updated
  on public.conversations (organization_id, updated_at desc);

create or replace function public.touch_conversation_from_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.conversations
     set updated_at = now(),
         title = case
           when title = 'New conversation' and new.role = 'user'
             then left(new.content, 80)
           else title
         end
   where id = new.conversation_id;
  return new;
end;
$$;

drop trigger if exists messages_touch_conversation on public.messages;
create trigger messages_touch_conversation
after insert on public.messages
for each row execute function public.touch_conversation_from_message();

revoke all on function public.touch_conversation_from_message() from public, anon, authenticated;

alter table public.organizations
  add column if not exists website text,
  add column if not exists industry text,
  add column if not exists description text;

commit;
