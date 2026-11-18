import { useEffect } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { authService } from "@/services/auth";
import { supabase } from "@/lib/supabase";
import type { SessaoUsuario } from "@/types";
import { chaveSessao, opcoesSessao, sincronizarSessaoCache } from "@/lib/sessao-consulta";

export function useSessao() {
  const queryClient = useQueryClient();
  const consulta = useQuery({
    ...opcoesSessao(() => authService.sessaoAtual()),
    enabled: typeof window !== "undefined",
    refetchOnWindowFocus: true,
  });

  useEffect(() => {
    let ativo = true;
    const { data: listener } = supabase?.auth.onAuthStateChange((evento, autenticada) => {
      // Leave the auth callback before issuing any Supabase requests.
      queueMicrotask(() => {
        if (ativo) void sincronizarSessaoCache(queryClient, evento, autenticada?.user.email);
      });
    }) ?? { data: { subscription: null } };
    return () => { ativo = false; listener.subscription?.unsubscribe(); };
  }, [queryClient]);

  function setSessao(valor: SessaoUsuario | null | ((anterior: SessaoUsuario | null) => SessaoUsuario | null)) {
    queryClient.setQueryData<SessaoUsuario | null>(chaveSessao, anterior => typeof valor === "function" ? valor(anterior ?? null) : valor);
  }

  return { sessao: consulta.data ?? null, carregando: consulta.isPending, setSessao };
}
