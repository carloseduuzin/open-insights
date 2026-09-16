import { createFileRoute } from "@tanstack/react-router";
import { AppShell } from "@/layout/AppShell";
import { PaginaEmConstrucao } from "@/components/PaginaEmConstrucao";

export const Route = createFileRoute("/prestacao")({
  head: () => ({
    meta: [
      { title: "Prestação de Contas — SIGO | RenoveLog" },
      { name: "description", content: "Prestação de contas das rotas e dos prestadores." },
      { property: "og:title", content: "Prestação de Contas — SIGO | RenoveLog" },
      { property: "og:description", content: "Conferência de valores e comprovações por rota." },
    ],
  }),
  component: () => (
    <AppShell titulo="Prestação" descricao="Prestação de contas por rota e prestador">
      <PaginaEmConstrucao modulo="Prestação de Contas" />
    </AppShell>
  ),
});
