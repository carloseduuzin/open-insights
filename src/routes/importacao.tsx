import { useMemo, useState } from "react";
import { createFileRoute, Link } from "@tanstack/react-router";
import { AppShell } from "@/layout/AppShell";
import { lerCSV, conciliarStopViews, prepararPrestacoesGM, type Linha } from "@/lib/greenmile-import";
import { requireSupabase } from "@/lib/supabase";

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
  const [gravando,setGravando] = useState(false);
  const [feedback,setFeedback] = useState("");
  const [importacaoConfirmada,setImportacaoConfirmada] = useState(false);
  const [cientePendencias,setCientePendencias] = useState(false);

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
    setProcessando(true); setErro(""); setCientePendencias(false); setFeedback(""); setImportacaoConfirmada(false);
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
  const preparacao = useMemo(() => {
    if (!paradas || !pedidos) return null;
    const linhas = paradas.linhas.filter(l=>l["Organização"]?.trim()==="RENOVELOG-ZL");
    const ids = new Set(linhas.map(l=>l["id"]));
    return prepararPrestacoesGM(linhas,pedidos.linhas.filter(l=>ids.has(l["id"])));
  },[paradas,pedidos]);
  const hoje = new Intl.DateTimeFormat("en-CA",{timeZone:"America/Sao_Paulo",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date());
  const futuras = preparacao?.candidatos.filter(c=>c.d0>hoje).length ?? 0;
  const permitido = !!preparacao && !preparacao.bloqueado && futuras===0 && preparacao.candidatos.length>0 && (preparacao.pendenciasNF.length===0 || cientePendencias);
  async function gravarPrestacoes() {
    if (!permitido || !preparacao || gravando) return;
    const confirmado = window.confirm(`CONFIRMAR abertura da fila de prestação para ${preparacao.candidatos.length} romaneios fiscais oficiais? A gravação é real, não muda prestações já cadastradas, e romaneios auxiliares são excluídos. Existem ${preparacao.pendenciasNF.length} pendências de NF que deverão ser tratadas antes da conferência/baixa.`);
    if (!confirmado) return;
    setGravando(true);setFeedback("");setErro("");
    try {
      const itens=preparacao.candidatos.map(c=>({romaneio:c.romaneio,d0:c.d0}));
      const {data,error} = await requireSupabase().rpc("sigo_importar_prestacoes_gm",{p_itens:itens});
      if(error) throw error;
      const resultado=Array.isArray(data)?data[0]:data;
      if (!resultado) throw new Error("Banco não confirmou a importação");
      setFeedback(`Importação confirmada: ${resultado.inseridos} prestação(ões) aberta(s), ${resultado.existentes} já existente(s). Confira em Prestação de Contas.`);
      setImportacaoConfirmada(true);
    }catch(e){setErro(e instanceof Error?e.message:"Falha na gravação.");}
    finally{setGravando(false);}
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
        <section className="rounded-xl border border-border bg-card p-5 space-y-3">
          <h2 className="font-semibold">Abrir fila de prestação a partir do GreenMile</h2>
          <p className="text-sm text-muted-foreground">Prévia: <strong>{preparacao?.candidatos.length??0} romaneios oficiais candidatos</strong>, {preparacao?.auxiliares??0} rotas auxiliares excluídas. A importação cria somente prestações ainda inexistentes; nunca apaga, reinicia ou reabre romaneios baixados. Não grava rotas, paradas nem NFs.</p>
          {futuras>0 && <p className="rounded-md border border-amber-500/40 p-3 text-sm text-amber-500">{futuras} rota(s) com D0 no futuro. Aguarde a data da rota para abrir a prestação; hoje nenhum dado será gravado.</p>}
          {!!preparacao?.avisos.length && <p className="rounded-md border border-destructive/40 p-3 text-sm text-destructive">Importação bloqueada: {preparacao.avisos.length} ocorrência(s) de conciliação ou romaneio. Revise os arquivos antes de gravar.</p>}
          {!!preparacao?.pendenciasNF.length && <div className="space-y-3 rounded-md border border-amber-500/50 bg-amber-500/5 p-3 text-sm">
            <p className="font-semibold text-amber-500">{preparacao.pendenciasNF.length} pendência(s) fiscal(is) — não impedem abrir a fila, mas devem ser corrigidas antes de conferir ou baixar.</p>
            <p className="text-muted-foreground">Os romaneios serão cadastrados apenas como ABERTA. O SIGO não está validando essas NFs ou dando baixa nelas.</p>
            <ul className="list-disc space-y-1 pl-5">{preparacao.pendenciasNF.map(p=><li key={p.idParada}>Parada <strong>{p.idParada}</strong>, rota <strong>{p.rota||"não identificada"}</strong>, romaneio <strong>{p.romaneio||"não identificado"}</strong>: NF ausente ou inválida</li>)}</ul>
            <label className="flex items-start gap-2"><input type="checkbox" checked={cientePendencias} onChange={e=>setCientePendencias(e.target.checked)} className="mt-1"/><span>Estou ciente dessas pendências e vou conferir as NFs no GreenMile antes de registrar a conferência da prestação.</span></label>
          </div>}
          <div className="max-h-48 overflow-auto rounded-md border border-border">
            <table className="w-full text-left text-xs"><thead><tr><th className="p-2">Romaneio oficial</th><th className="p-2">D0</th><th className="p-2">Rota</th></tr></thead><tbody>{preparacao?.candidatos.map(c=><tr key={c.romaneio+"|"+c.rota} className="border-t border-border"><td className="p-2 font-mono">{c.romaneio}</td><td className="p-2">{c.d0}</td><td className="p-2">{c.rota}</td></tr>)}</tbody></table>
          </div>
          <div className="flex flex-wrap items-center gap-3">
            <button type="button" disabled={!permitido||gravando} onClick={()=>void gravarPrestacoes()} className="rounded-md bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:cursor-not-allowed disabled:opacity-40">{gravando?"Gravando...":"Confirmar e abrir prestações"}</button>
            <Link to="/prestacao" className="rounded-md border border-border px-4 py-2 text-sm font-medium hover:bg-muted">Ver acompanhamento atual</Link>
          </div>
          {!!preparacao?.pendenciasNF.length && !cientePendencias && !preparacao.bloqueado && <p className="text-sm text-amber-500">Para habilitar a importação, leia e marque a confirmação de ciência das pendências fiscais.</p>}
          {feedback && <div role="status" className="space-y-3 rounded-md border border-emerald-500/40 p-3 text-sm text-emerald-500">
            <p>{feedback}</p>
            {importacaoConfirmada && <Link to="/prestacao" className="inline-flex rounded-md bg-primary px-4 py-2 font-semibold text-primary-foreground">Ir para acompanhamento de prestações</Link>}
          </div>}
          <p className="text-xs text-muted-foreground">Somente romaneios fiscais candidatos com D0 válido e sem divergências estruturais podem entrar na fila. NFs ausentes geram pendências explícitas e exigem ciência do operador; abrir a fila não significa conferir a documentação. A confirmação é obrigatória e a gravação usa uma operação única no Supabase.</p>
        </section>
      </div>}
    </div>
  </AppShell>;
}
