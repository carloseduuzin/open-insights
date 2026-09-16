import { createFileRoute } from "@tanstack/react-router";
import { AppShell } from "@/layout/AppShell";
import { PaginaEmConstrucao } from "@/components/PaginaEmConstrucao";

export const Route = createFileRoute("/romaneios")({
  head: () => ({
    meta: [
      { title: "Romaneios — SIGO | RenoveLog" },
      { name: "description", content: "Controle de romaneios e conferência de cargas." },
      { property: "og:title", content: "Romaneios — SIGO | RenoveLog" },
      { property: "og:description", content: "Emissão e conferência de romaneios da operação." },
    ],
  }),
  component: () => (
    <AppShell titulo="Romaneios" descricao="Emissão e conferência de cargas">
      <PaginaEmConstrucao modulo="Romaneios" />
    </AppShell>
  ),
});
