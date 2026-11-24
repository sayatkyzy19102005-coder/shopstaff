import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

let cachedApiKey = '';

async function resolveGeminiKey(): Promise<string> {
  if (cachedApiKey) return cachedApiKey;

  // 1. Проверяем секрет GEMINI_API_KEY в Supabase Edge Functions -> Secrets
  const envKey = Deno.env.get('GEMINI_API_KEY')?.trim();
  if (envKey) {
    cachedApiKey = envKey;
    return envKey;
  }

  // 2. Автоматический резерв: берём сохранённый ключ из таблицы profiles в вашей БД Supabase
  const sbUrl = Deno.env.get('SUPABASE_URL') || 'https://zpmapedzbbrfxlmuncbd.supabase.co';
  const sbServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_ANON_KEY') || '';
  if (sbUrl && sbServiceKey) {
    try {
      const sb = createClient(sbUrl, sbServiceKey);
      const { data } = await sb
        .from('profiles')
        .select('address')
        .eq('id', '00000000-0000-0000-0000-000000000099')
        .maybeSingle();
      if (data?.address) {
        cachedApiKey = String(data.address).trim();
        return cachedApiKey;
      }
    } catch (_) {}
  }
  return '';
}

async function callModel(url: string, payload: unknown, timeoutMs = 6500): Promise<string> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      throw new Error(data?.error?.message || `HTTP ${res.status}`);
    }
    const reply = data?.candidates?.[0]?.content?.parts
      ?.map((p: { text?: string }) => p.text || '')
      .join('')
      .trim();
    if (!reply) throw new Error('Empty reply');
    return reply;
  } finally {
    clearTimeout(timer);
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const apiKey = await resolveGeminiKey();
    if (!apiKey) {
      return new Response(
        JSON.stringify({ error: 'Секрет GEMINI_API_KEY не найден в Supabase' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const { systemPrompt, history } = await req.json();

    const payload = {
      systemInstruction: { parts: [{ text: systemPrompt || '' }] },
      contents: (history || []).slice(-8),
      generationConfig: { temperature: 0.35, maxOutputTokens: 550 },
    };

    const encodedKey = encodeURIComponent(apiKey);
    // Используем generativelanguage.googleapis.com (работает бесплатно с ключами AQ.... и AIzaSy... без включения Billing и Vertex AI!)
    const fastModels = [
      'gemini-3.8-flash',
      'gemini-3.1-flash-lite',
      'gemini-flash-lite-latest'
    ];
    const endpoints = fastModels.map(
      (m) => `https://generativelanguage.googleapis.com/v1beta/models/${m}:generateContent?key=${encodedKey}`
    );

    const reply = await Promise.any(endpoints.map((url) => callModel(url, payload, 6500)));

    return new Response(
      JSON.stringify({ reply }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
