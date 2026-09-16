import { createFileRoute } from "@tanstack/react-router";
import { AppShell } from "@/layout/AppShell";
import { PaginaEmConstrucao } from "@/components/PaginaEmConstrucao";

export const Route = createFileRoute("/relatorios")({
  head: () => ({
    meta: [
      { title: "Relatórios — SIGO | RenoveLog" },
      { name: "description", content: "Relatórios gerenciais de produtividade, SLA e custos." },
      { property: "og:title", content: "Relatórios — SIGO | RenoveLog" },
      { property: "og:description", content: "Indicadores consolidados da operação." },
    ],
  }),
  component: () => (
    <AppShell titulo="Relatórios" descricao="Indicadores consolidados da operação">
      <PaginaEmConstrucao modulo="Relatórios" />
    </AppShell>
  ),
});
