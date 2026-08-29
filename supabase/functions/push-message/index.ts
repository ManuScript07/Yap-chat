import { JWT } from 'npm:google-auth-library@9';
import { createClient } from 'npm:@supabase/supabase-js@2';

type OutboxRecord = {
  id: string;
  message_id: string | null;
  conversation_id: string | null;
  friend_request_id: string | null;
  notification_type: 'chat_message' | 'friend_request';
  recipient_user_id: string;
  sender_id: string;
  sender_name: string;
  message_type: 'text' | 'image' | 'audio' | 'location';
  message_text: string;
  message_created_at: string;
  status: 'pending' | 'processing' | 'sent' | 'failed';
  attempts: number;
};

type WebhookPayload = {
  record?: OutboxRecord;
  outbox_id?: string;
};

type FirebaseServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

type DeliveryResult = {
  success: boolean;
  invalidToken: boolean;
  error?: string;
};

type CompletionResult =
  | 'delivered_to_fcm'
  | 'no_devices'
  | 'message_deleted';

type PushDevice = {
  id: string;
  token: string;
};

const maxDeliveryAttempts = 3;

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return Response.json({ error: 'method_not_allowed' }, { status: 405 });
  }

  const webhookSecret = Deno.env.get('PUSH_WEBHOOK_SECRET');
  if (
    !webhookSecret ||
    request.headers.get('x-webhook-secret') !== webhookSecret
  ) {
    return Response.json({ error: 'unauthorized' }, { status: 401 });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const serviceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
  if (!supabaseUrl || !serviceRoleKey || !serviceAccountJson) {
    return Response.json({ error: 'server_not_configured' }, { status: 500 });
  }

  let payload: WebhookPayload;
  let serviceAccount: FirebaseServiceAccount;
  try {
    payload = (await request.json()) as WebhookPayload;
    serviceAccount = JSON.parse(serviceAccountJson) as FirebaseServiceAccount;
  } catch (_) {
    return Response.json({ error: 'invalid_payload' }, { status: 400 });
  }

  const outboxId = payload.record?.id ?? payload.outbox_id;
  if (!outboxId) {
    return Response.json({ error: 'missing_outbox_id' }, { status: 400 });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const attempts = Math.max(0, payload.record?.attempts ?? 0) + 1;
  const { data: job, error: claimError } = await admin
    .from('push_notification_outbox')
    .update({
      status: 'processing',
      attempts,
      last_error: null,
      delivery_result: null,
      delivered_device_count: 0,
    })
    .eq('id', outboxId)
    .eq('status', 'pending')
    .select()
    .maybeSingle<OutboxRecord>();

  if (claimError) {
    return Response.json({ error: 'claim_failed' }, { status: 500 });
  }
  if (!job) {
    return Response.json({ status: 'already_processed' });
  }

  if (job.notification_type === 'chat_message') {
    const { data: isMessageDeliverable, error: messageError } = await admin.rpc(
      'is_push_message_deliverable',
      { target_message_id: job.message_id },
    );
    if (messageError) {
      await markFailed(admin, job.id, messageError.message);
      return Response.json({ error: 'message_lookup_failed' }, { status: 500 });
    }
    if (!isMessageDeliverable) {
      await markCompleted(admin, job.id, 'message_deleted', 0);
      return Response.json({ status: 'message_deleted' });
    }
  }

  const { data: devices, error: devicesError } = await admin
    .from('push_devices')
    .select('id, token')
    .eq('user_id', job.recipient_user_id)
    .eq('enabled', true)
    .returns<PushDevice[]>();
  if (devicesError) {
    await markFailed(admin, job.id, devicesError.message);
    return Response.json({ error: 'device_lookup_failed' }, { status: 500 });
  }
  if (!devices?.length) {
    await markCompleted(admin, job.id, 'no_devices', 0);
    return Response.json({ status: 'no_devices' });
  }

  let accessToken: string;
  try {
    accessToken = await createAccessToken(serviceAccount);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await markFailed(admin, job.id, message);
    return Response.json({ error: 'firebase_auth_failed' }, { status: 500 });
  }

  const results = await Promise.all(
    devices.map(async (device) => ({
      device,
      result: await deliverWithRetry(
        serviceAccount.project_id,
        accessToken,
        device.token,
        job,
      ),
    })),
  );

  const invalidDeviceIds = results
    .filter(({ result }) => result.invalidToken)
    .map(({ device }) => device.id);
  if (invalidDeviceIds.length) {
    await admin
      .from('push_devices')
      .update({ enabled: false, updated_at: new Date().toISOString() })
      .in('id', invalidDeviceIds);
  }

  const failedResults = results.filter(
    ({ result }) => !result.success && !result.invalidToken,
  );
  if (failedResults.length) {
    const error = failedResults
      .map(({ result }) => result.error)
      .filter(Boolean)
      .join('; ')
      .slice(0, 2000);
    await markFailed(admin, job.id, error || 'delivery_failed');
    return Response.json({ error: 'delivery_failed' }, { status: 502 });
  }

  const deliveredDeviceCount = results.filter(
    ({ result }) => result.success,
  ).length;
  await markCompleted(
    admin,
    job.id,
    'delivered_to_fcm',
    deliveredDeviceCount,
  );
  return Response.json({
    status: 'sent',
    devices: deliveredDeviceCount,
  });
});

async function createAccessToken(
  serviceAccount: FirebaseServiceAccount,
): Promise<string> {
  const client = new JWT({
    email: serviceAccount.client_email,
    key: serviceAccount.private_key.replace(/\\n/g, '\n'),
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  });
  const credentials = await client.authorize();
  if (!credentials.access_token) throw new Error('missing_access_token');
  return credentials.access_token;
}

async function deliverWithRetry(
  projectId: string,
  accessToken: string,
  token: string,
  job: OutboxRecord,
): Promise<DeliveryResult> {
  let lastResult: DeliveryResult = {
    success: false,
    invalidToken: false,
    error: 'delivery_failed',
  };

  for (let attempt = 0; attempt < maxDeliveryAttempts; attempt += 1) {
    lastResult = await deliver(projectId, accessToken, token, job);
    if (lastResult.success || lastResult.invalidToken) return lastResult;
    if (attempt < maxDeliveryAttempts - 1) {
      await new Promise((resolve) =>
        setTimeout(resolve, 500 * 2 ** attempt),
      );
    }
  }
  return lastResult;
}

async function deliver(
  projectId: string,
  accessToken: string,
  token: string,
  job: OutboxRecord,
): Promise<DeliveryResult> {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token,
          data: {
            conversation_id: job.conversation_id ?? '',
            message_id: job.message_id ?? '',
            friend_request_id: job.friend_request_id ?? '',
            notification_type: job.notification_type,
            recipient_id: job.recipient_user_id,
            sender_id: job.sender_id,
            sender_name: job.sender_name,
            content_type: job.message_type,
            message_text: job.message_text.slice(0, 500),
            sent_at: job.message_created_at,
          },
          android: {
            priority: 'HIGH',
            ttl: '604800s',
          },
        },
      }),
    },
  );

  if (response.ok) return { success: true, invalidToken: false };

  const responseText = await response.text();
  const invalidToken =
    response.status === 404 ||
    responseText.includes('UNREGISTERED') ||
    responseText.includes('SENDER_ID_MISMATCH') ||
    responseText.includes('registration-token-not-registered');
  return {
    success: false,
    invalidToken,
    error: `FCM ${response.status}: ${responseText}`.slice(0, 1000),
  };
}

async function markCompleted(
  admin: ReturnType<typeof createClient>,
  id: string,
  deliveryResult: CompletionResult,
  deliveredDeviceCount: number,
) {
  await admin
    .from('push_notification_outbox')
    .update({
      status: 'sent',
      processed_at: new Date().toISOString(),
      last_error: null,
      delivery_result: deliveryResult,
      delivered_device_count: deliveredDeviceCount,
    })
    .eq('id', id);
}

async function markFailed(
  admin: ReturnType<typeof createClient>,
  id: string,
  error: string,
) {
  await admin
    .from('push_notification_outbox')
    .update({
      status: 'failed',
      processed_at: new Date().toISOString(),
      last_error: error.slice(0, 2000),
    })
    .eq('id', id);
}
