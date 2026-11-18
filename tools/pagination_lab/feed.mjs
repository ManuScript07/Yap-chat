import assert from 'node:assert/strict';
import {createHash, randomUUID} from 'node:crypto';
import {seedFeedPhotos as seedPhotos, verifyFeedPhotos as verifyPhotos} from './feed_photos.mjs';

const postCount = 65;
const pageSize = 20;
const expectedSizes = [20, 20, 20, 5];

function fixture(lab) {
  const owner = lab.state.owner.id;
  const digest = createHash('sha256').update('feed:' + lab.state.run).digest('hex');
  const prefix = digest.slice(0, 8) + '-' + digest.slice(8, 12) + '-4000-8000-';
  return {owner, prefix};
}

export async function seedFeed(lab) {
  const {owner, prefix} = fixture(lab);
  const authorIds = lab.state.users.filter(user => user.index >= 2)
    .map(user => "'" + user.id + "'").join(',');
  const result = lab.data(`
    begin;
    insert into public.user_locations(user_id, latitude, longitude, updated_at)
    values ('${owner}', 55.75, 37.61, statement_timestamp())
    on conflict (user_id) do update set updated_at = excluded.updated_at;

    with friends as (
      select candidate.id, candidate.ordinality
      from unnest(array[${authorIds}]::uuid[]) with ordinality candidate(id, ordinality)
      join public.friendships f on f.user_one_id = least('${owner}'::uuid, candidate.id)
        and f.user_two_id = greatest('${owner}'::uuid, candidate.id)
      order by candidate.ordinality limit 13
    ), authors as (
      select id, row_number() over(order by ordinality) as author_number from friends
    ), rows as (
      select ('${prefix}' || lpad(n::text, 12, '0'))::uuid as id,
        a.id as author_id,
        'Feed Lab ' || lpad(n::text, 3, '0') ||
          case when n % 5 = 1 then E'\\n\\n' || repeat('Длинный текст для проверки раскрытия и прокрутки. ', 9)
            else '' end as body,
        statement_timestamp() - (1 + (n - 1) / 3) * interval '1 second' as created_at
      from generate_series(1, ${postCount}) n
      join authors a on a.author_number = 1 + (n - 1) % 13
    )
    insert into feed.posts(id, author_id, text, audience, language, creation_request, created_at, latitude, longitude)
    select r.id, r.author_id, r.body, 'public', 'ru', '{"fixture":"pagination-lab-feed"}',
      r.created_at, l.latitude, l.longitude
    from rows r cross join public.user_locations l where l.user_id = '${owner}'
    on conflict (id) do update set created_at = excluded.created_at,
      latitude = excluded.latitude, longitude = excluded.longitude
    where feed.posts.creation_request = excluded.creation_request
      and feed.posts.author_id = excluded.author_id;

    do $$
    begin
      if (select count(*) from feed.posts where id::text like '${prefix}%'
          and creation_request = '{"fixture":"pagination-lab-feed"}'
          and exists (select 1 from public.friendships f
            where f.user_one_id = least('${owner}'::uuid, feed.posts.author_id)
              and f.user_two_id = greatest('${owner}'::uuid, feed.posts.author_id))) <> ${postCount} then
        raise exception 'Incomplete feed fixture';
      end if;
    end $$;
    select jsonb_build_object('posts', count(*), 'authors', count(distinct author_id))
    from feed.posts where id::text like '${prefix}%' and creation_request = '{"fixture":"pagination-lab-feed"}';
    commit;
  `);
  assert.deepEqual(result, {posts: postCount, authors: 13});
  return {...result, ...await seedPhotos(lab, prefix, owner)};
}

export function seedFeedPhotos(lab) {
  const {prefix, owner} = fixture(lab);
  return seedPhotos(lab, prefix, owner);
}

export function verifyFeedPhotos(lab) {
  return verifyPhotos(lab, fixture(lab).prefix);
}

export async function verifyFeed(lab) {
  const {prefix} = fixture(lab);
  const owner = lab.state.owner;
  const session = await lab.session(owner);
  const expected = Array.from({length: postCount}, (_, i) =>
    prefix + String(i + 1).padStart(12, '0'));
  const report = {};
  const posts = new Map();
  for (const rpc of ['get_for_you_feed_v2', 'get_nearby_feed', 'get_friends_feed']) {
    const personalized = rpc === 'get_for_you_feed_v2';
    const sessionId = personalized ? randomUUID() : null;
    const observed = [];
    const pageSizes = [];
    let cursor = null;
    let replayed = false;
    const visited = new Set();
    for (let request = 0; request < 16; request++) {
      const params = personalized
        ? {requested_session: sessionId, requested_cursor: cursor, requested_limit: pageSize}
        : {requested_session: cursor?.session_id ?? null, after_position: cursor?.after_position ?? -1, requested_limit: pageSize};
      const page = await lab.rpc(owner, rpc, params, session);
      assert.ok(page.items.length <= pageSize, rpc + ': oversized page');
      const fixtureIds = page.items.map(item => item.post.id).filter(id => id.startsWith(prefix));
      if (fixtureIds.length) pageSizes.push(fixtureIds.length);
      observed.push(...fixtureIds);
      if (rpc === 'get_friends_feed') {
        for (const {post} of page.items) posts.set(post.id, post);
      }
      if (request === 1) {
        const replay = await lab.rpc(owner, rpc, params, session);
        assert.deepEqual(replay.items.map(item => item.post.id), page.items.map(item => item.post.id), rpc + ': replay changed rows');
        assert.deepEqual(replay.next_cursor, page.next_cursor, rpc + ': replay changed cursor');
        replayed = true;
      }
      cursor = page.next_cursor;
      if (cursor === null) break;
      const key = JSON.stringify(cursor);
      assert.ok(!visited.has(key), rpc + ': cursor loop');
      visited.add(key);
    }
    assert.equal(cursor, null, rpc + ': feed did not terminate');
    assert.ok(replayed, rpc + ': continuation was not replayed');
    assert.deepEqual(observed, expected, rpc + ': unexpected fixture order, duplicate or missing post');
    assert.deepEqual(pageSizes, expectedSizes, rpc + ': unexpected fixture page sizes');
    report[rpc] = {pages: pageSizes, posts: observed.length, replayed};
  }
  return {...report, media: await verifyPhotos(lab, prefix, {posts, session})};
}
