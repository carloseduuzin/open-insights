import { createFileRoute } from "@tanstack/react-router";
import { AppShell } from "@/layout/AppShell";
import { PaginaEmConstrucao } from "@/components/PaginaEmConstrucao";

export const Route = createFileRoute("/configuracoes")({
  head: () => ({
    meta: [
      { title: "Configurações — SIGO | RenoveLog" },
      { name: "description", content: "Parâmetros do sistema, bases, usuários e permissões." },
      { property: "og:title", content: "Configurações — SIGO | RenoveLog" },
      { property: "og:description", content: "Ajustes gerais do SIGO." },
    ],
  }),
  component: () => (
    <AppShell titulo="Configurações" descricao="Parâmetros, bases e permissões">
      <PaginaEmConstrucao modulo="Configurações" />
    </AppShell>
  ),
});
