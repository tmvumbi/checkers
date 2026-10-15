import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

// Phase 0 schema: only what the Flutter client spike needs. The full port of
// the Supabase tables (supabase/migrations/) lands in Phase 2.
export default defineSchema({
  spikeCounters: defineTable({
    authSubject: v.string(),
    value: v.number(),
    updatedAt: v.number(),
  }).index("by_auth_subject", ["authSubject"]),
});
