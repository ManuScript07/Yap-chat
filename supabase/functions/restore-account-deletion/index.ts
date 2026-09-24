import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

/** Restores the authenticated account before its deletion window expires. */
Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (request.method !== 'POST') {
    return json({ error: 'method_not_allowed' }, 405);
  }

  const accessToken = request.headers
    .get('authorization')
    ?.replace(/^Bearer\s+/i, '')
    .trim();
  if (!accessToken) return json({ error: 'missing_access_token' }, 401);

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: 'server_not_configured' }, 500);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const {
    data: { user },
    error: userError,
  } = await admin.auth.getUser(accessToken);
  if (userError || !user) return json({ error: 'invalid_access_token' }, 401);

  const { error } = await admin.rpc(
    'restore_account_deletion_from_service',
    { target_user_id: user.id },
  );
  if (error) {
    const expired = error.message.includes('account_deletion_expired');
    const rateLimited = error.message.includes('account_deletion_rate_limited');
    return json(
      {
        error: rateLimited
          ? 'account_deletion_rate_limited'
          : expired
          ? 'account_deletion_expired'
          : 'account_restore_failed',
      },
      rateLimited ? 429 : expired ? 410 : 500,
    );
  }

  return json({ status: 'restored' });
});

function json(body: Record<string, unknown>, status = 200) {
  return Response.json(body, { status, headers: corsHeaders });
}
