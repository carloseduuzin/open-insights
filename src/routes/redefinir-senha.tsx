import { useEffect, useState } from "react";
import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { authService } from "@/services/auth";
import { requireSupabase } from "@/lib/supabase";

export const Route = createFileRoute("/redefinir-senha")({
  component: RedefinirSenha,
});

function RedefinirSenha() {
  const navigate = useNavigate();
  const [senha, setSenha] = useState("");
  const [confirmacao, setConfirmacao] = useState("");
  const [autorizado, setAutorizado] = useState(false);
  const [carregando, setCarregando] = useState(true);
  const [salvando, setSalvando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    let mounted = true;
    const client = requireSupabase();
    const { data: listener } = client.auth.onAuthStateChange((event) => {
      if (event === "PASSWORD_RECOVERY" && mounted) {
        setAutorizado(true);
        setCarregando(false);
      }
    });
    // Recovery links may have been exchanged for a session before this component mounted.
    // A session alone does not authorize password reset in this screen.
    const timeout = window.setTimeout(() => {
      if (mounted) setCarregando(false);
    }, 2000);
    return () => {
      mounted = false;
      window.clearTimeout(timeout);
      listener.subscription.unsubscribe();
    };
  }, []);

  async function salvar(e: React.FormEvent) {
    e.preventDefault();
    setErro(null);
    if (senha !== confirmacao) {
      setErro("As senhas não coincidem.");
      return;
    }
    setSalvando(true);
    try {
      if (!autorizado) throw new Error("Link de recuperação inválido ou expirado.");
      await authService.definirNovaSenha(senha);
      await authService.sair();
      navigate({ to: "/" });
    } catch (error) {
      setErro(error instanceof Error ? error.message : "Não foi possível redefinir a senha.");
    } finally {
      setSalvando(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-background px-4">
      <form onSubmit={salvar} className="w-full max-w-md space-y-5 rounded-2xl border border-border bg-card p-6">
        <div className="flex items-center gap-3">
          <ShieldCheck className="size-7 text-primary" />
          <h1 className="text-xl font-semibold">Redefinir senha do SIGO</h1>
        </div>
        {carregando ? <p className="text-sm text-muted-foreground">Validando link de recuperação...</p> :
          !autorizado ? <p role="alert" className="text-sm text-destructive">Link de recuperação inválido ou expirado. Solicite outro na página de login.</p> : (
            <>
              <div className="space-y-2">
                <Label htmlFor="nova-senha">Nova senha (mínimo 12 caracteres)</Label>
                <Input id="nova-senha" type="password" autoComplete="new-password" value={senha} onChange={(e) => setSenha(e.target.value)} required minLength={12} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="confirmacao">Confirme a nova senha</Label>
                <Input id="confirmacao" type="password" autoComplete="new-password" value={confirmacao} onChange={(e) => setConfirmacao(e.target.value)} required minLength={12} />
              </div>
              {erro && <p role="alert" className="text-sm text-destructive">{erro}</p>}
              <Button type="submit" disabled={salvando} className="w-full">{salvando ? "Salvando..." : "Atualizar senha"}</Button>
            </>
          )}
        <Link to="/" className="block text-center text-sm text-primary">Voltar ao login</Link>
      </form>
    </div>
  );
}
