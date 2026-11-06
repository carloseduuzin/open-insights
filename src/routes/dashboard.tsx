import { useEffect, useMemo, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { AppShell } from "@/layout/AppShell";
import { requireSupabase } from "@/lib/supabase";
import { criticidadePrestacao, type PrestacaoRegistro } from "@/lib/prestacao-sla";

export const Route = createFileRoute("/dashboard")({
  head: () => ({ meta: [{ title: "Dashboard — SIGO | RenoveLog" }] }),
  component: Dashboard,
});

function hojeSP() {
  const partes = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Sao_Paulo", year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(new Date());
  const get = (campo: string) => partes.find(p => p.type === campo)?.value ?? "";
  return `${get("year")}-${get("month")}-${get("day")}`;
}

function Dashboard() {
  const [registros, setRegistros] = useState<PrestacaoRegistro[]>([]);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState("");
  useEffect(() => {
    let ativo = true;
    async function consultar() {
      try {
        const { data, error } = await requireSupabase().from("prestacoes")
          .select("id,romaneio_oficial,d0,status,responsavel_id,retornada_em,conferida_em,enviada_em,confirmada_em")
          .order("d0", { ascending: false }).limit(1000);
        if (error) throw error;
        if (ativo) setRegistros((data ?? []) as PrestacaoRegistro[]);
      } catch (e) {
        if (ativo) setErro(e instanceof Error ? e.message : "Falha ao consultar prestações");
      } finally {
        if (ativo) setCarregando(false);
      }
    }
    void consultar();
    return () => { ativo = false; };
  }, []);
  const totais = useMemo(() => {
    const hoje = hojeSP();
    const itens = registros.map(p => ({ ...p, classificacao: criticidadePrestacao(p, hoje) }));
    return {
      pendentes: itens.filter(p => p.classificacao.nivel !== "CONCLUIDA").length,
      criticas: itens.filter(p => p.classificacao.nivel === "CRITICO").length,
      urgentes: itens.filter(p => p.classificacao.nivel === "URGENTE").length,
      alertas: itens.filter(p => p.classificacao.nivel === "ALERTA").length,
      baixadas: itens.filter(p => p.classificacao.nivel === "CONCLUIDA").length,
    };
  }, [registros]);

  return <AppShell titulo="Dashboard" descricao="Indicadores reais de prestação de contas — JTI">
    <div className="space-y-5">
      <section className="rounded-xl border border-border bg-card p-5">
        <h2 className="font-semibold">Prestação de contas</h2>
        <p className="mt-1 text-sm text-muted-foreground">Dados consultados no Supabase. Nenhum indicador fictício é exibido. D0 = data da rota, SLA D+3 corridos.</p>
        {erro && <p role="alert" className="mt-3 text-sm text-destructive">Falha ao carregar indicadores: {erro}</p>}
        {carregando ? <p className="mt-3 text-sm text-muted-foreground">Carregando indicadores...</p> :
          <div className="mt-4 grid grid-cols-2 gap-3 lg:grid-cols-5">
            {([
              ["Pendências ativas", totais.pendentes],
              ["Críticas D+4", totais.criticas],
              ["Urgentes D+3", totais.urgentes],
              ["Alertas D+2", totais.alertas],
              ["Baixadas", totais.baixadas],
            ] as const).map(([titulo, quantidade]) => (
              <div key={titulo} className="rounded-lg bg-muted p-4">
                <p className="text-xs text-muted-foreground">{titulo}</p>
                <p className="mt-2 text-2xl font-semibold">{erro ? "—" : quantidade.toLocaleString("pt-BR")}</p>
              </div>
            ))}
          </div>}
      </section>
      <section className="rounded-xl border border-border bg-card p-5">
        <h2 className="font-semibold">Visão operacional</h2>
        <p className="mt-2 text-sm text-muted-foreground">Indicadores de entregas, frota, quilômetros, faturamento e rotas críticas serão exibidos somente após integração de fontes reais validadas. Não usamos números de exemplo no piloto.</p>
      </section>
    </div>
  </AppShell>;
}
