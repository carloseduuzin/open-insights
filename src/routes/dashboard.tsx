import { useQuery } from "@tanstack/react-query";
import { createFileRoute } from "@tanstack/react-router";
import { AppShell } from "@/layout/AppShell";
import { requireSupabase } from "@/lib/supabase";

export const Route = createFileRoute("/dashboard")({
  head: () => ({ meta: [{ title: "Dashboard — SIGO | RenoveLog" }] }),
  component: Dashboard,
});
type Totais = { pendentes: number; criticas: number; urgentes: number; alertas: number; baixadas: number; arquivadas: number };

function Dashboard() {
  const consulta = useQuery({
    queryKey: ["sigo-dashboard"],
    queryFn: async () => {
      const { data, error } = await requireSupabase().from("v_dashboard_prestacoes").select("pendentes,criticas,urgentes,alertas,baixadas,arquivadas").single();
      if (error) throw error;
      if (!data) throw new Error("Indicadores não confirmados no banco.");
      return data as Totais;
    },
    staleTime: 15_000,refetchInterval: 60_000,retry: false,
  });
  const totais = consulta.data;
  return <AppShell titulo="Dashboard" descricao="Indicadores reais de prestação de contas — JTI">
    <div className="space-y-5">
      <section className="rounded-xl border border-border bg-card p-5">
        <div className="flex flex-wrap justify-between gap-3"><h2 className="font-semibold">Prestação de contas</h2><button type="button" disabled={consulta.isFetching} onClick={() => void consulta.refetch()} className="rounded-md border border-border px-3 py-2 text-sm disabled:opacity-40">Atualizar indicadores</button></div>
        <p className="mt-1 text-sm text-muted-foreground">Indicadores do Supabase, incluindo prestações arquivadas. D0 = data da rota, SLA D+3 corridos.</p>
        {consulta.isError && <p role="alert" className="mt-3 text-sm text-destructive">Não foi possível atualizar os indicadores. {totais ? "Os valores exibidos são da última consulta confirmada." : "Tente atualizar a consulta."}</p>}
        {consulta.isPending ? <p role="status" className="mt-3 text-sm text-muted-foreground">Carregando indicadores...</p> : totais && <>
          <div className="mt-4 grid grid-cols-2 gap-3 lg:grid-cols-5">{([
            ["Pendências ativas",totais.pendentes],["Críticas D+4",totais.criticas],["Urgentes D+3",totais.urgentes],["Alertas D+2",totais.alertas],["Baixadas",totais.baixadas],
          ] as const).map(([titulo,quantidade]) => <div key={titulo} className="rounded-lg bg-muted p-4"><p className="text-xs text-muted-foreground">{titulo}</p><p className="mt-2 text-2xl font-semibold">{quantidade.toLocaleString("pt-BR")}</p></div>)}</div>
          <p className="mt-3 text-sm text-muted-foreground">{totais.arquivadas.toLocaleString("pt-BR")} prestação(ões) retirada(s) da listagem operacional após exportação e envio; seus totais permanecem neste painel.</p>
        </>}
      </section>
      <section className="rounded-xl border border-border bg-card p-5"><h2 className="font-semibold">Visão operacional</h2><p className="mt-2 text-sm text-muted-foreground">Indicadores de entregas, frota, quilômetros e faturamento dependem de fontes reais validadas.</p></section>
    </div>
  </AppShell>;
}
