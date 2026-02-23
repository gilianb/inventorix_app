import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const CARDTRADER_BASE_URL = "https://api.cardtrader.com/api/v2";

interface ProxyRequestBody {
  blueprintId?: unknown;
  languageParam?: unknown;
}

function json(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json",
    },
  });
}

function asText(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function parseBlueprintId(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value > 0 ? Math.trunc(value) : null;
  }
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed) && parsed > 0) {
      return Math.trunc(parsed);
    }
  }
  return null;
}

function parseListingsByBlueprint(
  payload: unknown,
  blueprintId: number,
): Array<Record<string, unknown>> {
  if (!payload || typeof payload !== "object") return [];
  const map = payload as Record<string, unknown>;
  const bucket = map[String(blueprintId)];
  if (!Array.isArray(bucket)) return [];
  const out: Array<Record<string, unknown>> = [];
  for (const entry of bucket) {
    if (!entry || typeof entry !== "object") continue;
    out.push(entry as Record<string, unknown>);
  }
  return out;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const cardTraderToken = (Deno.env.get("CARDTRADER_TOKEN") ?? "").trim();
  if (!cardTraderToken) {
    return json(
      { error: "CARDTRADER_TOKEN secret is not configured." },
      500,
    );
  }

  let body: ProxyRequestBody = {};
  try {
    body = (await req.json()) as ProxyRequestBody;
  } catch {
    return json({ error: "Invalid JSON body." }, 400);
  }

  const blueprintId = parseBlueprintId(body.blueprintId);
  if (blueprintId === null) {
    return json({ error: "blueprintId must be a positive integer." }, 400);
  }

  const url = new URL(`${CARDTRADER_BASE_URL}/marketplace/products`);
  url.searchParams.set("blueprint_id", String(blueprintId));
  const language = asText(body.languageParam).trim().toLowerCase();
  if (language) {
    url.searchParams.set("language", language);
  }

  try {
    const upstream = await fetch(url.toString(), {
      headers: {
        Authorization: `Bearer ${cardTraderToken}`,
        Accept: "application/json",
      },
    });

    if (!upstream.ok) {
      const bodyText = (await upstream.text()).slice(0, 300);
      const reason = upstream.status === 401
        ? "CardTrader 401 (token invalid or expired)"
        : `CardTrader HTTP ${upstream.status}`;
      return json(
        {
          error: bodyText ? `${reason} - ${bodyText}` : reason,
        },
        502,
      );
    }

    const payload = await upstream.json();
    const listings = parseListingsByBlueprint(payload, blueprintId);
    return json({
      blueprintId,
      listings,
      listingsCount: listings.length,
    });
  } catch (error) {
    return json(
      {
        error: error instanceof Error
          ? error.message
          : "CardTrader proxy request failed.",
      },
      502,
    );
  }
});
