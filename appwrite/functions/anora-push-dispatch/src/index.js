module.exports = async ({ req, res, log, error }) => {
  const message = "Deprecated: emergency alerts now flow through PostgreSQL inbox polling in AWS.";
  if (typeof log === "function") {
    log(message);
  }
  return res.json(
    {
      ok: false,
      deprecated: true,
      message,
    },
    410
  );
};
