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
  const [busca,setBusca] = useState("");
  const [filtro,setFiltro] = useState("ATIVAS");
  const [baixando,setBaixando] = useState<string | null>(null);
  const [sucesso,setSucesso] = useState("");
  const [novoRomaneio,setNovoRomaneio] = useState("");
  const [novaData,setNovaData] = useState("");
  const [criando,setCriando] = useState(false);
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
  async function avancar(item: PrestacaoRegistro) {
    if (baixando) return;
    const etapa = item.status === "ABERTA" ? "RETORNADA" : item.status === "RETORNADA" ? "CONFERIDA" : item.status === "CONFERIDA" ? "ENVIADA_JTI" : null;
    if (!etapa) return;
    const texto = etapa === "RETORNADA" ? "registrar RETORNO À BASE" : etapa === "CONFERIDA" ? "registrar a CONFERÊNCIA" : "DAR BAIXA como ENVIADA À JTI";
    if (!window.confirm(`Confirma ${texto} da prestação ${item.romaneio_oficial}? O usuário e horário serão registrados automaticamente.`)) return;
    setBaixando(item.id);
    setErro("");
    setSucesso("");
    try {
      const chamada = etapa === "ENVIADA_JTI"
        ? await requireSupabase().rpc("sigo_enviar_prestacao_jti", { p_prestacao_id: item.id })
        : await requireSupabase().rpc("sigo_avancar_prestacao", { p_prestacao_id: item.id, p_etapa: etapa });
      if (chamada.error) throw chamada.error;
      if (!chamada.data || (Array.isArray(chamada.data) && chamada.data.length === 0)) throw new Error("Não foi possível confirmar a alteração no banco.");
      await carregar();
      setSucesso(`Romaneio ${item.romaneio_oficial}: ${texto} registrado com sucesso.`);
    } catch (e) {
      setErro(e instanceof Error ? e.message : "Falha ao registrar a etapa.");
    } finally {
      setBaixando(null);
    }
  }
  async function criarPrestacao(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (criando || !/^\\d{12}$/.test(novoRomaneio) || !novaData) return;
    if (!window.confirm(`Cadastrar romaneio oficial ${novoRomaneio}, D0 ${novaData}? Confirme os dados no GreenMile antes de prosseguir.`)) return;
    setCriando(true);
    setErro("");
    setSucesso("");
    try {
      const {data,error} = await requireSupabase().rpc("sigo_criar_prestacao",{p_romaneio:novoRomaneio,p_d0:novaData});
      if (error) throw error;
      if (!data || (Array.isArray(data) && data.length===0)) throw new Error("Cadastro não confirmado no banco");
      setSucesso(`Romaneio ${novoRomaneio} cadastrado na fila de prestação.`);
      setNovoRomaneio("");setNovaData("");
      setFiltro("ATIVAS");
      await carregar();
    } catch(e) {setErro(e instanceof Error?e.message:"Erro ao cadastrar prestação.");}
    finally {setCriando(false);}
  }
  const lista = useMemo(()=> registros.map(r=>({...r,crit:criticidadePrestacao(r,hoje)})),[registros,hoje]);
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
        {sucesso && <p role="status" className="rounded-lg border border-emerald-500/30 p-3 text-sm text-emerald-500">{sucesso}</p>}
        {erro && <p role="alert" className="rounded-lg border border-destructive/30 p-3 text-sm text-destructive">Falha ao consultar: {erro}</p>}
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
          {([["Pendências ativas",contagens.total],["Críticos D+4",contagens.criticos],["Urgentes D+3",contagens.urgentes],["Alerta D+2",contagens.alertas],["Baixadas",contagens.concluidas]] as const).map(([nome,numero])=><div key={nome} className="rounded-lg bg-muted p-3"><p className="text-xs text-muted-foreground">{nome}</p><p className="mt-1 text-2xl font-semibold">{numero.toLocaleString("pt-BR")}</p></div>)}
        </div>
        <p className="text-xs text-muted-foreground">Data de referência: {hoje.split("-").reverse().join("/")}. A criticidade representa atraso de prestação, não status da entrega. Enviadas à JTI recebem baixa no SIGO e saem da fila ativa; a confirmação posterior da JTI permanece no histórico.</p>
      </section>
      <section className="rounded-xl border border-border bg-card p-5 space-y-3">
        <h2 className="font-semibold">Cadastrar prestação por romaneio oficial</h2>
        <p className="text-xs text-muted-foreground">Cadastro manual controlado para o piloto. Confira o romaneio de origem e a data D0 no GreenMile. Romaneios auxiliares não devem ser cadastrados como prestação fiscal.</p>
        <form onSubmit={e=>void criarPrestacao(e)} className="grid gap-3 sm:grid-cols-[1fr_1fr_auto] sm:items-end">
          <label className="space-y-1 text-sm">Romaneio oficial (12 dígitos)<input required maxLength={12} pattern="[0-9]{12}" value={novoRomaneio} onChange={e=>setNovoRomaneio(e.target.value.replace(/\\D/g,"").slice(0,12))} className="w-full rounded-md border border-input bg-background px-3 py-2" placeholder="000000000000" disabled={criando}/></label>
          <label className="space-y-1 text-sm">Data da rota (D0)<input required type="date" max={hoje} value={novaData} onChange={e=>setNovaData(e.target.value)} className="w-full rounded-md border border-input bg-background px-3 py-2" disabled={demo || criando}/></label>
          <button type="submit" disabled={criando || novoRomaneio.length!==12 || !novaData} className="rounded-md bg-primary px-4 py-2 font-semibold text-primary-foreground disabled:opacity-40">{criando?"Registrando...":"Cadastrar"}</button>
        </form>
          </section>
      <section className="rounded-xl border border-border bg-card p-5 space-y-4">
        <div className="flex flex-wrap gap-3">
          <input aria-label="Buscar romaneio" value={busca} onChange={e=>setBusca(e.target.value)} placeholder="Localizar romaneio (12 dígitos)" className="min-w-0 flex-1 rounded-md border border-input bg-background px-3 py-2 text-sm" />
          <select aria-label="Filtrar criticidade" value={filtro} onChange={e=>setFiltro(e.target.value)} className="rounded-md border border-input bg-background px-3 py-2 text-sm">
            <option value="ATIVAS">Pendências ativas</option><option value="TODAS">Todas (inclui histórico)</option><option value="CRITICO">Críticas</option><option value="URGENTE">Urgentes</option><option value="ALERTA">Alertas</option><option value="NO_PRAZO">No prazo</option><option value="CONCLUIDA">Baixadas / histórico</option><option value="FUTURA">Futuras</option>
          </select>
        </div>
        {carregando ? <p className="text-sm text-muted-foreground">Consultando Supabase...</p> : visiveis.length===0 ? <p className="rounded-lg bg-muted p-5 text-sm text-muted-foreground">{erro?"Não foi possível carregar os dados.":"Nenhuma prestação encontrada para este filtro. Nenhuma prestação encontrada. Importe arquivos GreenMile revisados ou cadastre um romaneio oficial."}</p> :
          <div className="overflow-x-auto"><table className="w-full min-w-[820px] text-left text-sm">
            <thead className="border-b border-border text-muted-foreground"><tr>{["Romaneio oficial","Data da rota (D0)","Vencimento (D+3)","Dias","Etapa","Criticidade","Responsável","Próxima ação"].map(t=><th key={t} className="px-3 py-3 font-medium">{t}</th>)}</tr></thead>
            <tbody>{visiveis.map(r=><tr key={r.id} className="border-b border-border/60">
              <td className="px-3 py-3 font-mono">{r.romaneio_oficial}</td><td className="px-3 py-3">{r.d0}</td><td className="px-3 py-3">{vencimentoD3(r.d0)}</td>
              <td className="px-3 py-3">{r.crit.dias>=0?`D+${r.crit.dias}`:"Futura"}</td><td className="px-3 py-3">{statusTexto[r.status]??r.status}</td>
              <td className={`px-3 py-3 font-medium ${tom[r.crit.nivel]??""}`}>{r.crit.rotulo}</td>
              <td className="px-3 py-3">{r.responsavel_id?"ID cadastrado":"Não definido"}</td>
              <td className="px-3 py-3">
                {(r.status === "ABERTA" || r.status === "RETORNADA" || r.status === "CONFERIDA") ?
                  <button type="button" disabled={!!baixando || carregando} onClick={()=>void avancar(r)} className="whitespace-nowrap rounded-md bg-primary px-3 py-2 text-xs font-semibold text-primary-foreground disabled:opacity-40">{baixando===r.id ? "Registrando..." : r.status === "ABERTA" ? "Registrar retorno" : r.status === "RETORNADA" ? "Conferir prestação" : "Dar baixa — Enviado à JTI"}</button> :
                  r.status === "ENVIADA_JTI" || r.status === "CONFIRMADA_JTI" ?
                    <span className="text-xs text-emerald-500">Baixada {r.enviada_em?new Date(r.enviada_em).toLocaleString("pt-BR",{timeZone:"America/Sao_Paulo"}):""}</span> :
                    <span className="text-xs text-muted-foreground">"Aguardando conferência"</span>}
              </td>
            </tr>)}</tbody>
          </table></div>}
        <p className="text-xs text-muted-foreground">Fluxo obrigatório: Aberta → Retornada → Conferida → Enviada JTI (baixa). O servidor registra usuário e horário em cada etapa; a demonstração nunca grava dados.</p>
      </section>
    </div>
  </AppShell>;
}
