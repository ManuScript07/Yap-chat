type Dependencies = {
  supabaseUrl?: string;
  serviceRoleKey?: string;
  fetch?: typeof fetch;
  quotaTimeoutMs?: number;
  upstreamTimeoutMs?: number;
  now?: () => number;
};
type YandexUser = {
  id: string;
  login?: string | null;
  default_email?: string | null;
  emails?: string[] | null;
  display_name?: string | null;
  real_name?: string | null;
  birthday?: string | null;
  default_avatar_id?: string | null;
  is_avatar_empty?: boolean | null;
  default_phone?: { number?: string | null } | null;
};
const encoder = new TextEncoder();
const tokenPattern = /^(Bearer|OAuth) +([A-Za-z0-9._~+/-]+=*)$/i;
const yandexUrl = "https://login.yandex.ru/info?format=json";

/** The same handler is used by the deployed function and offline tests. */
export function createYandexUserInfoHandler(deps: Dependencies) {
  const send = deps.fetch ?? fetch;
  const now = deps.now ?? (() => performance.now());
  // These bounded, isolate-local caches only reject: admission always uses SQL.
  const deniedTokens = new Map<string, number>();
  let globallyDeniedUntil = 0;
  let unavailableUntil = 0;
  let quotaInFlight = 0;
  let signingKey: Promise<CryptoKey> | undefined;
  return async (request: Request): Promise<Response> => {
    if (request.method !== "GET") {
      return json({ error: "method_not_allowed" }, 405, { Allow: "GET" });
    }
    let headerBytes = 0;
    for (const [name, value] of request.headers) {
      headerBytes += encoder.encode(name + value).byteLength;
    }
    if (headerBytes > 8192 || request.url.length > 2048) {
      return json({ error: "request_too_large" }, 431);
    }
    if (
      request.body !== null || request.headers.has("transfer-encoding") ||
      (request.headers.has("content-length") &&
        request.headers.get("content-length") !== "0") ||
      new URL(request.url).search !== ""
    ) {
      return json({ error: "invalid_request" }, 400);
    }
    const authorization = request.headers.get("authorization");
    if (!authorization) {
      return json({ error: "missing_access_token" }, 401);
    }
    const match = tokenPattern.exec(authorization);
    if (!match || match[2].length > 4096) {
      return json({ error: "invalid_access_token" }, 401);
    }
    if (!deps.supabaseUrl || !deps.serviceRoleKey) {
      return json({ error: "server_not_configured" }, 503);
    }
    if (request.signal.aborted || unavailableUntil > now()) {
      return json({ error: "yandex_userinfo_unavailable" }, 503);
    }
    if (globallyDeniedUntil > now()) {
      return rateLimited(globallyDeniedUntil - now());
    }
    const accessToken = match[2];
    try {
      // Domain separation; only the HMAC fingerprint reaches the database.
      // Reuse the existing server credential; no new client secret/config needed.
      signingKey ??= crypto.subtle.importKey(
        "raw",
        encoder.encode(deps.serviceRoleKey),
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign"],
      );
      const signature = await crypto.subtle.sign(
        "HMAC",
        await signingKey,
        encoder.encode("yandex-userinfo:v1:" + accessToken),
      );
      const tokenHash = Array.from(
        new Uint8Array(signature),
        (byte) => byte.toString(16).padStart(2, "0"),
      ).join("");
      const deniedUntil = deniedTokens.get(tokenHash) ?? 0;
      if (deniedUntil > now()) return rateLimited(deniedUntil - now());
      deniedTokens.delete(tokenHash);
      // Re-check after asynchronous hashing, before issuing any database work.
      if (globallyDeniedUntil > now()) {
        return rateLimited(globallyDeniedUntil - now());
      }
      if (unavailableUntil > now() || quotaInFlight >= 64) {
        return json({ error: "yandex_userinfo_unavailable" }, 503);
      }
      quotaInFlight++;
      let quota: Record<string, unknown>;
      try {
        quota = await deadline(
          async (signal) => {
            const response = await send(
              deps.supabaseUrl!.replace(/\/$/, "") +
                "/rest/v1/rpc/consume_yandex_userinfo_quota",
              {
                method: "POST",
                redirect: "error",
                signal,
                headers: {
                  apikey: deps.serviceRoleKey!,
                  Authorization: "Bearer " + deps.serviceRoleKey!,
                  "Content-Type": "application/json",
                },
                body: JSON.stringify({ token_hash: tokenHash }),
              },
            );
            if (!response.ok) {
              void response.body?.cancel().catch(() => {});
              throw new Error("quota_unavailable");
            }
            const value = await readJson(response, 1024, signal);
            if (
              !record(value) || typeof value.allowed !== "boolean" ||
              !Number.isInteger(value.retry_after_seconds) ||
              (value.retry_after_seconds as number) < 0 ||
              (value.retry_after_seconds as number) > 60 ||
              (!value.allowed && value.retry_after_seconds === 0) ||
              (value.scope != null && value.scope !== "token" &&
                value.scope !== "global")
            ) throw new Error("invalid_quota_response");
            return value;
          },
          deps.quotaTimeoutMs ?? 1500,
          request.signal,
        );
      } finally {
        quotaInFlight--;
      }
      if (!quota.allowed) {
        const until = now() + (quota.retry_after_seconds as number) * 1000;
        if (quota.scope === "global") {
          globallyDeniedUntil = Math.max(globallyDeniedUntil, until);
        } else {
          // Fixed memory bound even if an attacker constantly rotates tokens.
          if (deniedTokens.size >= 1024) {
            deniedTokens.delete(deniedTokens.keys().next().value!);
          }
          deniedTokens.set(tokenHash, until);
        }
        return rateLimited(until - now());
      }
    } catch {
      // Brief shedding during database outages; client cancellation must not
      // open this breaker for other users. No retries, timers or connections.
      if (!request.signal.aborted) unavailableUntil = now() + 1000;
      return json({ error: "yandex_userinfo_unavailable" }, 503);
    }

    try {
      return await deadline(
        async (signal) => {
          const response = await send(yandexUrl, {
            headers: { Authorization: "OAuth " + accessToken },
            redirect: "error",
            signal,
          });
          if (!response.ok) {
            void response.body?.cancel().catch(() => {});
            const status = response.status === 401 || response.status === 403
              ? response.status
              : response.status === 429
              ? 503
              : 502;
            return json({ error: "yandex_userinfo_failed" }, status);
          }
          const user = await readJson(response, 16384, signal);
          if (!isYandexUser(user)) {
            return json({ error: "invalid_yandex_userinfo" }, 502);
          }
          const avatarUrl =
            user.is_avatar_empty === false && user.default_avatar_id
              ? `https://avatars.yandex.net/get-yapic/${user.default_avatar_id}/islands-200`
              : null;
          const email = user.default_email ?? user.emails?.[0] ?? null;
          const phoneNumber = user.default_phone?.number?.trim() || null;
          return json({
            sub: user.id,
            id: user.id,
            email,
            email_verified: email !== null,
            name: user.real_name ?? user.display_name ?? user.login ?? null,
            preferred_username: user.login ?? null,
            picture: avatarUrl,
            birthdate: user.birthday ?? null,
            birthday: user.birthday ?? null,
            phone: phoneNumber,
            phone_verified: phoneNumber !== null,
            phone_number: phoneNumber,
            phone_number_verified: phoneNumber !== null,
          });
        },
        deps.upstreamTimeoutMs ?? 5000,
        request.signal,
      );
    } catch (error) {
      return json({
        error: error instanceof DeadlineError
          ? "yandex_userinfo_timeout"
          : "yandex_userinfo_failed",
      }, error instanceof DeadlineError ? 504 : 502);
    }
  };
}

function rateLimited(remainingMs: number) {
  return json({ error: "yandex_userinfo_rate_limited" }, 429, {
    "Retry-After": String(Math.max(1, Math.ceil(remainingMs / 1000))),
  });
}

function json(body: Record<string, unknown>, status = 200, extra = {}) {
  return Response.json(body, {
    status,
    headers: { "Cache-Control": "no-store", ...extra },
  });
}
function record(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function isYandexUser(value: unknown): value is YandexUser {
  if (!record(value) || typeof value.id !== "string" || !value.id.trim()) {
    return false;
  }
  for (
    const field of [
      "login",
      "default_email",
      "display_name",
      "real_name",
      "birthday",
      "default_avatar_id",
    ]
  ) {
    if (value[field] != null && typeof value[field] !== "string") return false;
  }
  return (value.emails == null ||
    (Array.isArray(value.emails) &&
      value.emails.every((email) => typeof email === "string"))) &&
    (value.is_avatar_empty == null ||
      typeof value.is_avatar_empty === "boolean") &&
    (value.default_phone == null ||
      (record(value.default_phone) &&
        (value.default_phone.number == null ||
          typeof value.default_phone.number === "string")));
}

async function readJson(
  response: Response,
  maxBytes: number,
  signal: AbortSignal,
): Promise<unknown> {
  const length = Number(response.headers.get("content-length") ?? 0);
  if (length > maxBytes || !response.body) {
    void response.body?.cancel().catch(() => {});
    throw new Error("invalid_response_size");
  }
  const reader = response.body.getReader();
  const cancel = () => {
    void reader.cancel().catch(() => {});
  };
  if (signal.aborted) cancel();
  else signal.addEventListener("abort", cancel, { once: true });
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxBytes) throw new Error("response_too_large");
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } finally {
    signal.removeEventListener("abort", cancel);
    cancel();
  }
}

class DeadlineError extends Error {}
async function deadline<T>(
  operation: (signal: AbortSignal) => Promise<T>,
  timeoutMs: number,
  parent: AbortSignal,
): Promise<T> {
  if (parent.aborted) throw new DeadlineError();
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  let abort: () => void = () => {};
  const cancelled = new Promise<never>((_, reject) => {
    abort = () => {
      controller.abort();
      reject(new DeadlineError());
    };
    if (parent.aborted) abort();
    else parent.addEventListener("abort", abort, { once: true });
    timer = setTimeout(abort, timeoutMs);
  });
  try {
    return await Promise.race([cancelled, operation(controller.signal)]);
  } finally {
    clearTimeout(timer);
    parent.removeEventListener("abort", abort);
  }
}
