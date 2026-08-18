import { createClient } from 'npm:@supabase/supabase-js@2';

const bucketName = 'avatars';
const maxAvatarBytes = 2 * 1024 * 1024;
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

type ImportRequest = {
  source_url?: string;
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (request.method !== 'POST') {
    return jsonResponse({ error: 'method_not_allowed' }, 405);
  }

  const authorization = request.headers.get('authorization');
  const accessToken = authorization?.replace(/^Bearer\s+/i, '').trim();
  if (!accessToken) {
    return jsonResponse({ error: 'missing_access_token' }, 401);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: 'server_not_configured' }, 500);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const {
    data: { user },
    error: userError,
  } = await admin.auth.getUser(accessToken);
  if (userError || !user) {
    return jsonResponse({ error: 'invalid_access_token' }, 401);
  }

  let payload: ImportRequest;
  try {
    payload = (await request.json()) as ImportRequest;
  } catch (_) {
    return jsonResponse({ error: 'invalid_json' }, 400);
  }

  const sourceUrl = parseYandexAvatarUrl(payload.source_url);
  if (!sourceUrl) {
    return jsonResponse({ error: 'invalid_avatar_url' }, 400);
  }

  const imageResponse = await fetch(sourceUrl, { redirect: 'follow' });
  if (!imageResponse.ok) {
    return jsonResponse({ error: 'avatar_download_failed' }, 502);
  }

  const imageBytes = new Uint8Array(await imageResponse.arrayBuffer());
  if (imageBytes.length === 0 || imageBytes.length > maxAvatarBytes) {
    return jsonResponse({ error: 'avatar_size_invalid' }, 413);
  }

  const { data: currentProfile } = await admin
    .from('profiles')
    .select('avatar_storage_path')
    .eq('id', user.id)
    .maybeSingle();
  const previousPath = currentProfile?.avatar_storage_path as
    | string
    | null
    | undefined;
  const path = `${user.id}/${Date.now()}_${crypto.randomUUID()}.jpg`;
  const { error: uploadError } = await admin.storage
    .from(bucketName)
    .upload(path, imageBytes, {
      contentType: 'image/jpeg',
      cacheControl: '31536000',
      upsert: false,
    });
  if (uploadError) {
    return jsonResponse({ error: 'avatar_upload_failed' }, 502);
  }

  const updatedAt = new Date().toISOString();
  const { error: profileError } = await admin
    .from('profiles')
    .update({
      avatar_storage_path: path,
      avatar_updated_at: updatedAt,
    })
    .eq('id', user.id);
  if (profileError) {
    await admin.storage.from(bucketName).remove([path]);
    return jsonResponse({ error: 'profile_update_failed' }, 500);
  }

  if (previousPath && previousPath !== path) {
    await admin.storage.from(bucketName).remove([previousPath]);
  }

  return jsonResponse({ path, updated_at: updatedAt });
});

function parseYandexAvatarUrl(value: string | undefined): URL | null {
  if (!value) return null;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && url.hostname === 'avatars.yandex.net'
      ? url
      : null;
  } catch (_) {
    return null;
  }
}

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return Response.json(body, {
    status,
    headers: corsHeaders,
  });
}
