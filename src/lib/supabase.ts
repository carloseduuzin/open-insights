import { createClient } from "@supabase/supabase-js";

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined;

// Never create a persistent auth client in the server runtime: a module singleton
// could accidentally share a session between SSR requests.
export const supabase = typeof window !== "undefined" && url && key
  ? createClient(url, key, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
    })
  : null;

export function requireSupabase() {
  if (!supabase) throw new Error("Supabase não configurado. Verifique as variáveis VITE_SUPABASE_URL e VITE_SUPABASE_PUBLISHABLE_KEY.");
  return supabase;
}
