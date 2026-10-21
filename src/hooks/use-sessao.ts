import { useEffect, useState } from "react";
import { authService } from "@/services/auth";
import { supabase } from "@/lib/supabase";
import type { SessaoUsuario } from "@/types";

export function useSessao() {
  const [sessao, setSessao] = useState<SessaoUsuario | null>(null);
  const [carregando, setCarregando] = useState(true);

  useEffect(() => {
    let ativo = true;
    const atualizar = async () => {
      try {
        const atual = await authService.sessaoAtual();
        if (ativo) setSessao(atual);
      } catch {
        if (ativo) setSessao(null);
      } finally {
        if (ativo) setCarregando(false);
      }
    };
    void atualizar();
    const { data: listener } = supabase?.auth.onAuthStateChange((evento) => {
      if (evento === "SIGNED_OUT") {
        if (ativo) {
          setSessao(null);
          setCarregando(false);
        }
      } else if (evento === "SIGNED_IN" || evento === "TOKEN_REFRESHED") {
        // Avoid awaiting Supabase calls inside the auth event callback.
        queueMicrotask(() => { if (ativo) void atualizar(); });
      }
    }) ?? { data: { subscription: null } };
    return () => {
      ativo = false;
      listener.subscription?.unsubscribe();
    };
  }, []);

  return { sessao, carregando, setSessao };
}
