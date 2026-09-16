import { useEffect, useState } from "react";
import { authService } from "@/services/auth";
import type { SessaoUsuario } from "@/types";

export function useSessao() {
  const [sessao, setSessao] = useState<SessaoUsuario | null>(null);
  const [carregando, setCarregando] = useState(true);

  useEffect(() => {
    setSessao(authService.sessaoAtual());
    setCarregando(false);
  }, []);

  return { sessao, carregando, setSessao };
}
