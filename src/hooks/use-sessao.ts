import { useEffect, useState } from "react";
import { authService } from "@/services/auth";
import type { SessaoUsuario } from "@/types";

export function useSessao() {
  const [sessao, setSessao] = useState<SessaoUsuario | null>(null);
  const [carregando, setCarregando] = useState(true);

  useEffect(() => {
    let ativo = true;
    authService.sessaoAtual().then((value) => { if (ativo) setSessao(value); }).catch(() => { if (ativo) setSessao(null); }).finally(() => { if (ativo) setCarregando(false); });
    return () => { ativo = false; };
  }, []);

  return { sessao, carregando, setSessao };
}
