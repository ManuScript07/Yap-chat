-- Viewer-aware profile payloads, public friend lists, and throttled view counts.
create table private.profile_view_counters (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  viewer_id uuid not null references public.profiles(id) on delete cascade,
  view_count bigint not null default 1 check (view_count > 0),
  last_viewed_at timestamptz not null default now(),
  primary key (profile_id, viewer_id),
  check (profile_id <> viewer_id)
);

create index profile_view_counters_profile_idx
  on private.profile_view_counters (profile_id);

revoke all on table private.profile_view_counters from public, anon, authenticated;

create function private.record_profile_view_impl(target_user_id uuid)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare total_views bigint;
begin
  if auth.uid() is null then
    raise exception 'authentication_required';
  end if;
  if target_user_id is null or target_user_id = auth.uid() then
    return 0;
  end if;
  if not exists (
    select 1 from public.profiles profile
    where profile.id = target_user_id and profile.onboarding_completed
  ) then
    raise exception 'profile_not_found';
  end if;

  insert into private.profile_view_counters as counter (
    profile_id, viewer_id, view_count, last_viewed_at
  ) values (target_user_id, auth.uid(), 1, now())
  on conflict on constraint profile_view_counters_pkey do update set
    view_count = case
      when counter.last_viewed_at <= now() - interval '20 minutes'
        then counter.view_count + 1
      else counter.view_count
    end,
    last_viewed_at = case
      when counter.last_viewed_at <= now() - interval '20 minutes' then now()
      else counter.last_viewed_at
    end;

  select coalesce(sum(counter.view_count), 0)
  into total_views
  from private.profile_view_counters counter
  where counter.profile_id = target_user_id;
  return total_views;
end;
$$;

create function public.record_profile_view(target_user_id uuid)
returns bigint
language sql security invoker set search_path = ''
as $$ select private.record_profile_view_impl(target_user_id); $$;

create function private.get_profile_view_count_impl(target_user_id uuid)
returns bigint
language sql stable security definer set search_path = ''
as $$
  select coalesce(sum(counter.view_count), 0)
  from private.profile_view_counters counter
  where auth.uid() is not null and counter.profile_id = target_user_id;
$$;

create function public.get_profile_view_count(target_user_id uuid)
returns bigint
language sql security invoker set search_path = ''
as $$ select private.get_profile_view_count_impl(target_user_id); $$;

create function private.get_viewed_profile_impl(
  target_user_id uuid,
  should_register_view boolean
)
returns table (
  id uuid,
  username text,
  display_name text,
  birth_date date,
  avatar_url text,
  avatar_storage_path text,
  avatar_updated_at timestamptz,
  gender text,
  bio text,
  onboarding_completed boolean,
  created_at timestamptz,
  photos jsonb,
  relationship text,
  request_id uuid,
  friend_count bigint,
  friends_preview jsonb,
  profile_view_count bigint,
  last_seen_at timestamptz,
  shows_last_seen boolean
)
language plpgsql security definer set search_path = ''
as $$
declare current_user_id uuid := auth.uid();
declare counted_views bigint;
begin
  if current_user_id is null then raise exception 'authentication_required'; end if;
  if target_user_id is null or target_user_id = current_user_id then
    raise exception using errcode = '22023', message = 'invalid_profile_target';
  end if;

  if coalesce(should_register_view, true) then
    counted_views := private.record_profile_view_impl(target_user_id);
  else
    select coalesce(sum(counter.view_count), 0)
    into counted_views
    from private.profile_view_counters counter
    where counter.profile_id = target_user_id;
  end if;

  return query
  with target as (
    select profile.*
    from public.profiles profile
    where profile.id = target_user_id and profile.onboarding_completed
  ), relation as (
    select
      friendship.id as friendship_id,
      request.id as request_id,
      request.sender_id,
      request.recipient_id
    from target
    left join public.friendships friendship
      on friendship.user_one_id = least(current_user_id, target.id)
     and friendship.user_two_id = greatest(current_user_id, target.id)
    left join public.friend_requests request
      on request.pair_user_one_id = least(current_user_id, target.id)
     and request.pair_user_two_id = greatest(current_user_id, target.id)
  ), target_friends as (
    select
      peer.id,
      peer.username,
      peer.display_name,
      peer.avatar_url,
      peer.avatar_storage_path,
      friendship.created_at
    from target
    join public.friendships friendship
      on friendship.user_one_id = target.id or friendship.user_two_id = target.id
    join public.profiles peer
      on peer.id = case
        when friendship.user_one_id = target.id then friendship.user_two_id
        else friendship.user_one_id
      end
    where peer.onboarding_completed
    order by friendship.created_at desc, peer.id
  )
  select
    target.id,
    target.username,
    target.display_name,
    target.birth_date,
    target.avatar_url,
    target.avatar_storage_path,
    target.avatar_updated_at,
    target.gender,
    target.bio,
    target.onboarding_completed,
    target.created_at,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'position', photo.position,
        'avatar_url', photo.avatar_url,
        'storage_path', photo.storage_path,
        'updated_at', photo.updated_at
      ) order by photo.position)
      from public.profile_photos photo
      where photo.profile_id = target.id
    ), '[]'::jsonb),
    case
      when relation.friendship_id is not null then 'friend'
      when relation.sender_id = current_user_id then 'outgoing'
      when relation.recipient_id = current_user_id then 'incoming'
      else 'none'
    end,
    relation.request_id,
    (select count(*) from target_friends),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', preview.id,
        'username', preview.username,
        'display_name', preview.display_name,
        'avatar_url', preview.avatar_url,
        'avatar_storage_path', preview.avatar_storage_path
      ) order by preview.created_at desc, preview.id)
      from (select * from target_friends limit 3) preview
    ), '[]'::jsonb),
    coalesce(counted_views, 0),
    case
      when coalesce(privacy.last_seen_visibility, 'all') = 'all'
        or (coalesce(privacy.last_seen_visibility, 'all') = 'friends'
          and relation.friendship_id is not null)
      then target.last_seen_at
      else null
    end,
    coalesce(privacy.last_seen_visibility, 'all') = 'all'
      or (coalesce(privacy.last_seen_visibility, 'all') = 'friends'
        and relation.friendship_id is not null)
  from target
  cross join relation
  left join private.search_privacy_settings privacy on privacy.user_id = target.id;
end;
$$;

create function public.get_viewed_profile(
  target_user_id uuid,
  should_register_view boolean default true
)
returns table (
  id uuid, username text, display_name text, birth_date date,
  avatar_url text, avatar_storage_path text, avatar_updated_at timestamptz,
  gender text, bio text, onboarding_completed boolean, created_at timestamptz,
  photos jsonb, relationship text, request_id uuid, friend_count bigint,
  friends_preview jsonb, profile_view_count bigint, last_seen_at timestamptz,
  shows_last_seen boolean
)
language sql security invoker set search_path = ''
as $$
  select * from private.get_viewed_profile_impl(target_user_id, should_register_view);
$$;

create function private.get_user_profile_friends_impl(target_user_id uuid)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  avatar_storage_path text
)
language sql stable security definer set search_path = ''
as $$
  select
    peer.id,
    peer.username,
    peer.display_name,
    peer.avatar_url,
    peer.avatar_storage_path
  from public.friendships friendship
  join public.profiles peer
    on peer.id = case
      when friendship.user_one_id = target_user_id then friendship.user_two_id
      else friendship.user_one_id
    end
  where auth.uid() is not null
    and target_user_id is not null
    and (friendship.user_one_id = target_user_id or friendship.user_two_id = target_user_id)
    and peer.onboarding_completed
  order by peer.display_name, peer.id;
$$;

create function public.get_user_profile_friends(target_user_id uuid)
returns table (
  id uuid, username text, display_name text,
  avatar_url text, avatar_storage_path text
)
language sql security invoker set search_path = ''
as $$ select * from private.get_user_profile_friends_impl(target_user_id); $$;

create function private.remove_friend_impl(friend_user_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if friend_user_id is null or friend_user_id = auth.uid() then
    raise exception using errcode = '22023', message = 'invalid_friend_target';
  end if;
  delete from public.friendships friendship
  where friendship.user_one_id = least(auth.uid(), friend_user_id)
    and friendship.user_two_id = greatest(auth.uid(), friend_user_id);
end;
$$;

create function public.remove_friend(friend_user_id uuid)
returns void
language sql security invoker set search_path = ''
as $$ select private.remove_friend_impl(friend_user_id); $$;

revoke all on function private.record_profile_view_impl(uuid) from public, anon;
revoke all on function private.get_viewed_profile_impl(uuid, boolean) from public, anon;
revoke all on function private.get_profile_view_count_impl(uuid) from public, anon;
revoke all on function private.get_user_profile_friends_impl(uuid) from public, anon;
revoke all on function private.remove_friend_impl(uuid) from public, anon;
revoke all on function public.record_profile_view(uuid) from public, anon;
revoke all on function public.get_viewed_profile(uuid, boolean) from public, anon;
revoke all on function public.get_profile_view_count(uuid) from public, anon;
revoke all on function public.get_user_profile_friends(uuid) from public, anon;
revoke all on function public.remove_friend(uuid) from public, anon;

grant execute on function private.record_profile_view_impl(uuid) to authenticated, service_role;
grant execute on function private.get_viewed_profile_impl(uuid, boolean) to authenticated, service_role;
grant execute on function private.get_profile_view_count_impl(uuid) to authenticated, service_role;
grant execute on function private.get_user_profile_friends_impl(uuid) to authenticated, service_role;
grant execute on function private.remove_friend_impl(uuid) to authenticated, service_role;
grant execute on function public.record_profile_view(uuid) to authenticated, service_role;
grant execute on function public.get_viewed_profile(uuid, boolean) to authenticated, service_role;
grant execute on function public.get_profile_view_count(uuid) to authenticated, service_role;
grant execute on function public.get_user_profile_friends(uuid) to authenticated, service_role;
grant execute on function public.remove_friend(uuid) to authenticated, service_role;

comment on function public.get_viewed_profile(uuid, boolean) is
  'Returns a viewer-specific full profile and optionally records one view per viewer every twenty minutes.';
