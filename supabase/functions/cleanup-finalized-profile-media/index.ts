import { createClient } from 'npm:@supabase/supabase-js@2';

type ProfileCleanupTask = {
  id: string;
  owner_user_id: string;
  bucket_id: string;
  storage_path: string;
};

type ChatCleanupTask = {
  id: string;
  bucket_id: string;
  storage_path: string;
};

type QueueResult = {
  claimed: number;
  deleted: number;
  deferred: number;
};

/**
 * Service-only worker called by pg_cron through pg_net. It removes avatar
 * files after account finalisation, photos removed from active profiles, and
 * chat media after their retention window through the Storage API. All three
 * queues are populated solely from validated
 * database metadata; the worker accepts no request-supplied paths.
 */
Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return Response.json({ error: 'method_not_allowed' }, { status: 405 });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const schedulerToken = Deno.env.get(
    'ACCOUNT_DELETION_CLEANUP_SCHEDULER_TOKEN',
  );
  if (!supabaseUrl || !serviceRoleKey || !schedulerToken) {
    return Response.json({ error: 'server_not_configured' }, { status: 500 });
  }
  if (request.headers.get('apikey') !== schedulerToken) {
    return Response.json({ error: 'unauthorized' }, { status: 401 });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  let profile: QueueResult;
  let removedProfilePhotos: QueueResult;
  let chat: QueueResult;
  try {
    profile = await processProfileQueue(admin);
    removedProfilePhotos = await processRemovedProfilePhotos(admin);
    chat = await processChatQueue(admin);
  } catch (error) {
    console.error('could not claim media cleanup queue', error);
    return Response.json({ error: 'cleanup_claim_failed' }, { status: 500 });
  }

  return Response.json({
    claimed: profile.claimed + removedProfilePhotos.claimed + chat.claimed,
    deleted: profile.deleted + removedProfilePhotos.deleted + chat.deleted,
    deferred: profile.deferred + removedProfilePhotos.deferred + chat.deferred,
    profile,
    removedProfilePhotos,
    chat,
  });
});

async function processProfileQueue(
  admin: ReturnType<typeof createClient>,
): Promise<QueueResult> {
  const { data, error } = await admin.rpc(
    'claim_finalized_profile_media_cleanup_batch',
    { requested_batch_size: 250 },
  );
  if (error) {
    console.error('could not claim profile media cleanup batch', error);
    throw error;
  }
  const tasks = (data ?? []) as ProfileCleanupTask[];
  return processQueue(
    admin,
    tasks,
    'complete_finalized_profile_media_cleanup',
    'defer_finalized_profile_media_cleanup',
    (task) =>
      task.bucket_id === 'avatars' &&
      task.storage_path.startsWith(`${task.owner_user_id}/`),
    'invalid_profile_media_cleanup_path',
  );
}

async function processRemovedProfilePhotos(
  admin: ReturnType<typeof createClient>,
): Promise<QueueResult> {
  const { data, error } = await admin.rpc(
    'claim_removed_profile_photo_cleanup_batch',
    { requested_batch_size: 100 },
  );
  if (error) {
    console.error('could not claim removed profile photos', error);
    throw error;
  }
  return processQueue(
    admin,
    (data ?? []) as ProfileCleanupTask[],
    'complete_removed_profile_photo_cleanup',
    'defer_removed_profile_photo_cleanup',
    (task) =>
      task.bucket_id === 'avatars' &&
      task.storage_path.startsWith(
        `${(task as ProfileCleanupTask).owner_user_id}/`,
      ),
    'invalid_removed_profile_photo_path',
  );
}

async function processChatQueue(
  admin: ReturnType<typeof createClient>,
): Promise<QueueResult> {
  const { data, error } = await admin.rpc('claim_chat_media_cleanup_batch', {
    requested_batch_size: 1000,
  });
  if (error) {
    console.error('could not claim chat media cleanup batch', error);
    throw error;
  }
  const tasks = (data ?? []) as ChatCleanupTask[];
  return processQueue(
    admin,
    tasks,
    'complete_chat_media_cleanup',
    'defer_chat_media_cleanup',
    (task) =>
      (task.bucket_id === 'chat-images' || task.bucket_id === 'chat-audio') &&
      /^[0-9a-f-]{36}\/[0-9a-f-]{36}\/[0-9a-f-]{36}\/[^/]+$/i.test(
        task.storage_path,
      ),
    'invalid_chat_media_cleanup_path',
  );
}

async function processQueue(
  admin: ReturnType<typeof createClient>,
  tasks: Array<ProfileCleanupTask | ChatCleanupTask>,
  completeRpc: string,
  deferRpc: string,
  isValid: (task: ProfileCleanupTask | ChatCleanupTask) => boolean,
  invalidMessage: string,
): Promise<QueueResult> {
  const tasksByBucket = new Map<string, Array<ProfileCleanupTask | ChatCleanupTask>>();
  let deferred = 0;
  for (const task of tasks) {
    if (!isValid(task)) {
      await defer(admin, deferRpc, [task.id], invalidMessage);
      deferred += 1;
      continue;
    }
    const bucketTasks = tasksByBucket.get(task.bucket_id) ?? [];
    bucketTasks.push(task);
    tasksByBucket.set(task.bucket_id, bucketTasks);
  }

  let deleted = 0;
  for (const [bucketId, bucketTasks] of tasksByBucket) {
    // Keep each Storage API call small even when a long-lived conversation
    // releases many attachments in the same scheduled run.
    for (let index = 0; index < bucketTasks.length; index += 100) {
      const batch = bucketTasks.slice(index, index + 100);
      const ids = batch.map((task) => task.id);
      const { error: removeError } = await admin.storage
        .from(bucketId)
        .remove(batch.map((task) => task.storage_path));
      if (removeError) {
        console.error('could not remove retained media', removeError);
        await defer(admin, deferRpc, ids, removeError.message);
        deferred += ids.length;
        continue;
      }
      const { error: completeError } = await admin.rpc(completeRpc, {
        queue_ids: ids,
      });
      if (completeError) {
        // Storage deletion is idempotent.  Leaving the leased task pending is
        // safe: a later invocation may repeat the remove operation.
        console.error('could not complete media cleanup', completeError);
        deferred += ids.length;
        continue;
      }
      deleted += ids.length;
    }
  }
  return { claimed: tasks.length, deleted, deferred };
}

async function defer(
  admin: ReturnType<typeof createClient>,
  deferRpc: string,
  ids: string[],
  message: string,
) {
  const { error } = await admin.rpc(deferRpc, {
    queue_ids: ids,
    failure_message: message,
  });
  if (error) console.error('could not defer media cleanup', error);
}
