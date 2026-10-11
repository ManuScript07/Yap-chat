// Production and tests share this handler. Claims/progress are database-fenced.
type Admin = {
  rpc: (name: string, args?: Record<string, unknown>) => PromiseLike<{
    data: unknown;
    error: { message: string } | null;
  }>;
};
type Device = { id: string; token: string };
type Job = {
  id: string;
  claim_token: string;
  attempts: number;
  expires_at: string;
  message_id: string | null;
  reaction_message_id: string | null;
  friend_request_id: string | null;
  conversation_id: string | null;
  notification_type: string;
  recipient_user_id: string;
  sender_id: string;
  sender_name: string;
  message_type: string;
  message_text: string;
  message_created_at: string;
};
type Result = {
  device_id: string;
  token: string;
  outcome: "accepted" | "invalid" | "retry" | "failed";
};
type Dependencies = {
  secret?: string;
  configured: boolean;
  createAdmin: () => Admin;
  authorize: () => Promise<{ projectId: string; accessToken: string }>;
  invalidateAuthorization?: (accessToken: string) => void;
  fetch?: typeof fetch;
  now?: () => number;
  random?: () => number;
};
type Claim = { status?: string; job?: Job; devices?: Device[] };
type Completion = { status: string; devices?: number };
type Payload = {
  record?: { id?: unknown };
  outbox_id?: unknown;
  retry_due?: unknown;
};
type FcmError = {
  error?: {
    status?: string;
    details?: { "@type"?: string; errorCode?: string }[];
  };
};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function createPushHandler(deps: Dependencies) {
  const send = deps.fetch ?? fetch;
  const now = deps.now ?? Date.now;
  const random = deps.random ?? Math.random;
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return Response.json({ error: "method_not_allowed" }, { status: 405 });
    }
    if (
      !deps.secret || request.headers.get("x-webhook-secret") !== deps.secret
    ) {
      return Response.json({ error: "unauthorized" }, { status: 401 });
    }
    if (!deps.configured) {
      return Response.json({ error: "server_not_configured" }, { status: 500 });
    }
    let payload: Payload | null;
    try {
      payload = await request.json() as Payload | null;
    } catch {
      return Response.json({ error: "invalid_payload" }, { status: 400 });
    }
    const id = payload?.record?.id ?? payload?.outbox_id;
    if (
      payload?.retry_due !== true && (typeof id !== "string" || !uuid.test(id))
    ) {
      return Response.json({ error: "invalid_outbox_id" }, { status: 400 });
    }
    const admin = deps.createAdmin();
    async function rpc<T>(
      name: string,
      args: Record<string, unknown> = {},
    ): Promise<T> {
      const response = await admin.rpc(name, args);
      if (response.error) throw new Error(name);
      return response.data as T;
    }
    async function process(jobId: string) {
      const claimed = await rpc<Claim>("claim_push_notification", {
        outbox_id: jobId,
      });
      if (!claimed?.job) {
        return { status: claimed?.status ?? "already_processed" };
      }
      const job = claimed.job;
      const devices = claimed.devices ?? [];
      if (devices.length > 10) throw new Error("device_limit_exceeded");
      const results: Result[] = [];
      let retrySeconds = Math.min(
        1800,
        60 * 2 ** Math.min(job.attempts - 1, 5),
      );
      let failure: string | null = null;
      try {
        const { projectId, accessToken } = await deps.authorize();
        const deliveries = await Promise.all(devices.map(async (device) => {
          const ttl = Math.floor((Date.parse(job.expires_at) - now()) / 1000);
          if (ttl <= 0) {
            return {
              result: {
                device_id: device.id,
                token: device.token,
                outcome: "failed",
              } as Result,
            };
          }
          try {
            const response = await send(
              `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
              {
                method: "POST",
                signal: AbortSignal.timeout(8_000),
                headers: {
                  Authorization: `Bearer ${accessToken}`,
                  "Content-Type": "application/json",
                },
                body: JSON.stringify({
                  message: {
                    token: device.token,
                    data: {
                      conversation_id: job.conversation_id ?? "",
                      message_id: job.reaction_message_id ?? job.message_id ??
                        "",
                      friend_request_id: job.friend_request_id ?? "",
                      notification_type: job.notification_type,
                      recipient_id: job.recipient_user_id,
                      sender_id: job.sender_id,
                      sender_name: job.sender_name,
                      content_type: job.message_type,
                      message_text: job.message_text.slice(0, 500),
                      sent_at: job.message_created_at,
                    },
                    android: { priority: "HIGH", ttl: `${ttl}s` },
                  },
                }),
              },
            );
            let code = "";
            if (response.status === 401) {
              deps.invalidateAuthorization?.(accessToken);
            }
            if (!response.ok) {
              const body = await response.json().catch(() => null) as
                | FcmError
                | null;
              const details = body?.error?.details;
              code = (Array.isArray(details)
                ? details.find((detail) =>
                  detail["@type"] ===
                    "type.googleapis.com/google.firebase.fcm.v1.FcmError"
                )?.errorCode
                : "") ?? "";
              if (!code) {
                code = body?.error?.status ?? "";
              }
            }
            const invalid = code === "UNREGISTERED" ||
              code === "SENDER_ID_MISMATCH";
            const retry = !response.ok && !invalid &&
              (response.status === 429 || response.status >= 500 ||
                response.status === 401);
            return {
              result: {
                device_id: device.id,
                token: device.token,
                outcome: response.ok
                  ? "accepted"
                  : invalid
                  ? "invalid"
                  : retry
                  ? "retry"
                  : "failed",
              } as Result,
              retryAfter: retry
                ? parseRetryAfter(response.headers.get("Retry-After"), now())
                : 0,
              error: response.ok || invalid
                ? null
                : `FCM ${response.status} ${code}`,
            };
          } catch {
            return {
              result: {
                device_id: device.id,
                token: device.token,
                outcome: "retry",
              } as Result,
              error: "fcm_transport_failed",
              retryAfter: 0,
            };
          }
        }));
        for (const delivery of deliveries) {
          results.push(delivery.result);
          retrySeconds = Math.max(retrySeconds, delivery.retryAfter ?? 0);
          failure ??= delivery.error ?? null;
        }
      } catch {
        failure = "firebase_auth_failed";
        results.push(
          ...devices.map((device) => ({
            device_id: device.id,
            token: device.token,
            outcome: "retry" as const,
          })),
        );
      }
      return await rpc<Completion>("finish_push_notification", {
        outbox_id: job.id,
        lease_token: job.claim_token,
        device_results: results,
        retry_delay_seconds: Math.ceil(retrySeconds + random() * 15),
        failure_reason: failure,
      });
    }
    try {
      if (payload?.retry_due !== true) {
        return Response.json(await process(id as string));
      }
      const ids = await rpc<string[]>("get_due_push_notification_ids", {
        batch_size: 20,
      });
      const outcomes: unknown[] = [];
      let cursor = 0;
      // Claim immediately before sending. Max 4 jobs / 40 FCM requests.
      await Promise.all(
        Array.from({ length: Math.min(4, ids.length) }, async () => {
          while (cursor < ids.length) {
            const next = ids[cursor++];
            try {
              outcomes.push(await process(next));
            } catch {
              outcomes.push({ status: "worker_error" });
            }
          }
        }),
      );
      return Response.json({ processed: outcomes.length, outcomes });
    } catch {
      // If DB progress cannot be saved, lease expiry recovers the job.
      // Do not expose tokens, message bodies or provider response bodies.
      return Response.json({ error: "worker_failed" }, { status: 500 });
    }
  };
}

export function parseRetryAfter(value: string | null, now: number): number {
  if (!value) return 0;
  const seconds = Number(value);
  if (Number.isFinite(seconds)) return Math.max(0, Math.ceil(seconds));
  const date = Date.parse(value);
  return Number.isFinite(date)
    ? Math.max(0, Math.ceil((date - now) / 1000))
    : 0;
}

export async function withTimeout<T>(
  promise: Promise<T>,
  milliseconds: number,
): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<T>((_, reject) => {
        timer = setTimeout(
          () => reject(new Error("operation_timeout")),
          milliseconds,
        );
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}
