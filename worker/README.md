# DrishtiBution geo Worker

This Worker replaces the Firebase callable `searchResourcesByIntent` handler while leaving Firestore rules, indexes, and documents unchanged. It accepts a `POST` body in the callable-compatible form `{ "data": { "intent": ..., "limit": ..., "origin": ..., "radiusKm": ... } }` and returns the same successful response fields.

## Configure and deploy

Set the Firebase project ID in `wrangler.toml`, then store the service-account credentials as Worker secrets:

```bash
npx wrangler secret put FIREBASE_CLIENT_EMAIL
npx wrangler secret put FIREBASE_PRIVATE_KEY
npx wrangler deploy
```

The geo handler had no Firebase Function environment variables. The three secrets above are required only because the Worker authenticates to the Firestore REST API instead of using the Firebase Admin SDK. The REST helper uses `FIREBASE_CLIENT_EMAIL` and `FIREBASE_PRIVATE_KEY` to mint a short-lived Google OAuth token, then reads clean `organizations` documents. Its commit primitive is available for future Firestore writes.

Run the parity test with `npm test` from this directory. `npx wrangler dev` runs the Worker locally.