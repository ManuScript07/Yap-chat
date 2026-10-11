import { JWT } from "npm:google-auth-library@9";
import { createClient } from "npm:@supabase/supabase-js@2";
import { createPushHandler, withTimeout } from "./worker.ts";

const secret = Deno.env.get("PUSH_WEBHOOK_SECRET");
const url = Deno.env.get("SUPABASE_URL");
const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const accountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
let cachedToken: { value: string; expires: number } | undefined;
let tokenRequest: Promise<void> | undefined;

Deno.serve(createPushHandler({
  secret,
  configured: Boolean(url && key && accountJson),
  invalidateAuthorization: (accessToken) => {
    if (cachedToken?.value === accessToken) cachedToken = undefined;
  },
  createAdmin: () =>
    createClient(url!, key!, {
      auth: { autoRefreshToken: false, persistSession: false },
      global: {
        fetch: (input, init) =>
          fetch(input, {
            ...init,
            signal: AbortSignal.timeout(10_000),
          }),
      },
    }),
  authorize: async () => {
    const account = JSON.parse(accountJson!) as {
      project_id: string;
      client_email: string;
      private_key: string;
    };
    if (!account.project_id || !account.client_email || !account.private_key) {
      throw new Error("invalid_firebase_configuration");
    }
    if (!cachedToken || cachedToken.expires <= Date.now()) {
      // Concurrent jobs in a recovery batch share the same OAuth request.
      tokenRequest ??= (async () => {
        const client = new JWT({
          email: account.client_email,
          key: account.private_key.replace(/\\n/g, "\n"),
          scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
        });
        const credentials = await withTimeout(client.authorize(), 10_000);
        if (!credentials.access_token) throw new Error("missing_access_token");
        cachedToken = {
          value: credentials.access_token,
          expires: (credentials.expiry_date ?? Date.now() + 60_000) - 30_000,
        };
      })();
      try {
        await tokenRequest;
      } finally {
        tokenRequest = undefined;
      }
    }
    return { projectId: account.project_id, accessToken: cachedToken!.value };
  },
}));
