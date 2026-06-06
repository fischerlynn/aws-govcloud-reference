// Minimal health/echo handler for the HTTP API (payload format v2.0).
//
// GET  /health  -> { status: "ok", ... }
// any  /echo    -> echoes method, path, query and parsed JSON body
//
// Intentionally dependency-free so it packages with zero build step and
// runs well within the Lambda free tier.

export const handler = async (event) => {
  const http = event?.requestContext?.http ?? {};
  const method = http.method ?? "UNKNOWN";
  const path = http.path ?? "/";

  const respond = (statusCode, body) => ({
    statusCode,
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });

  if (path === "/health" || path === "/") {
    return respond(200, {
      status: "ok",
      service: process.env.SERVICE_NAME ?? "aws-govcloud-reference",
      time: new Date().toISOString(),
    });
  }

  let parsedBody = null;
  if (event?.body) {
    try {
      parsedBody = JSON.parse(event.body);
    } catch {
      parsedBody = event.body;
    }
  }

  return respond(200, {
    echo: {
      method,
      path,
      query: event?.queryStringParameters ?? {},
      body: parsedBody,
    },
    time: new Date().toISOString(),
  });
};
