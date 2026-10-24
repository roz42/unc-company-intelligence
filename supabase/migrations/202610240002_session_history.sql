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
