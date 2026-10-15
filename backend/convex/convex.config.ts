import { defineApp } from "convex/server";
import { v } from "convex/values";

// Deployment env vars (set with `npx convex env set NAME value`). All are
// optional so a fresh deployment works; features needing one no-op
// without it, as the Vault-backed SQL triggers did.
const app = defineApp({
  env: {
    // Resend key for feedback emails (was Vault `resend_api_key`).
    RESEND_API_KEY: v.optional(v.string()),
    FEEDBACK_EMAIL_TO: v.optional(v.string()),
    // checkers-push Cloudflare Worker (was Vault push_relay_url/key).
    PUSH_RELAY_URL: v.optional(v.string()),
    PUSH_RELAY_KEY: v.optional(v.string()),
    // Shared secret the admin console worker sends to /admin/* HTTP actions.
    ADMIN_API_SECRET: v.optional(v.string()),
    // Legacy Supabase GoTrue, used only to verify account-claim handoffs.
    SUPABASE_LEGACY_URL: v.optional(v.string()),
    SUPABASE_LEGACY_ANON_KEY: v.optional(v.string()),
    // "yes" lets migration:wipe empty the deployment (rehearsals only).
    MIGRATION_ALLOW_WIPE: v.optional(v.string()),
  },
});

export default app;
