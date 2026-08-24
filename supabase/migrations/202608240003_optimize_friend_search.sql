alter table public.profiles
  drop constraint if exists profiles_display_name_length;

alter table public.profiles
  add constraint profiles_display_name_length check (
    not onboarding_completed
    or char_length(btrim(display_name)) between 2 and 30
  ) not valid;

do $$
begin
  if not exists (
    select 1
    from public.profiles profile
    where profile.onboarding_completed
      and char_length(btrim(profile.display_name)) not between 2 and 30
  ) then
    alter table public.profiles
      validate constraint profiles_display_name_length;
  end if;
end;
$$;

create table private.profile_friend_counts (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  friends_count integer not null default 0 check (friends_count >= 0)
);

revoke all on private.profile_friend_counts from public, anon, authenticated;
grant select, insert, update, delete on private.profile_friend_counts
to service_role;

insert into private.profile_friend_counts (user_id, friends_count)
select
  profile.id,
  count(friendship.id)::integer
from public.profiles profile
left join public.friendships friendship
  on friendship.user_one_id = profile.id
  or friendship.user_two_id = profile.id
group by profile.id;

create or replace function private.update_profile_friends_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into private.profile_friend_counts as profile_count (
      user_id,
      friends_count
    )
    values (new.user_one_id, 1), (new.user_two_id, 1)
    on conflict (user_id) do update
    set friends_count = profile_count.friends_count + 1;
    return new;
  end if;

  update private.profile_friend_counts profile_count
  set friends_count = greatest(profile_count.friends_count - 1, 0)
  where profile_count.user_id in (old.user_one_id, old.user_two_id);
  return old;
end;
$$;

revoke all on function private.update_profile_friends_count()
from public, anon, authenticated;

create trigger friendships_update_profile_counts
after insert or delete on public.friendships
for each row execute function private.update_profile_friends_count();

create or replace function private.display_name_prefix_query(search_text text)
returns tsquery
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select to_tsquery(
    'simple'::regconfig,
    string_agg(quote_literal(token.value) || ':*', ' & ' order by token.position)
  )
  from regexp_split_to_table(
    lower(btrim(search_text)),
    '[^[:alnum:]_]+'
  ) with ordinality as token(value, position)
  where token.value <> '';
$$;

revoke all on function private.display_name_prefix_query(text)
from public, anon, authenticated;

create index profiles_display_name_prefix_search_idx
on public.profiles using gin (
  to_tsvector('simple'::regconfig, display_name)
)
where onboarding_completed;

drop function public.search_friend_candidates(text, integer);
drop function private.search_friend_candidates_impl(text, integer);

create function private.search_friend_candidates_impl(
  search_query text,
  result_limit integer default 10
)
returns table (
  id uuid,
  request_id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  friend_count bigint,
  relationship text
)
language sql
stable
security definer
set search_path = ''
as $$
  with normalized as (
    select lower(btrim(coalesce(search_query, ''))) as query
  ),
  prepared as (
    select
      normalized.query,
      left(normalized.query, 1) = '@' as is_username_search,
      case
        when left(normalized.query, 1) = '@'
          then substr(normalized.query, 2)
        else normalized.query
      end as search_value
    from normalized
  )
  select
    profile.id,
    request.id,
    profile.username,
    profile.display_name,
    profile.avatar_url,
    profile.avatar_storage_path,
    case
      when profile.show_friends_count or profile.id = auth.uid()
        then coalesce(profile_count.friends_count, 0)::bigint
      else null
    end,
    case
      when request.sender_id = auth.uid() then 'outgoing'
      when request.recipient_id = auth.uid() then 'incoming'
      else 'none'
    end
  from prepared
  join public.profiles profile
    on profile.id <> auth.uid()
   and profile.onboarding_completed
   and (
     (
       prepared.is_username_search
       and prepared.search_value ~ '^[a-z0-9_]{3,24}$'
       and lower(profile.username) = prepared.search_value
     )
     or (
       not prepared.is_username_search
       and char_length(prepared.search_value) >= 3
       and to_tsvector('simple'::regconfig, profile.display_name)
         @@ private.display_name_prefix_query(prepared.search_value)
     )
   )
  left join public.friendships friendship
    on friendship.user_one_id = least(profile.id, auth.uid())
   and friendship.user_two_id = greatest(profile.id, auth.uid())
  left join public.friend_requests request
    on request.pair_user_one_id = least(profile.id, auth.uid())
   and request.pair_user_two_id = greatest(profile.id, auth.uid())
  left join private.profile_friend_counts profile_count
    on profile_count.user_id = profile.id
  where auth.uid() is not null
    and friendship.id is null
  order by
    prepared.is_username_search desc,
    (lower(profile.display_name) = prepared.search_value) desc,
    (left(lower(profile.display_name), length(prepared.search_value)) = prepared.search_value) desc,
    lower(profile.display_name),
    profile.id
  limit case
    when (select is_username_search from prepared) then 1
    else least(greatest(coalesce(result_limit, 10), 1), 10)
  end;
$$;

revoke all on function private.search_friend_candidates_impl(text, integer)
from public, anon;
grant execute on function private.search_friend_candidates_impl(text, integer)
to authenticated, service_role;

create function public.search_friend_candidates(
  search_query text,
  result_limit integer default 10
)
returns table (
  id uuid,
  request_id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text,
  friend_count bigint,
  relationship text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select *
  from private.search_friend_candidates_impl(search_query, result_limit);
$$;

revoke all on function public.search_friend_candidates(text, integer)
from public, anon;
grant execute on function public.search_friend_candidates(text, integer)
to authenticated, service_role;

create or replace function private.get_friend_requests_impl()
returns table (
  request_id uuid,
  peer_id uuid,
  peer_username text,
  peer_display_name text,
  peer_avatar_url text,
  peer_avatar_storage_path text,
  peer_friend_count bigint,
  direction text,
  requested_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    request.id,
    peer.id,
    peer.username,
    peer.display_name,
    peer.avatar_url,
    peer.avatar_storage_path,
    case
      when peer.show_friends_count or peer.id = auth.uid()
        then coalesce(peer_count.friends_count, 0)::bigint
      else null
    end,
    case when request.sender_id = auth.uid() then 'outgoing' else 'incoming' end,
    request.created_at
  from public.friend_requests request
  join public.profiles peer
    on peer.id = case
      when request.sender_id = auth.uid() then request.recipient_id
      else request.sender_id
    end
  left join private.profile_friend_counts peer_count
    on peer_count.user_id = peer.id
  where auth.uid() is not null
    and auth.uid() in (request.sender_id, request.recipient_id)
  order by request.created_at desc, request.id desc;
$$;

revoke all on function private.get_friend_requests_impl()
from public, anon;
grant execute on function private.get_friend_requests_impl()
to authenticated, service_role;

comment on table private.profile_friend_counts is
  'Cached accepted-friend counts maintained by friendships triggers.';
