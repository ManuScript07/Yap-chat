import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

/**
 * Starts the thirty-day deletion window for the authenticated account.
 *
 * The user id is derived exclusively from the bearer token.  The service-role
 * client is used only to reach the private transactional database function;
 * no service credential is ever returned to the device.
 */
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

  const survey = await parseSurvey(request);
  if (!survey) return json({ error: 'account_deletion_survey_invalid' }, 400);

  const { data, error } = await admin.rpc(
    'request_account_deletion_from_service',
    {
      target_user_id: user.id,
      requested_by_value: 'self',
      requested_reasons: survey.reasons,
      requested_feedback: survey.feedback,
    },
  );
  if (error) {
    console.error('account deletion request failed', error);
    const rateLimited = error.message.includes('account_deletion_rate_limited');
    const globallyBanned = error.message.includes('account_globally_banned');
    const invalidSurvey = error.message.includes('account_deletion_survey_invalid');
    return json(
      {
        error: rateLimited
          ? 'account_deletion_rate_limited'
          : globallyBanned
          ? 'account_globally_banned'
          : invalidSurvey
          ? 'account_deletion_survey_invalid'
          : 'account_deletion_failed',
      },
      rateLimited ? 429 : globallyBanned ? 403 : invalidSurvey ? 400 : 500,
    );
  }

  const scheduledFor = Array.isArray(data)
    ? data[0]?.scheduled_for
    : null;
  return json({ status: 'scheduled', scheduled_for: scheduledFor });
});

function json(body: Record<string, unknown>, status = 200) {
  return Response.json(body, { status, headers: corsHeaders });
}

const deletionReasons = new Set([
  'ads',
  'new_account',
  'safety',
  'few_people',
  'no_longer_chat',
  'technical_problems',
  'other',
]);

async function parseSurvey(
  request: Request,
): Promise<{ reasons: string[]; feedback: string | null } | null> {
  let body: unknown;
  try {
    body = await request.json();
  } catch (_) {
    return null;
  }
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    return null;
  }
  const { reasons, feedback } = body as Record<string, unknown>;
  if (
    !Array.isArray(reasons) ||
    reasons.length === 0 ||
    reasons.length > deletionReasons.size ||
    reasons.some((reason) => typeof reason !== 'string' || !deletionReasons.has(reason)) ||
    new Set(reasons).size !== reasons.length
  ) {
    return null;
  }
  if (feedback !== null && feedback !== undefined && typeof feedback !== 'string') {
    return null;
  }
  const normalizedFeedback = typeof feedback === 'string' ? feedback.trim() : null;
  if (normalizedFeedback !== null && normalizedFeedback.length > 150) return null;
  return {
    reasons: reasons as string[],
    feedback: normalizedFeedback || null,
  };
}
