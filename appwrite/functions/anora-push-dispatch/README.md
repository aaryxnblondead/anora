# anora-push-dispatch

Deprecated historical stub for the old emergency alert dispatch path.

This folder is kept only as historical reference. The backend now stores emergency alerts in PostgreSQL and the clinician app polls the inbox directly.

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

## Status

Do not deploy this function for the current version of Anora.

If you are migrating an older environment, archive this folder after confirming the backend and clinician inbox polling flow are working in your deployed backend.
