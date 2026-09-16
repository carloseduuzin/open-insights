import { createFileRoute } from "@tanstack/react-router";
import { AppShell } from "@/layout/AppShell";
import { PaginaEmConstrucao } from "@/components/PaginaEmConstrucao";

export const Route = createFileRoute("/ocorrencias")({
  head: () => ({
    meta: [
      { title: "Ocorrências — SIGO | RenoveLog" },
      { name: "description", content: "Registro e tratativa de ocorrências operacionais." },
      { property: "og:title", content: "Ocorrências — SIGO | RenoveLog" },
      { property: "og:description", content: "Tratativas de avarias, atrasos e insucessos." },
    ],
  }),
  component: () => (
    <AppShell titulo="Ocorrências" descricao="Registro e tratativa de ocorrências">
      <PaginaEmConstrucao modulo="Ocorrências" />
    </AppShell>
  ),
});
