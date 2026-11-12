-- Operator control for the bounded vision pilot. Shadow indexes with an empty
-- viewer list. The existing serving functions continue to gate on membership.
create function recsys.set_vision_rollout(requested_mode text, requested_viewers uuid[] default '{}'::uuid[])
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
    previous_enabled boolean;
    old_viewers uuid[];
    new_viewers uuid[];
    changed uuid[];
    viewer record;
    new_revision bigint;
begin
    if requested_mode is null or requested_mode not in ('off', 'shadow', 'serve')
       or requested_viewers is null or cardinality(requested_viewers) > 32
       or coalesce(array_ndims(requested_viewers), 1) <> 1
       or array_position(requested_viewers, null::uuid) is not null
       or (requested_mode = 'serve') <> (cardinality(requested_viewers) > 0) then
        raise exception using errcode = '22023', message = 'invalid_vision_rollout';
    end if;
    select coalesce(array_agg(distinct id order by id), '{}'::uuid[]) into new_viewers
        from unnest(requested_viewers) as input(id);
    if cardinality(new_viewers) <> cardinality(requested_viewers) then
        raise exception using errcode = '22023', message = 'duplicate_vision_viewer';
    end if;

    -- Match the publisher's settings -> membership -> state lock order.
    select enabled into strict previous_enabled from recsys.vision_settings for update;
    select coalesce(array_agg(user_id order by user_id), '{}'::uuid[]) into old_viewers
        from recsys.vision_viewers;
    select coalesce(array_agg(id order by id), '{}'::uuid[]) into changed from (
        select id from unnest(old_viewers) as old(id) where not (id = any(new_viewers)) or not previous_enabled
        union
        select id from unnest(new_viewers) as added(id) where not (id = any(old_viewers)) or not previous_enabled
    ) affected;

    delete from recsys.vision_viewers where not (user_id = any(new_viewers));
    with free_slots as (
        select slots.slot, row_number() over (order by slots.slot) as position
        from generate_series(1, 32) as slots(slot)
        where not exists(select 1 from recsys.vision_viewers v where v.slot = slots.slot)
    ), additions as (
        select id, row_number() over (order by id) as position from unnest(new_viewers) as added(id)
        where not exists(select 1 from recsys.vision_viewers v where v.user_id = added.id)
    )
    insert into recsys.vision_viewers(slot, user_id)
        select slot, id from free_slots join additions using (position);
    update recsys.vision_settings set enabled = requested_mode <> 'off'
        where enabled is distinct from (requested_mode <> 'off');

    -- Keep older session IDs readable, but new sessions must use the new
    -- policy. Fence leased builds from both sides of a cohort change.
    for viewer in select user_id from recsys.user_states where user_id = any(changed) order by user_id for update loop
        update recsys.user_states
            set revision = revision + 1, current_snapshot = null, prepared_at = null, profile_complete = false
            where user_id = viewer.user_id returning revision into strict new_revision;
        perform private.queue_recommendation_refresh(viewer.user_id, new_revision, true);
        update recsys.refresh_jobs set lease = null, locked_until = null, claimed_at = null
            where user_id = viewer.user_id and lease is not null;
    end loop;

    return jsonb_build_object('mode', requested_mode, 'viewers', cardinality(new_viewers),
                              'changed_viewers', cardinality(changed));
end $$;

revoke all on function recsys.set_vision_rollout(text,uuid[])
    from public, anon, authenticated, service_role, yap_recommendation_worker, yap_feed_media_worker, yap_feed_vision_worker;
grant execute on function recsys.set_vision_rollout(text,uuid[]) to postgres;
