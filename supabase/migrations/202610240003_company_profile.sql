alter table public.organizations
  add column if not exists website text,
  add column if not exists industry text,
  add column if not exists description text;
