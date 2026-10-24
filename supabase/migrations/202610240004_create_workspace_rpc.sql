-- Create a workspace and its owner membership as one trusted transaction.
-- This repairs environments where the organization table exists but its owner trigger was not installed.
create or replace function public.create_workspace(
  p_name text,
  p_website text default null,
  p_industry text default null,
  p_description text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_organization_id uuid;
begin
  if v_user_id is null then
    raise exception 'Sign in required';
  end if;
  if nullif(trim(p_name), '') is null then
    raise exception 'Company name is required';
  end if;

  insert into public.organizations(name, created_by, website, industry, description)
  values (trim(p_name), v_user_id, nullif(trim(p_website), ''), nullif(trim(p_industry), ''), nullif(trim(p_description), ''))
  returning id into v_organization_id;

  insert into public.organization_members(organization_id, user_id, role)
  values (v_organization_id, v_user_id, 'owner')
  on conflict (organization_id, user_id) do nothing;

  return v_organization_id;
end;
$$;

revoke all on function public.create_workspace(text, text, text, text) from public;
grant execute on function public.create_workspace(text, text, text, text) to authenticated;
