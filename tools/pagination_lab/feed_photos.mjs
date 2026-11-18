import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';

const marker = 'pagination-lab-photo-v1';
const dimensions = {
  portrait: [900, 1200], landscape: [1600, 900], square: [2048, 2048],
  panorama: [2048, 256], tall: [256, 2048], strip: [2048, 1], pole: [1, 2048],
};
const examples = [
  [2, ['portrait']], [3, ['landscape']], [4, ['square']],
  [6, ['portrait', 'landscape', 'square']],
  [7, ['panorama', 'tall']], [8, ['strip', 'pole', 'square']],
];

const postId = (prefix, number) => prefix + String(number).padStart(12, '0');
const json = value => `convert_from(decode('${Buffer.from(JSON.stringify(value)).toString('hex')}', 'hex'), 'UTF8')::jsonb`;

function jpegSize(bytes) {
  assert.equal(bytes.readUInt16BE(0), 0xffd8, 'Expected a JPEG fixture');
  for (let offset = 2; offset + 9 < bytes.length;) {
    const tag = bytes.readUInt16BE(offset);
    if (tag === 0xffc0 || tag === 0xffc2) {
      return [bytes.readUInt16BE(offset + 7), bytes.readUInt16BE(offset + 5)];
    }
    const length = bytes.readUInt16BE(offset + 2);
    if (length < 2 || tag === 0xffda) break;
    offset += 2 + length;
  }
  throw Error('JPEG fixture has no size marker');
}

function thumbnailSize([width, height]) {
  const scale = Math.min(1, 512 / Math.max(width, height));
  return [width, height].map(edge => Math.max(1, Math.floor(edge * scale)));
}

function loadAssets() {
  const assets = new Map();
  for (const [name, fullSize] of Object.entries(dimensions)) {
    const full = readFileSync(new URL(`./feed_photos/${name}-image.jpg`, import.meta.url));
    const thumb = readFileSync(new URL(`./feed_photos/${name}-thumbnail.jpg`, import.meta.url));
    assert.deepEqual(jpegSize(full), fullSize, name);
    assert.deepEqual(jpegSize(thumb), thumbnailSize(fullSize), name);
    assets.set(name, {full, thumb});
  }
  return assets;
}

function selectedPhotoPosts(lab) {
  const previous = lab.state.feedPhotoPosts;
  return Array.isArray(previous) && previous.length === examples.length &&
    new Set(previous).size === previous.length &&
    previous.every(number => Number.isInteger(number) && number >= 1 && number <= 65)
    ? previous : examples.map(([number]) => number);
}

export async function seedFeedPhotos(lab, prefix, owner) {
  const assets = loadAssets();
  const posts = lab.data(`select coalesce(jsonb_object_agg(right(p.id::text,12)::int,
    jsonb_build_object('author',p.author_id,'photos',p.photo_count,'fixture_sizes',
      (select jsonb_agg(jsonb_build_array(u.width,u.height) order by u.position)
       from feed.photo_uploads u where u.draft_id=p.id and u.state='attached'
         and u.image_path like '%/${marker}/%'))), '{}') from feed.posts p
    join public.friendships f on f.user_one_id=least('${owner}'::uuid,p.author_id)
      and f.user_two_id=greatest('${owner}'::uuid,p.author_id)
    where p.id::text like '${prefix}%' and p.creation_request='{"fixture":"pagination-lab-feed"}'
      and p.deleted_at is null and private.feed_post_visible('${owner}'::uuid,p.author_id,p.audience);`);
  const candidates = Object.keys(posts).map(Number);
  const previous = selectedPhotoPosts(lab);
  const selected = examples.map(([, names], i) => {
    const sizes = JSON.stringify(names.map(name => dimensions[name]));
    const matches = n => posts[n]?.photos === names.length && JSON.stringify(posts[n].fixture_sizes) === sizes;
    return matches(previous[i]) ? previous[i] : candidates.find(matches) ?? null;
  });
  const used = new Set(selected);
  for (const [i, [preferred]] of examples.entries()) {
    if (selected[i] != null || posts[preferred]?.photos !== 0 || used.has(preferred)) continue;
    selected[i] = preferred;
    used.add(preferred);
  }
  for (const [i, number] of selected.entries()) {
    if (number != null) continue;
    const free = candidates.find(n => posts[n].photos === 0 && !used.has(n));
    assert.ok(free, 'Not enough available lab posts for the photo fixtures');
    selected[i] = free;
    used.add(free);
  }
  const cases = examples.map(([, names], i) => ({
    id: postId(prefix, selected[i]), author: posts[selected[i]].author, names,
    label: `Feed Lab ${String(selected[i]).padStart(3, '0')} · фото ${names.map(name => dimensions[name].join('×')).join(' + ')}`,
  }));
  const rows = cases.flatMap(({id, author, names, label}) => {
    return names.map((name, slot) => {
      const hex = createHash('sha256').update(`${marker}:${id}:${slot}`).digest('hex');
      const photo = `${hex.slice(0,8)}-${hex.slice(8,12)}-4${hex.slice(13,16)}-8${hex.slice(17,20)}-${hex.slice(20,32)}`;
      const path = `${author}/${id}/${photo}/${marker}`;
      const {full, thumb} = assets.get(name);
      const [width, height] = dimensions[name];
      return {post: id, author, photo, slot, width, height, label,
        source: `${path}/source.jpg`, image: `${path}/image.jpg`, thumbnail: `${path}/thumbnail.jpg`,
        image_bytes: full.length, thumbnail_bytes: thumb.length,
        sha256: createHash('sha256').update(full).digest('hex')};
    });
  });
  const records = `jsonb_to_recordset(${json(rows)}) as r(post uuid, author uuid, photo uuid, slot integer,
    width integer, height integer, label text, source text, image text, thumbnail text,
    image_bytes integer, thumbnail_bytes integer, sha256 text)`;
  const preflight = lab.data(`select jsonb_build_object(
    'conflict',(select exists(select 1 from ${records}
      join feed.photo_uploads p on p.draft_id=r.post where p.id<>r.photo and p.slot=r.slot)),
    'existing',(select coalesce(jsonb_agg(name),'[]') from storage.objects where bucket_id='feed-media'
      and name like '%/${marker}/%'));`);
  assert.equal(preflight.conflict, false, 'A fixture slot already contains a manually attached photo');
  const existing = new Set(preflight.existing);
  for (const [index, name] of examples.flatMap(([, names]) => names).entries()) {
    const {full, thumb} = assets.get(name);
    for (const [path, bytes] of [[rows[index].image, full], [rows[index].thumbnail, thumb]]) {
      if (!existing.has(path)) {
        await lab.request(`/storage/v1/object/feed-media/${path}`, {method: 'POST', bytes, contentType: 'image/jpeg'});
      }
    }
  }
  lab.sql(`begin;
    create temp table seeded_feed_photos on commit drop as select * from ${records};
    insert into feed.post_drafts(id,owner_id,published_at)
      select distinct post,author,statement_timestamp() from seeded_feed_photos
      on conflict (id) do nothing;
    do $$ begin
      if exists(select 1 from seeded_feed_photos s join feed.post_drafts d on d.id=s.post
        where d.owner_id<>s.author or d.published_at is null or d.cancelled_at is not null) then
        raise exception 'Feed fixture conflicts with a non-published draft';
      end if;
    end $$;
    insert into feed.photo_uploads(id,draft_id,slot,position,declared_bytes,declared_mime,source_path,
      state,image_path,thumbnail_path,width,height,image_bytes,thumbnail_bytes,sha256)
      select photo,post,slot,slot,image_bytes,'image/jpeg',source,'attached',image,thumbnail,width,height,
        image_bytes,thumbnail_bytes,sha256 from seeded_feed_photos
      on conflict (id) do nothing;
    update feed.posts p set photo_count=s.total,text=s.label
    from (select f.post,min(f.label) as label,(select count(*) from feed.photo_uploads u
      where u.draft_id=f.post and u.state='attached') as total from seeded_feed_photos f group by f.post) s
    where p.id=s.post and p.creation_request='{"fixture":"pagination-lab-feed"}';
    commit;`);
  lab.state.feedPhotoPosts = selected;
  lab.save();
  return {photoPosts: cases.length, photos: rows.length, examples: cases.map(({label}) => label)};
}

export async function verifyFeedPhotos(lab, prefix, {posts, session} = {}) {
  session ??= await lab.session(lab.state.owner);
  const checked = new Set();
  for (const [index, number] of selectedPhotoPosts(lab).entries()) {
    const [, names] = examples[index];
    const id = postId(prefix, number);
    const post = posts ? posts.get(id) : await lab.rpc(lab.state.owner, 'get_feed_post', {requested_id: id}, session);
    assert.ok(post, `Photo fixture Feed Lab ${number} was not returned`);
    assert.deepEqual(post.photos?.map(photo => [photo.width, photo.height]), names.map(name => dimensions[name]),
      `Wrong photos or order for Feed Lab ${number}; rerun seedFeed`);
    for (const photo of post.photos) {
      for (const [path, size] of [[photo.path, [photo.width, photo.height]],
        [photo.thumbnail_path, thumbnailSize([photo.width, photo.height])]]) {
        assert.equal(typeof path, 'string');
        if (checked.has(path)) continue;
        const bytes = await lab.request(`/storage/v1/object/authenticated/feed-media/${path}`,
          {token: session.access_token, binary: true});
        assert.deepEqual(jpegSize(bytes), size);
        checked.add(path);
      }
    }
  }
  return {posts: examples.length, storedJpegs: checked.size};
}
