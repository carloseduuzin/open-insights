import type { SessaoUsuario } from "@/types";

const STORAGE_KEY = "sigo.sessao";

/**
 * Autenticação mock. Preparada para troca por Supabase:
 * basta substituir os corpos das funções por chamadas ao client.
 */
export const authService = {
  async entrar(email: string, senha: string): Promise<SessaoUsuario> {
    await new Promise((r) => setTimeout(r, 500));
    if (!email || !senha) throw new Error("Informe e-mail e senha.");
    const sessao: SessaoUsuario = { nome: email.split("@")[0] ?? "Operador", email };
    localStorage.setItem(STORAGE_KEY, JSON.stringify(sessao));
    return sessao;
  },

  async recuperarSenha(email: string): Promise<void> {
    await new Promise((r) => setTimeout(r, 400));
    if (!email) throw new Error("Informe o e-mail para recuperar a senha.");
  },

  sair() {
    localStorage.removeItem(STORAGE_KEY);
  },

  sessaoAtual(): SessaoUsuario | null {
    if (typeof window === "undefined") return null;
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? (JSON.parse(raw) as SessaoUsuario) : null;
  },
};
