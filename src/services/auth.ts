import type { SessaoUsuario } from "@/types";
import { requireSupabase } from "@/lib/supabase";

export const authService = {
  async entrar(email: string, senha: string): Promise<SessaoUsuario> {
    const client = requireSupabase();
    const { data, error } = await client.auth.signInWithPassword({ email, password: senha });
    if (error) throw error;
    if (!data.user) throw new Error("Não foi possível autenticar.");
    const { data: active, error: activeError } = await client.rpc("sigo_is_active");
    if (activeError || !active) {
      await client.auth.signOut();
      throw new Error("Usuário sem permissão ativa no SIGO. Solicite acesso ao administrador.");
    }
    const { data: profile } = await client.from("profiles").select("nome").eq("id", data.user.id).single();
    return { nome: profile?.nome || email.split("@")[0] || "Operador", email };
  },

  async recuperarSenha(email: string): Promise<void> {
    if (!email) throw new Error("Informe o e-mail para recuperar a senha.");
    const redirectTo = typeof window !== "undefined" ? window.location.origin : undefined;
    const { error } = await requireSupabase().auth.resetPasswordForEmail(email, { redirectTo });
    if (error) throw error;
  },

  async sair(): Promise<void> {
    const { error } = await requireSupabase().auth.signOut();
    if (error) throw error;
  },

  async sessaoAtual(): Promise<SessaoUsuario | null> {
    const client = requireSupabase();
    const { data: { user }, error } = await client.auth.getUser();
    if (error || !user?.email) return null;
    const { data: active, error: activeError } = await client.rpc("sigo_is_active");
    if (activeError || !active) return null;
    const { data: profile } = await client.from("profiles").select("nome").eq("id", user.id).single();
    return { nome: profile?.nome || user.email.split("@")[0] || "Operador", email: user.email };
  },
};
