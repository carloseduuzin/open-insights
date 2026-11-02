import { useEffect, useMemo, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { AppShell } from "@/layout/AppShell";
import { requireSupabase } from "@/lib/supabase";
import { criticidadePrestacao, vencimentoD3, type PrestacaoRegistro } from "@/lib/prestacao-sla";

export const Route = createFileRoute("/prestacao")({
  head: () => ({ meta: [{ title: "Prestação de Contas — SIGO | RenoveLog" }] }),
  component: Prestacao,
});

const statusTexto: Record<PrestacaoRegistro["status"],string> = {
  ABERTA: "Aberta", RETORNADA: "Retornada à base", CONFERIDA: "Conferida",
  ENVIADA_JTI: "Enviada à JTI", CONFIRMADA_JTI: "Confirmada JTI",
};
const amostra: PrestacaoRegistro[] = [
  { id:"exemplo1",romaneio_oficial:"123456789012",d0:"2026-10-27",status:"ABERTA",responsavel_id:null,retornada_em:null,conferida_em:null,enviada_em:null,confirmada_em:null },
  { id:"exemplo2",romaneio_oficial:"234567890123",d0:"2026-10-29",status:"CONFERIDA",responsavel_id:null,retornada_em:null,conferida_em:null,enviada_em:null,confirmada_em:null },
  { id:"exemplo3",romaneio_oficial:"345678901234",d0:"2026-10-31",status:"ENVIADA_JTI",responsavel_id:null,retornada_em:null,conferida_em:null,enviada_em:null,confirmada_em:null },
  { id:"exemplo4",romaneio_oficial:"456789012345",d0:"2026-11-02",status:"CONFIRMADA_JTI",responsavel_id:null,retornada_em:null,conferida_em:null,enviada_em:null,confirmada_em:null },
];
function dataLocalHoje(): string {
  const agora = new Date();
  const partes = new Intl.DateTimeFormat("en-CA", { timeZone:"America/Sao_Paulo",year:"numeric",month:"2-digit",day:"2-digit" }).formatToParts(agora);
  const valor = (chave:string) => partes.find(p=>p.type===chave)?.value ?? "";
  return `${valor("year")}-${valor("month")}-${valor("day")}`;
}
function Prestacao() {
  const [registros,setRegistros] = useState<PrestacaoRegistro[]>([]);
  const [carregando,setCarregando] = useState(true);
  const [erro,setErro] = useState("");
  const [demo,setDemo] = useState(false);
  const [busca,setBusca] = useState("");
  const [filtro,setFiltro] = useState("ATIVAS");
  const [baixando,setBaixando] = useState<string | null>(null);
  const [sucesso,setSucesso] = useState("");
  const hoje = dataLocalHoje();
  async function carregar() {
    setCarregando(true);setErro("");
    try {
      const { data, error } = await requireSupabase().from("prestacoes").select("id,romaneio_oficial,d0,status,responsavel_id,retornada_em,conferida_em,enviada_em,confirmada_em").order("d0",{ascending:true}).limit(1000);
      if(error) throw error;
      setRegistros((data??[]) as PrestacaoRegistro[]);
    } catch (e) { setErro(e instanceof Error?e.message:"Não foi possível consultar prestações."); }
    finally { setCarregando(false); }
  }
  useEffect(()=>{void carregar();},[]);
  async function darBaixa(item: PrestacaoRegistro) {
    if (demo || item.status !== "CONFERIDA" || baixando) return;
    const confirmado = window.confirm(`Confirmar que a prestação do romaneio ${item.romaneio_oficial} foi realmente ENVIADA à JTI? Ela sairá da fila de pendências e ficará registrada no histórico. Essa ação não pode ser desfeita nesta tela.`);
    if (!confirmado) return;
    setBaixando(item.id);
    setErro("");
    setSucesso("");
    try {
      const { data, error } = await requireSupabase().rpc("sigo_enviar_prestacao_jti", {p_prestacao_id:item.id});
      if (error) throw error;
      if (!data || (Array.isArray(data) && data.length === 0)) throw new Error("Não foi possível confirmar a baixa no banco.");
      setSucesso(`Prestação ${item.romaneio_oficial} baixada com sucesso. Consulte Baixadas / histórico.`);
      await carregar();
    } catch (e) {setErro(e instanceof Error?e.message:"Falha ao dar baixa. Confira se o romaneio já foi enviado.");}
    finally {setBaixando(null);}
  }
  const lista = useMemo(()=> (demo?amostra:registros).map(r=>({...r,crit:criticidadePrestacao(r,hoje)})),[demo,registros,hoje]);
  const contagens = {
    total:lista.filter(r=>r.crit.nivel!=="CONCLUIDA").length,
    criticos:lista.filter(r=>r.crit.nivel==="CRITICO").length,
    urgentes:lista.filter(r=>r.crit.nivel==="URGENTE").length,
    alertas:lista.filter(r=>r.crit.nivel==="ALERTA").length,
    concluidas:lista.filter(r=>r.crit.nivel==="CONCLUIDA").length,
  };
  const visiveis=lista.filter(r=>(filtro==="TODAS" || (filtro==="ATIVAS" ? r.crit.nivel!=="CONCLUIDA" : r.crit.nivel===filtro))&&r.romaneio_oficial.includes(busca.trim())).sort((a,b)=>{
    const ordem:Record<string,number>={CRITICO:0,URGENTE:1,ALERTA:2,NO_PRAZO:3,FUTURA:4,CONCLUIDA:5};
    return (ordem[a.crit.nivel]??9)-(ordem[b.crit.nivel]??9)||a.d0.localeCompare(b.d0);
  });
  const tom:Record<string,string>={CRITICO:"text-red-500",URGENTE:"text-orange-500",ALERTA:"text-amber-500",CONCLUIDA:"text-emerald-500",NO_PRAZO:"text-foreground",FUTURA:"text-muted-foreground"};
  return <AppShell titulo="Prestação de Contas" descricao="Controle de romaneios e SLA D+3 dias corridos">
    <div className="space-y-5">
      <section className="rounded-xl border border-border bg-card p-5 space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div><h2 className="font-semibold">Fila de prestação JTI</h2><p className="mt-1 text-sm text-muted-foreground">D0 = data da rota GreenMile. Vencimento D+3 em dias corridos, com meta interna de 48 horas.</p></div>
          <button type="button" onClick={()=>void carregar()} className="rounded-lg border border-border px-3 py-2 text-sm hover:bg-muted">Atualizar consulta</button>
        </div>
        <label className="flex items-center gap-3 text-sm"><input type="checkbox" checked={demo} onChange={e=>setDemo(e.target.checked)} />Exibir demonstração com registros fictícios (não salvos)</label>
        {demo && <p role="status" className="rounded-lg border border-amber-500/30 bg-amber-500/10 p-3 text-sm font-medium">MODO DEMONSTRAÇÃO — dados fictícios, sem relação com a operação real. Nenhuma alteração no Supabase.</p>}
        {sucesso && !demo && <p role="status" className="rounded-lg border border-emerald-500/30 p-3 text-sm text-emerald-500">{sucesso}</p>}
        {!demo && erro && <p role="alert" className="rounded-lg border border-destructive/30 p-3 text-sm text-destructive">Falha ao consultar: {erro}</p>}
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
          {([["Pendências ativas",contagens.total],["Críticos D+4",contagens.criticos],["Urgentes D+3",contagens.urgentes],["Alerta D+2",contagens.alertas],["Baixadas",contagens.concluidas]] as const).map(([nome,numero])=><div key={nome} className="rounded-lg bg-muted p-3"><p className="text-xs text-muted-foreground">{nome}</p><p className="mt-1 text-2xl font-semibold">{numero.toLocaleString("pt-BR")}</p></div>)}
        </div>
        <p className="text-xs text-muted-foreground">Data de referência: {hoje.split("-").reverse().join("/")}. A criticidade representa atraso de prestação, não status da entrega. Enviadas à JTI recebem baixa no SIGO e saem da fila ativa; a confirmação posterior da JTI permanece no histórico.</p>
      </section>
      <section className="rounded-xl border border-border bg-card p-5 space-y-4">
        <div className="flex flex-wrap gap-3">
          <input aria-label="Buscar romaneio" value={busca} onChange={e=>setBusca(e.target.value)} placeholder="Localizar romaneio (12 dígitos)" className="min-w-0 flex-1 rounded-md border border-input bg-background px-3 py-2 text-sm" />
          <select aria-label="Filtrar criticidade" value={filtro} onChange={e=>setFiltro(e.target.value)} className="rounded-md border border-input bg-background px-3 py-2 text-sm">
            <option value="ATIVAS">Pendências ativas</option><option value="TODAS">Todas (inclui histórico)</option><option value="CRITICO">Críticas</option><option value="URGENTE">Urgentes</option><option value="ALERTA">Alertas</option><option value="NO_PRAZO">No prazo</option><option value="CONCLUIDA">Baixadas / histórico</option><option value="FUTURA">Futuras</option>
          </select>
        </div>
        {!demo && carregando ? <p className="text-sm text-muted-foreground">Consultando Supabase...</p> : visiveis.length===0 ? <p className="rounded-lg bg-muted p-5 text-sm text-muted-foreground">{erro && !demo?"Não foi possível carregar os dados.":"Nenhuma prestação encontrada para este filtro. A importação GreenMile ainda não gera prestações automaticamente."}</p> :
          <div className="overflow-x-auto"><table className="w-full min-w-[820px] text-left text-sm">
            <thead className="border-b border-border text-muted-foreground"><tr>{["Romaneio oficial","Data da rota (D0)","Vencimento (D+3)","Dias","Etapa","Criticidade","Responsável","Baixa / envio JTI"].map(t=><th key={t} className="px-3 py-3 font-medium">{t}</th>)}</tr></thead>
            <tbody>{visiveis.map(r=><tr key={r.id} className="border-b border-border/60">
              <td className="px-3 py-3 font-mono">{r.romaneio_oficial}</td><td className="px-3 py-3">{r.d0}</td><td className="px-3 py-3">{vencimentoD3(r.d0)}</td>
              <td className="px-3 py-3">{r.crit.dias>=0?`D+${r.crit.dias}`:"Futura"}</td><td className="px-3 py-3">{statusTexto[r.status]??r.status}</td>
              <td className={`px-3 py-3 font-medium ${tom[r.crit.nivel]??""}`}>{r.crit.rotulo}</td>
              <td className="px-3 py-3">{r.responsavel_id?"ID cadastrado":"Não definido"}</td>
              <td className="px-3 py-3">
                {r.status === "CONFERIDA" && !demo ?
                  <button type="button" disabled={!!baixando || carregando} onClick={()=>void darBaixa(r)} className="whitespace-nowrap rounded-md bg-primary px-3 py-2 text-xs font-semibold text-primary-foreground disabled:opacity-40">{baixando===r.id?"Registrando...":"Dar baixa — Enviado à JTI"}</button> :
                  r.status === "ENVIADA_JTI" || r.status === "CONFIRMADA_JTI" ?
                    <span className="text-xs text-emerald-500">Baixada {r.enviada_em?new Date(r.enviada_em).toLocaleString("pt-BR",{timeZone:"America/Sao_Paulo"}):""}</span> :
                    <span className="text-xs text-muted-foreground">{demo?"Simulação — sem ações": "Aguardando conferência"}</span>}
              </td>
            </tr>)}</tbody>
          </table></div>}
        <p className="text-xs text-muted-foreground">A baixa só é permitida para prestações conferidas. Após confirmação, o servidor registra usuário e horário e retira o romaneio da fila ativa. A demonstração nunca grava dados.</p>
      </section>
    </div>
  </AppShell>;
}
