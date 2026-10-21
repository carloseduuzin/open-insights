import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { AppShell } from "@/layout/AppShell";
import { lerCSV, conciliarStopViews, type Linha } from "@/lib/greenmile-import";

export const Route = createFileRoute("/importacao")({ component: Importacao });
type Arquivo = { nome: string; linhas: Linha[]; colunas: string[] };
function Importacao() {
  const [paradas, setParadas] = useState<Arquivo | null>(null);
  const [pedidos, setPedidos] = useState<Arquivo | null>(null);
  const [erro, setErro] = useState("");
  const [processando, setProcessando] = useState(false);
  const conciliacao = paradas && pedidos ? conciliarStopViews(paradas.linhas, pedidos.linhas) : null;
  async function lerArquivo(file: File | undefined, tipo: "paradas" | "pedidos") {
    if (!file) return;
    setProcessando(true); setErro("");
    try {
      if (file.size > 35 * 1024 * 1024) throw new Error("Arquivo acima de 35 MB. Divida a exportação por período.");
      const csv = lerCSV(await file.text());
      if (!csv.colunas.includes("id")) throw new Error("Arquivo sem ID da parada.");
      if (tipo === "paradas") {
        if (!csv.colunas.includes("Descrição da rota") || !csv.colunas.includes("Código da rota")) throw new Error("Selecione o StopView filtrado por Paradas.");
        setParadas({ nome: file.name, ...csv });
      } else {
        if (!csv.colunas.includes("stop.orders.number") || !csv.colunas.includes("routeView.route.key")) throw new Error("Selecione o StopView filtrado por Pedidos e Itens.");
        setPedidos({ nome: file.name, ...csv });
      }
    } catch (e) { setErro(e instanceof Error ? e.message : "Erro ao ler CSV"); }
    finally { setProcessando(false); }
  }
  return <AppShell titulo="Importação GreenMile" descricao="Pré-validação dos CSV antes de gravar no banco">
    <div className="space-y-5">
      <div className="rounded-xl border border-border bg-card p-5">
        <h2 className="font-semibold">Conferência dos StopViews</h2>
        <p className="mt-2 text-sm text-muted-foreground">Selecione os dois relatórios do mesmo período. O SIGO cruza os pedidos pelo ID da parada, preserva os zeros da NF e separa romaneios auxiliares. Esta tela apenas valida os arquivos: não grava dados.</p>
        <div className="mt-4 grid gap-4 md:grid-cols-2">
          <label className="block space-y-2 text-sm font-medium">StopView — Paradas
            <input type="file" accept=".csv,text/csv" disabled={processando} onChange={e=>void lerArquivo(e.target.files?.[0],"paradas")} className="block w-full rounded-md border p-2 text-sm" />
            {paradas && <span className="block text-xs text-muted-foreground">{paradas.nome} — {paradas.linhas.length.toLocaleString("pt-BR")} linhas</span>}
          </label>
          <label className="block space-y-2 text-sm font-medium">StopView — Pedidos e Itens
            <input type="file" accept=".csv,text/csv" disabled={processando} onChange={e=>void lerArquivo(e.target.files?.[0],"pedidos")} className="block w-full rounded-md border p-2 text-sm" />
            {pedidos && <span className="block text-xs text-muted-foreground">{pedidos.nome} — {pedidos.linhas.length.toLocaleString("pt-BR")} linhas</span>}
          </label>
        </div>
        {erro && <p role="alert" className="mt-3 text-sm text-destructive">{erro}</p>}
      </div>
      {conciliacao && <div className="rounded-xl border border-border bg-card p-5 space-y-4">
        <h2 className="font-semibold">Resultado da pré-validação</h2>
        <div className="grid gap-3 sm:grid-cols-3">
          <div className="rounded-lg bg-muted p-3"><div className="text-xs">Paradas</div><div className="text-2xl font-semibold">{conciliacao.totalParadas.toLocaleString("pt-BR")}</div></div>
          <div className="rounded-lg bg-muted p-3"><div className="text-xs">NFs relacionadas</div><div className="text-2xl font-semibold">{conciliacao.vinculos.length.toLocaleString("pt-BR")}</div></div>
          <div className="rounded-lg bg-muted p-3"><div className="text-xs">Ocorrências para revisar</div><div className="text-2xl font-semibold">{conciliacao.erros.length.toLocaleString("pt-BR")}</div></div>
        </div>
        <p className="text-sm text-muted-foreground">Romaneios auxiliares encontrados: {conciliacao.vinculos.filter(v=>v.tipoRomaneio==="AUXILIAR").length}. Romaneios não classificados: {conciliacao.vinculos.filter(v=>v.tipoRomaneio==="INVALIDO").length}.</p>
        {conciliacao.erros.length > 0 && <div className="max-h-48 overflow-auto rounded-lg border p-3"><h3 className="mb-2 text-sm font-medium">Primeiras ocorrências</h3>{conciliacao.erros.slice(0,40).map((item,i)=><p key={i} className="text-xs text-destructive">{item}</p>)}</div>}
        <p className="text-xs text-muted-foreground">Nenhum registro foi salvo. A gravação controlada será liberada após testes de consistência e auditoria.</p>
      </div>}
    </div>
  </AppShell>;
}
