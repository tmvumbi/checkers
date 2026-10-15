import type { AuthConfig } from "convex/server";

// Players sign in with Firebase Auth (anonymous, Google, Apple) in project
// `checkers-club`; Convex verifies the Firebase ID token directly.
// `identity.subject` is the Firebase uid.
const FIREBASE_PROJECT_ID = "checkers-club";

export default {
  providers: [
    {
      type: "customJwt",
      applicationID: FIREBASE_PROJECT_ID,
      issuer: `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`,
      jwks: "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
      algorithm: "RS256",
    },
  ],
} satisfies AuthConfig;
