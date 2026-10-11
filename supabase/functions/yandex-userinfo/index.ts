import { createYandexUserInfoHandler } from "./handler.ts";

// Auth sends a Yandex credential, not a Supabase JWT. Keep verify_jwt=false.
Deno.serve(createYandexUserInfoHandler({
  supabaseUrl: Deno.env.get("SUPABASE_URL"),
  serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
}));
