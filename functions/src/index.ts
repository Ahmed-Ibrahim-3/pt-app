import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret, defineString} from "firebase-functions/params";
import crypto from "crypto";
/* eslint-disable max-len */
/* eslint-disable require-jsdoc */

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
const API_NINJAS_KEY = defineSecret("API_NINJAS_KEY");

const FS_OAUTH2_CLIENT_ID = defineSecret("FS_OAUTH2_CLIENT_ID");
const FS_OAUTH2_CLIENT_SECRET = defineSecret("FS_OAUTH2_CLIENT_SECRET");
const FS_OAUTH1_CONSUMER_KEY = defineSecret("FS_OAUTH1_CONSUMER_KEY");
const FS_OAUTH1_CONSUMER_SECRET = defineSecret("FS_OAUTH1_CONSUMER_SECRET");

const FS_API_MODE = defineString("FS_API_MODE");

const REGION = "europe-west2";

function requireAuth(request: any) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }
}

// =====================================================
// GEMINI
// =====================================================
const defaultSystemInstruction = `
You are a helpful fitness & nutrition assistant. Use mainstream, trusted sports/nutrition science.
Be specific and quantitative. If the user wants a concrete meal or workout, call a function to return structured data.

MEALS
- When proposing meals, include ingredients with amounts and per-ingredient macros (kcal, protein, carbs, fat).
- Also include totals, and 2–4 small low-impact swaps (with brief macro impact).
- If the user sends a description or image of food, estimate the meal via the estimation function and include a confidence 0..1 and a brief disclaimer.

WORKOUTS
- For each exercise, provide sets, reps, RPE (0-10), optional restSeconds, and 1–3 swaps (alternatives targeting similar muscles).
- Use conservative guidance for intensity. RPE is subjective and should align with how hard the user feels the effort (0=rest, 10=max).

Avoid extreme claims; do not diagnose conditions. Keep wording concise.
`.trim();

const tools = [
  {
    functionDeclarations: [
      {
        name: "propose_meal",
        description:
          "Return a specific meal with ingredients, per-ingredient macros, totals, and low-impact swaps.",
        parametersJsonSchema: {
          type: "object",
          properties: {
            title: {type: "string"},
            ingredients: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  name: {type: "string"},
                  amount: {type: "number"},
                  unit: {type: "string"},
                  calories: {type: "number"},
                  protein: {type: "number"},
                  carbs: {type: "number"},
                  fat: {type: "number"},
                },
                required: ["name", "amount", "unit", "calories", "protein", "carbs", "fat"],
              },
            },
            totals: {
              type: "object",
              properties: {
                calories: {type: "number"},
                protein: {type: "number"},
                carbs: {type: "number"},
                fat: {type: "number"},
              },
              required: ["calories", "protein", "carbs", "fat"],
            },
            swaps: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  name: {type: "string"},
                  why: {type: "string"},
                  macroImpact: {type: "string"},
                },
                required: ["name", "why", "macroImpact"],
              },
            },
            notes: {type: "string"},
          },
          required: ["title", "ingredients", "totals", "swaps"],
        },
      },

      {
        name: "estimate_meal_from_input",
        description:
          "Estimate a meal from text and/or images. Return ingredients/macros/totals, swaps, and confidence 0..1 plus an estimation note.",
        parametersJsonSchema: {
          type: "object",
          properties: {
            title: {type: "string"},
            ingredients: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  name: {type: "string"},
                  amount: {type: "number"},
                  unit: {type: "string"},
                  calories: {type: "number"},
                  protein: {type: "number"},
                  carbs: {type: "number"},
                  fat: {type: "number"},
                },
                required: ["name", "amount", "unit", "calories", "protein", "carbs", "fat"],
              },
            },
            totals: {
              type: "object",
              properties: {
                calories: {type: "number"},
                protein: {type: "number"},
                carbs: {type: "number"},
                fat: {type: "number"},
              },
              required: ["calories", "protein", "carbs", "fat"],
            },
            swaps: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  name: {type: "string"},
                  why: {type: "string"},
                  macroImpact: {type: "string"},
                },
                required: ["name", "why", "macroImpact"],
              },
            },
            confidence: {type: "number"},
            estimationNote: {type: "string"},
            notes: {type: "string"},
          },
          required: ["title", "ingredients", "totals", "swaps", "confidence", "estimationNote"],
        },
      },

      {
        name: "propose_workout_plan",
        description:
          "Return a workout plan with exercises (sets, reps, RPE), optional restSeconds, and swaps.",
        parametersJsonSchema: {
          type: "object",
          properties: {
            name: {type: "string"},
            assignToToday: {type: "boolean"},
            notes: {type: "string"},
            exercises: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  name: {type: "string"},
                  sets: {type: "integer"},
                  reps: {type: "integer"},
                  rpe: {type: "number"},
                  restSeconds: {type: "integer"},
                  swaps: {type: "array", items: {type: "string"}},
                },
                required: ["name", "sets", "reps", "rpe"],
              },
            },
          },
          required: ["name", "exercises"],
        },
      },
    ],
  },
];

async function geminiGenerate(model: string, body: any, apiKey: string) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
  const resp = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": apiKey,
    },
    body: JSON.stringify(body),
  });

  const json = await resp.json().catch(() => ({}));
  if (!resp.ok) {
    throw new HttpsError(
      "internal",
      `Gemini error (${resp.status}): ${JSON.stringify(json).slice(0, 1000)}`
    );
  }
  return json;
}

export const geminiChat = onCall(
  {
    region: REGION,
    secrets: [GEMINI_API_KEY],
    // enforceAppCheck: true,
  },
  async (request) => {
    requireAuth(request);

    const apiKey = GEMINI_API_KEY.value();
    const model = String(request.data?.model ?? "gemini-2.0-flash");
    const fallbackModel = String(request.data?.fallbackModel ?? "gemini-2.5-flash");
    const contents = request.data?.contents;

    if (!Array.isArray(contents) || contents.length === 0) {
      throw new HttpsError("invalid-argument", "contents[] required");
    }

    const sys = String(request.data?.systemInstruction ?? defaultSystemInstruction);

    const payload = {
      systemInstruction: {parts: [{text: sys}]},
      contents,
      tools,
      toolConfig: {functionCallingConfig: {mode: "AUTO"}},
      generationConfig: {temperature: 0.2},
    };

    try {
      const json = await geminiGenerate(model, payload, apiKey);
      return simplifyGeminiResponse(json);
    } catch (e: any) {
      const msg = String(e?.message ?? e);
      if (msg.includes("503") || msg.toLowerCase().includes("overloaded")) {
        const json = await geminiGenerate(fallbackModel, payload, apiKey);
        return simplifyGeminiResponse(json);
      }
      throw e;
    }
  }
);

function simplifyGeminiResponse(json: any) {
  const cand = json?.candidates?.[0];
  const content = cand?.content ?? null;
  const parts = content?.parts ?? [];
  const text = parts.map((p: any) => p.text).filter(Boolean).join("\n").trim();

  const functionCalls = parts
    .map((p: any) => p.functionCall)
    .filter(Boolean)
    .map((fc: any) => ({
      name: String(fc.name ?? ""),
      args: fc.args ?? {},
    }));

  return {
    text: text || null,
    candidateContent: content,
    functionCalls,
  };
}

// =====================================================
// API NINJAS (Exercises)
// =====================================================
export const apiNinjasSearchExercises = onCall(
  {region: REGION, secrets: [API_NINJAS_KEY]},
  async (request) => {
    requireAuth(request);

    const key = API_NINJAS_KEY.value();
    const name = (request.data?.name ?? "").toString().trim();
    const muscle = (request.data?.muscle ?? "").toString().trim();
    const type = (request.data?.type ?? "").toString().trim();
    const difficulty = (request.data?.difficulty ?? "").toString().trim();

    const qp = new URLSearchParams();
    if (name) qp.set("name", name);
    if (muscle) qp.set("muscle", muscle);
    if (type) qp.set("type", type);
    if (difficulty) qp.set("difficulty", difficulty);

    const url = `https://api.api-ninjas.com/v1/exercises?${qp.toString()}`;
    const resp = await fetch(url, {headers: {"X-Api-Key": key}});
    const json = await resp.json().catch(() => ({}));
    if (!resp.ok) {
      throw new HttpsError("internal", `API Ninjas ${resp.status}: ${JSON.stringify(json)}`);
    }
    return json;
  }
);

// =====================================================
// FATSECRET (Food - OAuth2 preferred, OAuth1 fallback)
// =====================================================
type OAuth2TokenCache = { token: string; expiryMs: number };
let oauth2Cache: OAuth2TokenCache | null = null;

/*
get auth token via OAuth2 client credentials flow, with in-memory caching until expiry.
*/
async function fsGetOAuth2Token(): Promise<string> {
  if (oauth2Cache && Date.now() < oauth2Cache.expiryMs) return oauth2Cache.token;

  const id = FS_OAUTH2_CLIENT_ID.value();
  const secret = FS_OAUTH2_CLIENT_SECRET.value();
  if (!id || !secret) throw new HttpsError("failed-precondition", "FatSecret OAuth2 secrets missing");

  const basic = Buffer.from(`${id}:${secret}`).toString("base64");
  const body = new URLSearchParams({grant_type: "client_credentials", scope: "premier barcode"});

  const resp = await fetch("https://oauth.fatsecret.com/connect/token", {
    method: "POST",
    headers: {
      "Authorization": `Basic ${basic}`,
      "Content-Type": "application/x-www-form-urlencoded",
      "Accept": "application/json",
    },
    body,
  });

  const json = await resp.json().catch(() => ({}));
  if (!resp.ok) throw new HttpsError("internal", `FatSecret token ${resp.status}: ${JSON.stringify(json)}`);

  const token = String(json.access_token ?? "");
  const expiresIn = Number(json.expires_in ?? 3000);
  oauth2Cache = {token, expiryMs: Date.now() + Math.max(0, (expiresIn - 30) * 1000)};
  return token;
}

function fsMode(): "oauth2" | "oauth1" | "auto" {
  const m = (FS_API_MODE.value() ?? "auto").toLowerCase();
  if (m === "oauth2") return "oauth2";
  if (m === "oauth1") return "oauth1";
  return "auto";
}

async function fsOAuth2Get(path: string, params: Record<string, string>) {
  const token = await fsGetOAuth2Token();
  const qp = new URLSearchParams({format: "json", ...params});
  const url = `https://platform.fatsecret.com/rest${path.startsWith("/") ? path : "/" + path}?${qp.toString()}`;
  const resp = await fetch(url, {headers: {Authorization: `Bearer ${token}`, Accept: "application/json"}});
  const json = await resp.json().catch(() => ({}));
  if (!resp.ok) throw new HttpsError("internal", `FatSecret OAuth2 ${resp.status}: ${JSON.stringify(json)}`);
  return json;
}

async function fsOAuth2PostMethod(method: string, params: Record<string, string>) {
  const token = await fsGetOAuth2Token();
  const body = new URLSearchParams({method, format: "json", ...params});
  const resp = await fetch("https://platform.fatsecret.com/rest/server.api", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/x-www-form-urlencoded",
      "Accept": "application/json",
    },
    body,
  });
  const json = await resp.json().catch(() => ({}));
  if (!resp.ok) throw new HttpsError("internal", `FatSecret OAuth2 ${resp.status}: ${JSON.stringify(json)}`);
  return json;
}

function oauthEnc(s: string) {
  return encodeURIComponent(s)
    .replace(/[!'()*]/g, (c) => "%" + c.charCodeAt(0).toString(16).toUpperCase());
}

function oauth1Signature(httpMethod: string, baseUrl: string, params: Record<string, string>, consumerSecret: string) {
  const sorted = Object.keys(params)
    .sort()
    .map((k) => `${oauthEnc(k)}=${oauthEnc(params[k] ?? "")}`)
    .join("&");

  const base = [httpMethod.toUpperCase(), oauthEnc(baseUrl), oauthEnc(sorted)].join("&");
  const key = `${oauthEnc(consumerSecret)}&`;
  return crypto.createHmac("sha1", key).update(base).digest("base64");
}

function nonce() {
  return crypto.randomBytes(16).toString("hex");
}

async function fsOAuth1MethodGet(method: string, params: Record<string, string>) {
  const key = FS_OAUTH1_CONSUMER_KEY.value();
  const secret = FS_OAUTH1_CONSUMER_SECRET.value();
  if (!key || !secret) throw new HttpsError("failed-precondition", "FatSecret OAuth1 secrets missing");

  const baseUrl = "https://platform.fatsecret.com/rest/server.api";
  const oauthParams: Record<string, string> = {
    oauth_consumer_key: key,
    oauth_nonce: nonce(),
    oauth_signature_method: "HMAC-SHA1",
    oauth_timestamp: Math.floor(Date.now() / 1000).toString(),
    oauth_version: "1.0",
  };

  const all: Record<string, string> = {method, format: "json", ...params, ...oauthParams};
  const sig = oauth1Signature("GET", baseUrl, all, secret);

  const qp = new URLSearchParams({...all, oauth_signature: sig});
  const url = `${baseUrl}?${qp.toString()}`;

  const resp = await fetch(url, {headers: {Accept: "application/json"}});
  const json = await resp.json().catch(() => ({}));
  if (!resp.ok) throw new HttpsError("internal", `FatSecret OAuth1 ${resp.status}: ${JSON.stringify(json)}`);
  return json;
}

async function fsAuto(getOAuth2: () => Promise<any>, getOAuth1: () => Promise<any>) {
  const mode = fsMode();
  if (mode === "oauth2") return getOAuth2();
  if (mode === "oauth1") return getOAuth1();

  // auto: try oauth2, fallback oauth1
  try {
    return await getOAuth2();
  } catch {
    return await getOAuth1();
  }
}

export const fsSearchFoods = onCall({region: REGION, secrets: [FS_OAUTH2_CLIENT_ID, FS_OAUTH2_CLIENT_SECRET, FS_OAUTH1_CONSUMER_KEY, FS_OAUTH1_CONSUMER_SECRET]}, async (request) => {
  requireAuth(request);

  const q = String(request.data?.query ?? "").trim();
  const max = Number(request.data?.max ?? 20);
  const page = Number(request.data?.page ?? 0);
  if (!q) return [];

  const data = await fsAuto(
    () => fsOAuth2Get("/foods/search/v3", {search_expression: q, max_results: String(max), page_number: String(page)}),
    () => fsOAuth1MethodGet("foods.search.v2", {search_expression: q, max_results: String(max), page_number: String(page)})
  );

  const node =
    data?.foods?.food ??
    data?.foods_search?.results?.food;

  if (!node) return [];
  const list = Array.isArray(node) ? node : [node];

  return list.map((f: any) => ({
    id: String(f.food_id ?? ""),
    name: String(f.food_name ?? ""),
    type: String(f.food_type ?? ""),
  }));
});

export const fsAutocomplete = onCall({region: REGION, secrets: [FS_OAUTH2_CLIENT_ID, FS_OAUTH2_CLIENT_SECRET, FS_OAUTH1_CONSUMER_KEY, FS_OAUTH1_CONSUMER_SECRET]}, async (request) => {
  requireAuth(request);

  const expr = String(request.data?.expr ?? "").trim();
  const max = Number(request.data?.max ?? 8);
  if (!expr) return [];

  const data = await fsAuto(
    () => fsOAuth2PostMethod("foods.autocomplete", {expression: expr, max_results: String(max)}),
    () => fsOAuth1MethodGet("foods.autocomplete", {expression: expr, max_results: String(max)})
  );

  const node = data?.suggestions?.suggestion;
  if (!node) return [];
  const list = Array.isArray(node) ? node : [node];
  return list.map((x: any) => String(x));
});

export const fsGetFoodDetails = onCall({region: REGION, secrets: [FS_OAUTH2_CLIENT_ID, FS_OAUTH2_CLIENT_SECRET, FS_OAUTH1_CONSUMER_KEY, FS_OAUTH1_CONSUMER_SECRET]}, async (request) => {
  requireAuth(request);

  const foodId = String(request.data?.foodId ?? "").trim();
  if (!foodId) throw new HttpsError("invalid-argument", "foodId required");

  const data = await fsAuto(
    () => fsOAuth2Get("/food/v4", {food_id: foodId}),
    () => fsOAuth1MethodGet("food.get", {food_id: foodId})
  );

  const food = data?.food ?? {};
  const servingsNode = food?.servings?.serving;
  const raw = !servingsNode ? [] : Array.isArray(servingsNode) ? servingsNode : [servingsNode];

  return {
    id: String(food.food_id ?? ""),
    name: String(food.food_name ?? ""),
    servings: raw,
  };
});

export const fsGetFoodDetailsByBarcode = onCall({region: REGION, secrets: [FS_OAUTH2_CLIENT_ID, FS_OAUTH2_CLIENT_SECRET, FS_OAUTH1_CONSUMER_KEY, FS_OAUTH1_CONSUMER_SECRET]}, async (request) => {
  requireAuth(request);

  const rawCode = String(request.data?.rawCode ?? "").trim();
  if (!rawCode) throw new HttpsError("invalid-argument", "rawCode required");

  const digits = rawCode.replace(/\D/g, "");
  let gtin13 = digits;
  if (digits.length === 12) gtin13 = "0" + digits;
  else if (digits.length === 8) gtin13 = "00000" + digits;
  else if (digits.length !== 13) throw new HttpsError("invalid-argument", `Unsupported barcode length: ${digits.length}`);

  const region = String(request.data?.region ?? "").trim();
  const language = String(request.data?.language ?? "").trim();

  const params: Record<string, string> = {barcode: gtin13, format: "json"};
  if (region) params.region = region;
  if (language && region) params.language = language;

  const data = await fsAuto(
    () => fsOAuth2Get("/food/barcode/find-by-id/v1", params),
    () => fsOAuth1MethodGet("food.find_id_for_barcode", params)
  );

  const node = data?.food_id;
  const id = node?.value != null ? String(node.value) : String(node ?? "");
  if (!id || id === "0") throw new HttpsError("not-found", `No match for barcode ${gtin13}`);

  const details = await (fsGetFoodDetails as any).run({auth: request.auth, data: {foodId: id}});
  return details;
});
