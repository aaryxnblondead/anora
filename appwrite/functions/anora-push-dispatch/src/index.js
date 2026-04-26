module.exports = async ({ req, res, log, error }) => {
  try {
    const raw = req.bodyRaw || req.body || "{}";
    const parsed = typeof raw === "string" ? JSON.parse(raw) : raw;

    const tokens = Array.isArray(parsed.tokens) ? parsed.tokens.filter(Boolean) : [];
    const title = parsed.notification?.title || "High-priority wellness alert";
    const body = parsed.notification?.body || "A linked patient may need immediate support.";

    if (tokens.length === 0) {
      return res.json(
        {
          ok: false,
          reason: "no_tokens",
          received: {
            alert_id: parsed.alert_id || null,
            clinician_id: parsed.clinician_id || null,
          },
        },
        200
      );
    }

    // TODO: Integrate your real push provider here (FCM / OneSignal / APNs / etc).
    // This starter only validates and echoes the dispatch request.
    log(`Push dispatch request accepted for ${tokens.length} token(s).`);

    return res.json(
      {
        ok: true,
        simulated: true,
        dispatched_count: tokens.length,
        notification: { title, body },
        event: parsed.event || "emergency_alert",
        alert_id: parsed.alert_id || null,
        clinician_id: parsed.clinician_id || null,
      },
      200
    );
  } catch (err) {
    error(`Push dispatch function error: ${err?.message || err}`);
    return res.json(
      {
        ok: false,
        reason: "invalid_payload",
        error: err?.message || "Failed to parse payload",
      },
      400
    );
  }
};
