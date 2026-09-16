import { useState } from "react";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { KeyRound, LogIn, ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { authService } from "@/services/auth";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Entrar — SIGO | RenoveLog Operations" },
      {
        name: "description",
        content:
          "Acesse o SIGO, sistema integrado de gestão operacional da RenoveLog: rotas, prestadores, romaneios e indicadores.",
      },
      { property: "og:title", content: "Entrar — SIGO | RenoveLog Operations" },
      {
        property: "og:description",
        content: "Sistema Integrado de Gestão Operacional da RenoveLog.",
      },
    ],
  }),
  component: Login,
});

function Login() {
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [erro, setErro] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [carregando, setCarregando] = useState(false);

  async function entrar(e: React.FormEvent) {
    e.preventDefault();
    setErro(null);
    setAviso(null);
    setCarregando(true);
    try {
      await authService.entrar(email, senha);
      navigate({ to: "/dashboard" });
    } catch (err) {
      setErro(err instanceof Error ? err.message : "Não foi possível entrar.");
    } finally {
      setCarregando(false);
    }
  }

  async function recuperar() {
    setErro(null);
    try {
      await authService.recuperarSenha(email);
      setAviso("Se o e-mail existir, enviaremos as instruções de recuperação.");
    } catch (err) {
      setErro(err instanceof Error ? err.message : "Erro ao recuperar senha.");
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-background px-4 py-10">
      <div className="w-full max-w-md">
        <div className="mb-8 text-center">
          <div className="mx-auto mb-5 flex size-14 items-center justify-center rounded-2xl bg-primary text-primary-foreground shadow-[var(--shadow-glow)]">
            <ShieldCheck className="size-7" />
          </div>
          <h1 className="text-4xl font-semibold tracking-[0.2em]">SIGO</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Sistema Integrado de Gestão Operacional
          </p>
        </div>

        <form
          onSubmit={entrar}
          className="space-y-5 rounded-2xl border border-border bg-card p-6 shadow-[var(--shadow-elevated)]"
        >
          <div className="space-y-2">
            <Label htmlFor="email">E-mail</Label>
            <Input
              id="email"
              type="email"
              autoComplete="email"
              placeholder="operacao@renovelog.com.br"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="senha">Senha</Label>
            <Input
              id="senha"
              type="password"
              autoComplete="current-password"
              placeholder="••••••••"
              value={senha}
              onChange={(e) => setSenha(e.target.value)}
            />
          </div>

          {erro && <p className="text-sm text-destructive">{erro}</p>}
          {aviso && <p className="text-sm text-success">{aviso}</p>}

          <div className="space-y-2">
            <Button type="submit" className="w-full" disabled={carregando}>
              <LogIn className="size-4" />
              {carregando ? "Entrando..." : "Entrar"}
            </Button>
            <Button type="button" variant="ghost" className="w-full" onClick={recuperar}>
              <KeyRound className="size-4" />
              Recuperar senha
            </Button>
          </div>
        </form>

        <p className="mt-6 text-center text-xs text-muted-foreground">
          SIGO v1.0 — RenoveLog Operations
        </p>
      </div>
    </div>
  );
}
