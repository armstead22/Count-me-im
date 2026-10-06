-- Count Me In: database setup for Supabase.
-- Paste this whole file into Supabase > SQL Editor > New query, then press Run.
-- It is safe to run more than once.
--
-- How it is protected: the table has row-level security switched on and NO
-- policies, so the public key in the web page cannot read or change it
-- directly. The page can only call the three functions below, and each one
-- needs a plan's id. Ids are long random strings, so knowing a plan's link is
-- what lets someone see and vote on that plan. Nobody can list plans.

create table if not exists public.cmi_plans (
  id          text primary key,
  data        jsonb       not null,
  rev         integer     not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.cmi_plans enable row level security;
revoke all on public.cmi_plans from anon, authenticated;

-- Start a new plan. Returns {id, rev, data}.
create or replace function public.cmi_create(p_title text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id     text;
  v_title  text;
  v_recent integer;
  v_data   jsonb;
begin
  -- A simple brake so a script cannot fill the table: 30 new plans a minute, site-wide.
  select count(*) into v_recent from cmi_plans where created_at > now() - interval '1 minute';
  if v_recent >= 30 then
    raise exception 'Lots of plans are being started right now. Try again in a minute.';
  end if;

  v_title := left(btrim(coalesce(p_title, '')), 60);
  if v_title = '' then v_title := 'Our plan'; end if;

  v_id := substr(replace(gen_random_uuid()::text, '-', ''), 1, 20);
  v_data := jsonb_build_object(
    'meta',   jsonb_build_object('title', v_title, 'locked', null,
                                 'createdAt', (extract(epoch from now()) * 1000)::bigint),
    'people', '{}'::jsonb, 'ideas', '{}'::jsonb, 'times', '{}'::jsonb, 'votes', '{}'::jsonb);

  insert into cmi_plans (id, data) values (v_id, v_data);
  return jsonb_build_object('id', v_id, 'rev', 0, 'data', v_data);
end;
$$;

-- Read a plan. Pass the revision you already have to get a tiny answer when nothing changed.
-- Returns null when the plan does not exist.
create or replace function public.cmi_get(p_id text, p_rev integer default -1)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case when rev = p_rev then jsonb_build_object('rev', rev)
              else jsonb_build_object('rev', rev, 'data', data) end
  from cmi_plans
  where id = p_id;
$$;

-- Change one piece of a plan. p_path is ['meta'] or [collection, item id].
-- A null p_value removes the item. Returns {rev, data} after the change.
-- Each call is one atomic update, so two friends voting at the same moment both count.
create or replace function public.cmi_write(p_id text, p_path text[], p_value jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_len  integer := coalesce(array_length(p_path, 1), 0);
  v_rev  integer;
  v_data jsonb;
begin
  if v_len = 1 and p_path[1] = 'meta' then
    if p_value is null or jsonb_typeof(p_value) <> 'object' then
      raise exception 'That change is not allowed.';
    end if;
  elsif v_len = 2 and p_path[1] in ('people', 'ideas', 'times', 'votes') then
    if p_path[2] !~ '^[a-z0-9]{1,40}$' then
      raise exception 'That change is not allowed.';
    end if;
    if p_value is not null and jsonb_typeof(p_value) <> 'object' then
      raise exception 'That change is not allowed.';
    end if;
  else
    raise exception 'That change is not allowed.';
  end if;

  if p_value is not null and octet_length(p_value::text) > 4000 then
    raise exception 'That is too long to save.';
  end if;

  update cmi_plans
     set data = case when p_value is null then data #- p_path
                     else jsonb_set(data, p_path, p_value, true) end,
         rev = rev + 1,
         updated_at = now()
   where id = p_id
  returning rev, data into v_rev, v_data;

  if not found then
    raise exception 'This plan no longer exists.';
  end if;

  -- Limits. Raising here undoes the update above.
  if v_len = 2 and (select count(*) from jsonb_object_keys(v_data -> p_path[1])) > 60 then
    raise exception 'This plan is full. Remove something before adding more.';
  end if;
  if octet_length(v_data::text) > 64000 then
    raise exception 'This plan is full. Remove something before adding more.';
  end if;

  return jsonb_build_object('rev', v_rev, 'data', v_data);
end;
$$;

revoke all on function public.cmi_create(text)                from public;
revoke all on function public.cmi_get(text, integer)          from public;
revoke all on function public.cmi_write(text, text[], jsonb)  from public;
grant execute on function public.cmi_create(text)               to anon, authenticated;
grant execute on function public.cmi_get(text, integer)         to anon, authenticated;
grant execute on function public.cmi_write(text, text[], jsonb) to anon, authenticated;

-- Tell the API layer about the new functions straight away.
notify pgrst, 'reload schema';
