import { createFileRoute } from "@tanstack/react-router";
import { AppShell } from "@/layout/AppShell";
import { PaginaEmConstrucao } from "@/components/PaginaEmConstrucao";

export const Route = createFileRoute("/financeiro")({
  head: () => ({
    meta: [
      { title: "Financeiro — SIGO | RenoveLog" },
      { name: "description", content: "Pagamentos, descontos e fechamento quinzenal." },
      { property: "og:title", content: "Financeiro — SIGO | RenoveLog" },
      { property: "og:description", content: "Fechamento financeiro da operação logística." },
    ],
  }),
  component: () => (
    <AppShell titulo="Financeiro" descricao="Pagamentos e fechamento quinzenal">
      <PaginaEmConstrucao modulo="Financeiro" />
    </AppShell>
  ),
});
