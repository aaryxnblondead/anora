# anora-push-dispatch

Starter Appwrite Function for emergency push dispatch requests coming from the backend.

## Purpose

This function receives execution payloads from the backend endpoint flow in `backend/main.py` and validates the dispatch request.

Expected payload shape:

```json
{
  "event": "emergency_alert",
  "severity": "high",
  "alert_id": "<uuid>",
  "clinician_id": "<id>",
  "tokens": ["token1", "token2"],
  "notification": {
    "title": "High-priority wellness alert",
    "body": "A linked patient may need immediate support."
  }
}
```

## Deploy in Appwrite

1. Create a function in Appwrite: `anora-push-dispatch`.
2. Select Node.js runtime.
3. Upload this folder contents.
4. Copy the function ID and set it in `backend/.env`:

`APPWRITE_PUSH_FUNCTION_ID=<function_id>`

5. Switch backend push back on:

`PUSH_PROVIDER=appwrite`

## Next integration step

Replace the TODO in `src/index.js` with real push provider delivery logic.
