import { useMemo, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { AppShell } from "@/layout/AppShell";
import { lerCSV, conciliarStopViews, type Linha } from "@/lib/greenmile-import";

export const Route = createFileRoute("/importacao")({ component: Importacao });
type Arquivo = { nome: string; linhas: Linha[]; colunas: string[] };
type DetalheRota = {
  chave: string; codigo: string; data: string; romaneio: string; motorista: string;
  paradas: number; nfs: number; semMotorista: number; auxiliares: number; alertas: number;
};
type Alerta = { tipo: string; descricao: string; rota: string; nf?: string };

function Importacao() {
  const [paradas, setParadas] = useState<Arquivo | null>(null);
  const [pedidos, setPedidos] = useState<Arquivo | null>(null);
  const [erro, setErro] = useState("");
  const [processando, setProcessando] = useState(false);
  const [filtroRota, setFiltroRota] = useState("");
  const [mostrarAlertas, setMostrarAlertas] = useState(true);

  const auditoria = useMemo(() => {
    if (!paradas || !pedidos) return null;
    const paradasZL = paradas.linhas.filter(l => l["Organização"]?.trim() === "RENOVELOG-ZL");
    const ids = new Set(paradasZL.map(l => l["id"]));
    const pedidosZL = pedidos.linhas.filter(l => ids.has(l["id"]));
    const conciliacao = conciliarStopViews(paradasZL, pedidosZL);
    const mapa = new Map<string, DetalheRota>();
    const alertas: Alerta[] = conciliacao.erros.map(descricao => ({ tipo: "Conciliação", descricao, rota: "—" }));
    const mapaNF = new Map<string, Set<string>>();
    const ocorrenciasNF = new Set<string>();
    const nfsDistintas = new Set<string>();
    const locais = new Map<string, number>();
    const valoresRota = new Map<string, Set<string>>();
    let semMotorista = 0;
    let auxiliares = 0;
    for (const parada of paradasZL) {
      const codigo = parada["Código da rota"]?.trim() ?? "";
      const data = (parada["Data da Rota"] ?? "").slice(0, 10);
      const chave = `${data}|${codigo}`;
      const romaneio = parada["Descrição da rota"]?.trim() || "Não informado";
      const motorista = parada["Motoristas"]?.trim() || parada["Motorista"]?.trim() || "";
      let rota = mapa.get(chave);
      if (!rota) {
        rota = { chave, codigo, data, romaneio, motorista, paradas: 0, nfs: 0, semMotorista: 0, auxiliares: 0, alertas: 0 };
        mapa.set(chave, rota);
      }
      rota.paradas++;
      if (!motorista) { semMotorista++; rota.semMotorista++; }
      else if (!rota.motorista) rota.motorista = motorista;
      const vals = valoresRota.get(chave) ?? new Set<string>();
      vals.add(romaneio);
      valoresRota.set(chave, vals);
      const local = parada["Código da Localidade"]?.trim();
      if (local) locais.set(local, (locais.get(local) ?? 0) + 1);
    }
    for (const vinculo of conciliacao.vinculos) {
      const chave = `${vinculo.data}|${vinculo.codigoRota}`;
      const rota = mapa.get(chave);
      if (rota) {
        rota.nfs++;
        if (vinculo.tipoRomaneio === "AUXILIAR") rota.auxiliares++;
      }
      if (vinculo.tipoRomaneio === "AUXILIAR") auxiliares++;
      const nfKey = `${vinculo.numeroNF}|${vinculo.serie ?? "sem-serie"}`;
      nfsDistintas.add(nfKey);
      const nfDia = `${vinculo.data}|${nfKey}`;
      const rotasNF = mapaNF.get(nfDia) ?? new Set<string>();
      if (rotasNF.size && !rotasNF.has(vinculo.codigoRota) && !ocorrenciasNF.has(nfDia)) {
        alertas.push({ tipo: "NF em rotas diferentes", descricao: "A mesma NF/serie aparece em mais de uma rota no dia. Pode ser apoio ou reentrega; conferir antes de gravar ou remunerar.", rota: vinculo.codigoRota, nf: vinculo.numeroNF });
        ocorrenciasNF.add(nfDia);
      }
      rotasNF.add(vinculo.codigoRota);
      mapaNF.set(nfDia, rotasNF);
      const pedido = pedidosZL.find(p => p["id"] === vinculo.idParada && (p["stop.orders.number"] ?? "").trim() !== "");
      const original = pedido?.["stop.orders.number"]?.trim() ?? "";
      if (/^\d{1,3}$/.test(original)) alertas.push({ tipo: "NF curta", descricao: `Número original "${original}" é muito curto; verificar no GreenMile, sem corrigir automaticamente.`, rota: vinculo.codigoRota, nf: original });
    }
    for (const rota of mapa.values()) {
      if (rota.semMotorista > 0) {
        alertas.push({ tipo: "Motorista não informado", descricao: `${rota.semMotorista} parada(s) sem motorista preenchido no StopView. Pode ser programação futura.`, rota: rota.codigo });
      }
      if ((valoresRota.get(rota.chave)?.size ?? 0) > 1) alertas.push({ tipo: "Romaneios distintos", descricao: "Mais de uma descrição de romaneio na mesma rota/data; conferir origem fiscal e execução.", rota: rota.codigo });
      rota.alertas = alertas.filter(a => a.rota === rota.codigo).length;
    }
    const rotas = [...mapa.values()].sort((a,b)=>a.codigo.localeCompare(b.codigo,"pt-BR"));
    return {
      rotas, alertas, conciliacao, semMotorista, auxiliares, nfsDistintas: nfsDistintas.size,
      duplicidadeEntreRotas: ocorrenciasNF.size,
      locaisRepetidos: [...locais.values()].filter(n=>n>1).length,
      paradasZL: paradasZL.length, pedidosZL: pedidosZL.length,
      outrasParadas: paradas.linhas.length - paradasZL.length,
      outrosPedidos: pedidos.linhas.length - pedidosZL.length,
    };
  }, [paradas, pedidos]);

  async function lerArquivo(file: File | undefined, tipo: "paradas" | "pedidos") {
    if (!file) return;
    setProcessando(true); setErro("");
    try {
      if (file.size > 35 * 1024 * 1024) throw new Error("Arquivo acima de 35 MB. Divida a exportação por período.");
      const csv = lerCSV(await file.text());
      if (!csv.colunas.includes("id")) throw new Error("Arquivo sem ID da parada.");
      if (tipo === "paradas") {
        if (!["Organização", "Descrição da rota", "Código da rota", "Data da Rota"].every(k => csv.colunas.includes(k))) throw new Error("Selecione o StopView filtrado por Paradas.");
        setParadas({ nome: file.name, ...csv });
      } else {
        if (!["stop.orders.number", "routeView.route.key", "routeView.route.date"].every(k => csv.colunas.includes(k))) throw new Error("Selecione o StopView filtrado por Pedidos e Itens.");
        setPedidos({ nome: file.name, ...csv });
      }
    } catch (e) { setErro(e instanceof Error ? e.message : "Erro ao ler CSV"); }
    finally { setProcessando(false); }
  }
  const rotasFiltradas = auditoria?.rotas.filter(r => `${r.codigo} ${r.romaneio} ${r.motorista}`.toLowerCase().includes(filtroRota.toLowerCase())) ?? [];
  return <AppShell titulo="Importação GreenMile" descricao="Auditoria dos CSV antes de gravar no banco">
    <div className="space-y-5">
      <div className="rounded-xl border border-border bg-card p-5">
        <h2 className="font-semibold">Conferência dos StopViews</h2>
        <p className="mt-2 text-sm text-muted-foreground">Selecione os relatórios do mesmo período. A auditoria acontece no navegador e <strong>não grava</strong> dados no Supabase. Informações de rota e NF devem ser conferidas antes de qualquer liberação operacional.</p>
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
      {auditoria && <div className="space-y-5">
        <section className="rounded-xl border border-border bg-card p-5 space-y-4">
          <h2 className="font-semibold">Resumo da auditoria — RENOVELOG-ZL</h2>
          <p className="text-sm text-muted-foreground">{auditoria.outrasParadas.toLocaleString("pt-BR")} paradas de outras organizações excluídas; {auditoria.outrosPedidos.toLocaleString("pt-BR")} pedidos fora do escopo excluídos.</p>
          <div className="grid gap-3 grid-cols-2 lg:grid-cols-4">
            {[
              ["Paradas",auditoria.paradasZL],
              ["Vínculos de NF",auditoria.conciliacao.vinculos.length],
              ["NFs distintas",auditoria.nfsDistintas],
              ["Rotas",auditoria.rotas.length],
              ["Paradas sem motorista",auditoria.semMotorista],
              ["NFs em rotas distintas",auditoria.duplicidadeEntreRotas],
              ["Vínculos auxiliares",auditoria.auxiliares],
              ["Alertas de auditoria",auditoria.alertas.length],
            ].map(([nome,valor])=><div key={nome} className="rounded-lg bg-muted p-3"><div className="text-xs text-muted-foreground">{nome}</div><div className="mt-1 text-2xl font-semibold">{Number(valor).toLocaleString("pt-BR")}</div></div>)}
          </div>
          <p className="text-xs text-muted-foreground">Códigos de localidade com múltiplas paradas: {auditoria.locaisRepetidos}. Repetição de PDV não é, por si só, duplicidade de NF. Os vínculos auxiliares contam ocorrências, não romaneios únicos.</p>
        </section>
        <section className="rounded-xl border border-border bg-card p-5 space-y-3">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h2 className="font-semibold">Conferência por rota</h2>
            <input aria-label="Filtrar rota" value={filtroRota} onChange={e=>setFiltroRota(e.target.value)} placeholder="Buscar rota, motorista ou romaneio" className="w-full max-w-sm rounded-md border border-input bg-background px-3 py-2 text-sm" />
          </div>
          <div className="overflow-x-auto"><table className="w-full min-w-[850px] text-left text-sm">
            <thead className="border-b border-border text-muted-foreground"><tr>{["Rota","Data","Romaneio (descrição GM)","Motorista","Paradas","NFs","Sem motorista","Auxiliares","Alertas"].map(c=><th key={c} className="px-3 py-3 font-medium">{c}</th>)}</tr></thead>
            <tbody>{rotasFiltradas.map(r=><tr key={r.chave} className="border-b border-border/60">
              <td className="px-3 py-3 font-medium">{r.codigo || "—"}</td><td className="px-3 py-3">{r.data}</td><td className="px-3 py-3 font-mono text-xs">{r.romaneio}</td>
              <td className="px-3 py-3">{r.motorista || "Não informado"}</td><td className="px-3 py-3">{r.paradas}</td><td className="px-3 py-3">{r.nfs}</td>
              <td className="px-3 py-3">{r.semMotorista}</td><td className="px-3 py-3">{r.auxiliares}</td><td className="px-3 py-3">{r.alertas}</td>
            </tr>)}</tbody>
          </table></div>
        </section>
        <section className="rounded-xl border border-border bg-card p-5 space-y-3">
          <button type="button" onClick={()=>setMostrarAlertas(v=>!v)} className="font-semibold underline-offset-4 hover:underline">Alertas para revisão ({auditoria.alertas.length}) — {mostrarAlertas ? "ocultar" : "mostrar"}</button>
          {mostrarAlertas && (auditoria.alertas.length ? <div className="max-h-80 overflow-auto space-y-2">
            {auditoria.alertas.slice(0,200).map((a,i)=><div key={i} className="rounded-md border border-border p-3 text-sm"><strong>{a.tipo}</strong> — rota {a.rota}{a.nf ? ` — NF ${a.nf}` : ""}<p className="text-muted-foreground">{a.descricao}</p></div>)}
            {auditoria.alertas.length > 200 && <p className="text-xs text-muted-foreground">Exibindo os primeiros 200 alertas.</p>}
          </div> : <p className="text-sm text-muted-foreground">Nenhum alerta detectado pelas regras atuais. Isso não substitui auditoria fiscal.</p>)}
        </section>
        <p className="rounded-md border border-border bg-muted p-3 text-sm"><strong>Modo seguro:</strong> nenhum arquivo foi persistido no Supabase. A gravação de rotas permanece indisponível até definirmos validação de importação repetida, responsabilidade fiscal/operacional, permissões e trilha de auditoria.</p>
      </div>}
    </div>
  </AppShell>;
}
