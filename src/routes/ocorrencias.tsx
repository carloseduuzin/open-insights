import { useEffect, useMemo, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { AppShell } from "@/layout/AppShell";
import { requireSupabase } from "@/lib/supabase";

export const Route = createFileRoute("/ocorrencias")({
  head: () => ({ meta: [{ title: "Impactos Comerciais e Roteirização — SIGO" }] }),
  component: Ocorrencias,
});

type Ocorrencia = {
  id: string; data_rota: string; criado_em: string; codigo_cliente: string; cliente: string;
  nf: string; codigo_rota: string; romaneio: string | null; condutor: string | null;
  vendedor: string | null; tipo: string; saida: string; detalhe: string;
  sequencia_planejada: number | null; sequencia_executada: number | null;
  horario_restricao: string | null; impacto: string; acao_imediata: string | null;
  area_correcao: string; responsavel_tratativa: string | null; status: string;
  retorno_gestao: string | null;
};
type Campo = "data_rota" | "codigo_cliente" | "cliente" | "nf" | "codigo_rota" | "romaneio" |
  "condutor" | "vendedor" | "tipo" | "saida" | "sequencia_planejada" |
  "sequencia_executada" | "horario_restricao" | "detalhe" | "impacto" | "acao_imediata" |
  "area_correcao" | "responsavel_tratativa";

const tipos: Record<string,string> = {
  HORARIO_INCOMPATIVEL: "Horário incompatível com a saída",
  ENDERECO_INCORRETO: "Endereço incorreto",
  SEQUENCIA_INCORRETA: "Sequência de visitas inadequada",
  JANELA_ATENDIMENTO: "Restrição de dia/horário do PDV",
  OUTRO: "Outro impacto",
};
const impactos: Record<string,string> = {
  RISCO_REENTREGA: "Risco de reentrega", REENTREGA: "Reentrega gerada",
  ATRASO: "Atraso", DESVIO_ROTA: "Desvio de rota", SEM_IMPACTO: "Corrigido sem impacto",
};
const statusNome: Record<string,string> = {
  ABERTA:"Aberta", ENVIADA_GESTAO:"Enviada à gestão", EM_TRATATIVA:"Em tratativa",
  CORRIGIDA:"Corrigida", SEM_CORRECAO:"Sem correção confirmada",
};
const areas: Record<string,string> = {
  COMERCIAL:"Comercial / vendedor", ROTEIRIZACAO:"Roteirização",
  CADASTRO:"Cadastro do cliente", OPERACAO:"Operação", A_DEFINIR:"A definir",
};
const hoje = () => {
  const partes = new Intl.DateTimeFormat("en-CA",{timeZone:"America/Sao_Paulo",year:"numeric",month:"2-digit",day:"2-digit"}).formatToParts(new Date());
  const p=(chave:string)=>partes.find(x=>x.type===chave)?.value ?? "";
  return `${p("year")}-${p("month")}-${p("day")}`;
};
const inicial = () => ({
  data_rota: hoje(), codigo_cliente:"",cliente:"",nf:"",codigo_rota:"",romaneio:"",
  condutor:"",vendedor:"",tipo:"HORARIO_INCOMPATIVEL",saida:"PRIMEIRA",
  sequencia_planejada:"",sequencia_executada:"",horario_restricao:"",
  detalhe:"",impacto:"RISCO_REENTREGA",acao_imediata:"",
  area_correcao:"COMERCIAL",responsavel_tratativa:"",
});
const campoStyle="w-full min-w-0 rounded-md border border-input bg-background px-3 py-2 text-sm";
function Ocorrencias() {
  const [dados,setDados] = useState(inicial);
  const [itens,setItens] = useState<Ocorrencia[]>([]);
  const [carregando,setCarregando]=useState(true);
  const [salvando,setSalvando]=useState(false);
  const [erro,setErro]=useState("");
  const [aviso,setAviso]=useState("");
  const [busca,setBusca]=useState("");
  const [filtro,setFiltro]=useState("TODOS");
  const [dia,setDia]=useState(hoje());
  const [editando,setEditando]=useState<string|null>(null);
  const [novoStatus,setNovoStatus]=useState("EM_TRATATIVA");
  const [retorno,setRetorno]=useState("");
  const [responsavel,setResponsavel]=useState("");

  function atualizar(c:Campo,v:string){setDados(prev=>({...prev,[c]:v}));}
  async function carregar(){
    setCarregando(true);setErro("");
    try {
      const {data,error}=await requireSupabase().from("ocorrencias_roteirizacao")
        .select("*").order("criado_em",{ascending:false}).limit(1000);
      if(error)throw error;
      setItens((data??[]) as Ocorrencia[]);
    }catch(e){setErro(e instanceof Error?e.message:"Não foi possível carregar ocorrências");}
    finally{setCarregando(false);}
  }
  useEffect(()=>{void carregar();},[]);
  async function registrar(e:React.FormEvent<HTMLFormElement>){
    e.preventDefault();
    if(salvando)return;
    if(!window.confirm("Confirma o registro desta ocorrência real no SIGO?"))return;
    setSalvando(true);setErro("");setAviso("");
    try{
      const {data,error}=await requireSupabase().rpc("sigo_registrar_ocorrencia",{p_dados:dados});
      if(error)throw error;
      if(!data)throw new Error("O banco não confirmou o registro");
      setDados(inicial());setAviso("Ocorrência registrada. Inclua no feedback diário à gestão.");
      await carregar();
    }catch(ex){setErro(ex instanceof Error?ex.message:"Não foi possível registrar");}
    finally{setSalvando(false);}
  }
  async function tratar(id:string){
    if(salvando)return;
    setSalvando(true);setErro("");setAviso("");
    try{
      const {data,error}=await requireSupabase().rpc("sigo_tratar_ocorrencia",{
        p_id:id,p_status:novoStatus,p_retorno:retorno,p_responsavel:responsavel,
      });
      if(error)throw error;
      if(!data)throw new Error("Registro não encontrado");
      setEditando(null);setAviso("Tratativa atualizada.");await carregar();
    }catch(ex){setErro(ex instanceof Error?ex.message:"Falha ao atualizar");}
    finally{setSalvando(false);}
  }
  const filtrados=useMemo(()=>itens.filter(o=>
    (filtro==="TODOS"||o.status===filtro) &&
    (!busca.trim()||[o.codigo_cliente,o.cliente,o.nf,o.codigo_rota,o.romaneio,o.vendedor].some(v=>(v??"").toLowerCase().includes(busca.toLowerCase())))
  ),[itens,busca,filtro]);
  const doDia=itens.filter(o=>o.data_rota===dia);
  const abertos=itens.filter(o=>!["CORRIGIDA","SEM_CORRECAO"].includes(o.status)).length;
  const repetidos=useMemo(()=>{
    const contagem=new Map<string,number>();
    for(const o of itens)contagem.set(o.codigo_cliente,(contagem.get(o.codigo_cliente)??0)+1);
    return [...contagem].filter(([,q])=>q>1).sort((a,b)=>b[1]-a[1]).slice(0,8);
  },[itens]);
  const relatorio=()=>{
    const linhas=[
      `FEEDBACK DIÁRIO — IMPACTOS DE ROTEIRIZAÇÃO / COMERCIAL — ${dia.split("-").reverse().join("/")}`,
      "Destino: Gestão do Limão (Faustinho, Alexandre e Filipe) | Cópia: Coordenação JTI",
      `Ocorrências registradas: ${doDia.length}`,
      ...doDia.map((o,i)=>[
        `${i+1}. ${o.cliente} (cód. ${o.codigo_cliente}) | NF ${o.nf} | Rota ${o.codigo_rota} | ${o.saida} saída`,
        `   Problema: ${tipos[o.tipo]??o.tipo}. ${o.detalhe}`,
        `   Janela/restrição: ${o.horario_restricao??"não informada"} | Sequência prevista/real: ${o.sequencia_planejada??"—"}/${o.sequencia_executada??"—"}`,
        `   Impacto: ${impactos[o.impacto]??o.impacto} | Ação: ${o.acao_imediata??"não informada"}`,
        `   Direcionar: ${areas[o.area_correcao]??o.area_correcao} | Responsável: ${o.responsavel_tratativa??"a definir"} | Situação: ${statusNome[o.status]??o.status}`,
      ].join("\n")),
      "Solicitamos avaliação e ajuste cadastral/roteirização dos casos registrados para reduzir reentregas e desvios.",
    ];
    return linhas.join("\n\n");
  };
  async function copiar(){try{await navigator.clipboard.writeText(relatorio());setAviso("Feedback copiado. Revise e encaminhe pelos canais oficiais.");}catch{setErro("Não foi possível copiar automaticamente. Selecione e copie o texto no navegador.");}}
  function baixarCSV(){
    const colunas=["data_rota","codigo_cliente","cliente","nf","codigo_rota","romaneio","condutor","vendedor","tipo","saida","sequencia_planejada","sequencia_executada","horario_restricao","detalhe","impacto","acao_imediata","area_correcao","responsavel_tratativa","status","retorno_gestao"];
    const csv=[colunas.join(";"),...filtrados.map(o=>colunas.map(c=>`"${String(o[c as keyof Ocorrencia]??"").replace(/"/g,'""')}"`).join(";"))].join("\r\n");
    const blob=new Blob(["\uFEFF",csv],{type:"text/csv;charset=utf-8"});
    const url=URL.createObjectURL(blob);
    const a=document.createElement("a");a.href=url;a.download="sigo-impactos-comercial-roteirizacao.csv";a.click();URL.revokeObjectURL(url);
  }
  const campo=(nome:string,chave:Campo,obrigatorio=false,placeholder="")=><label className="space-y-1 text-sm">
    <span className="text-muted-foreground">{nome}</span>
    <input className={campoStyle} value={dados[chave]} onChange={e=>atualizar(chave,e.target.value)}
      required={obrigatorio} placeholder={placeholder}/>
  </label>;
  const selecionar=(nome:string,chave:Campo,opcoes:Record<string,string>)=><label className="space-y-1 text-sm">
    <span className="text-muted-foreground">{nome}</span>
    <select className={campoStyle} value={dados[chave]} onChange={e=>atualizar(chave,e.target.value)}>
      {Object.entries(opcoes).map(([v,t])=><option key={v} value={v}>{t}</option>)}
    </select>
  </label>;
  return <AppShell titulo="Impactos de Roteirização e Comercial" descricao="Torre de Controle 5.0 — prevenção de reentregas e base de ajustes">
    <div className="space-y-5">
      <section className="rounded-xl border border-border bg-card p-5 space-y-3">
        <h2 className="text-lg font-semibold">Trabalho de formiguinha — JTI / Renovelog ZL</h2>
        <p className="text-sm text-muted-foreground">Registre cada erro de endereço, janela de atendimento e sequência de visita. A base servirá de evidência para solicitações de parametrização ao Comercial e à Roteirização. O SIGO não modifica o GreenMile automaticamente.</p>
        {erro && <p role="alert" className="rounded-md border border-destructive/40 p-3 text-sm text-destructive">{erro}</p>}
        {aviso && <p role="status" className="rounded-md border border-emerald-500/40 p-3 text-sm text-emerald-500">{aviso}</p>}
        <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
          {[
            ["Ocorrências registradas",itens.length],["Aguardando solução",abertos],
            ["Ocorrências no dia",doDia.length],["Clientes recorrentes",repetidos.length],
          ].map(([titulo,valor])=><div key={titulo} className="rounded-lg bg-muted p-3">
            <p className="text-xs text-muted-foreground">{titulo}</p><p className="text-2xl font-semibold">{carregando?"—":valor}</p>
          </div>)}
        </div>
      </section>
      <section className="rounded-xl border border-border bg-card p-5">
        <h2 className="font-semibold">Registrar impacto operacional</h2>
        <p className="mt-1 text-xs text-muted-foreground">Uma ocorrência por problema identificado. Anote o que aconteceu de fato e o impacto para evitar reentrega.</p>
        <form className="mt-4 space-y-4" onSubmit={e=>void registrar(e)}>
          <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            <label className="space-y-1 text-sm"><span className="text-muted-foreground">Data da rota (D0)</span><input className={campoStyle} type="date" max={hoje()} required value={dados.data_rota} onChange={e=>atualizar("data_rota",e.target.value)}/></label>
            {campo("Código do cliente *","codigo_cliente",true)}
            {campo("Nome do cliente/PDV *","cliente",true)}
            {campo("NF *","nf",true)}
            {campo("Código da rota *","codigo_rota",true,"Ex.: SP-1MFV37")}
            {campo("Romaneio oficial (se houver)","romaneio")}
            {campo("Condutor","condutor")}
            {campo("Vendedor / contato comercial","vendedor")}
            {selecionar("Tipo do problema","tipo",tipos)}
            {selecionar("Saída","saida",{PRIMEIRA:"Primeira saída",SEGUNDA:"Segunda saída",OUTRA:"Outra"})}
            {campo("Sequência prevista no GM","sequencia_planejada",false,"Ex.: 3")}
            {campo("Posição realmente visitada","sequencia_executada",false,"Ex.: 19")}
            {campo("Horário/dia correto do cliente","horario_restricao",false,"Ex.: após 13h; não abre segunda")}
            {selecionar("Impacto","impacto",impactos)}
            {selecionar("Área que deve ajustar","area_correcao",areas)}
            {campo("Responsável pela tratativa","responsavel_tratativa",false,"Ex.: gestão Limão / vendedor")}
          </div>
          <div className="grid gap-3 md:grid-cols-2">
            <label className="space-y-1 text-sm"><span className="text-muted-foreground">O que aconteceu de fato? *</span>
              <textarea className={campoStyle} rows={3} required minLength={10} value={dados.detalhe} onChange={e=>atualizar("detalhe",e.target.value)}
                placeholder="Ex.: rota da primeira saída contém NF com recebimento somente depois das 13h; prestador não conseguiu concluir a visita."/></label>
            <label className="space-y-1 text-sm"><span className="text-muted-foreground">Ação imediata adotada</span>
              <textarea className={campoStyle} rows={3} value={dados.acao_imediata} onChange={e=>atualizar("acao_imediata",e.target.value)}
                placeholder="Ex.: contato com vendedor, ajuste de sequência, repasse ou segunda saída."/></label>
          </div>
          <button type="submit" disabled={salvando||carregando} className="rounded-md bg-primary px-5 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-50">{salvando?"Salvando...":"Registrar ocorrência"}</button>
        </form>
      </section>
      <section className="rounded-xl border border-border bg-card p-5 space-y-3">
        <h2 className="font-semibold">Feedback diário à gestão e à JTI</h2>
        <div className="flex flex-wrap items-end gap-3">
          <label className="space-y-1 text-sm"><span className="block text-muted-foreground">Data de referência</span><input className={campoStyle} type="date" value={dia} onChange={e=>setDia(e.target.value)}/></label>
          <button onClick={()=>void copiar()} className="rounded-md border border-border px-4 py-2 text-sm font-medium">Copiar feedback do dia</button>
          <button onClick={baixarCSV} className="rounded-md border border-border px-4 py-2 text-sm font-medium">Exportar base CSV</button>
        </div>
        <p className="text-xs text-muted-foreground">O relatório é preparado para revisão e envio manual ao time de gestão do Limão, com a coordenação JTI em cópia. O SIGO não envia e-mails automaticamente nesta versão.</p>
        <textarea className={campoStyle+" font-mono text-xs"} readOnly rows={6} value={relatorio()} aria-label="Prévia do feedback diário"/>
      </section>
      <section className="rounded-xl border border-border bg-card p-5 space-y-3">
        <h2 className="font-semibold">Acompanhamento das tratativas</h2>
        <div className="flex flex-wrap gap-2">
          <input className={campoStyle+" flex-1"} placeholder="Buscar cliente, código, rota, NF ou vendedor" value={busca} onChange={e=>setBusca(e.target.value)} aria-label="Buscar ocorrência"/>
          <select className={campoStyle+" max-w-[220px]"} value={filtro} onChange={e=>setFiltro(e.target.value)} aria-label="Filtrar status">
            <option value="TODOS">Todos os status</option>{Object.entries(statusNome).map(([v,n])=><option key={v} value={v}>{n}</option>)}
          </select>
          <button onClick={()=>void carregar()} className="rounded-md border border-border px-3 text-sm">Atualizar</button>
        </div>
        {carregando ? <p className="text-sm text-muted-foreground">Consultando ocorrências...</p> :
          filtrados.length===0 ? <p className="rounded-md bg-muted p-5 text-sm text-muted-foreground">Nenhuma ocorrência encontrada. Comece registrando um problema real da rota.</p> :
          <div className="space-y-3">
            {filtrados.map(o=><div key={o.id} className="rounded-lg border border-border p-4 space-y-2 text-sm">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <strong>{o.cliente} • {o.codigo_cliente}</strong>
                <span className="rounded-md bg-muted px-2 py-1 text-xs">{statusNome[o.status]??o.status}</span>
              </div>
              <p className="text-muted-foreground">{o.data_rota} • NF {o.nf} • {o.codigo_rota} • {o.saida} saída • {tipos[o.tipo]??o.tipo}</p>
              <p>{o.detalhe}</p>
              <p className="text-muted-foreground">Impacto: {impactos[o.impacto]??o.impacto} | Direcionar: {areas[o.area_correcao]??o.area_correcao} | Responsável: {o.responsavel_tratativa??"não definido"}</p>
              {o.retorno_gestao && <p className="rounded-md bg-muted p-2">Retorno: {o.retorno_gestao}</p>}
              {editando===o.id ? <div className="grid gap-2 md:grid-cols-3">
                <select className={campoStyle} value={novoStatus} onChange={e=>setNovoStatus(e.target.value)}>{Object.entries(statusNome).map(([v,n])=><option key={v} value={v}>{n}</option>)}</select>
                <input className={campoStyle} placeholder="Responsável" value={responsavel} onChange={e=>setResponsavel(e.target.value)}/>
                <input className={campoStyle} placeholder="Retorno / correção aplicada" value={retorno} onChange={e=>setRetorno(e.target.value)}/>
                <div className="flex gap-2"><button disabled={salvando} onClick={()=>void tratar(o.id)} className="rounded-md bg-primary px-3 py-2 text-primary-foreground">Salvar tratativa</button><button onClick={()=>setEditando(null)} className="rounded-md border px-3 py-2">Cancelar</button></div>
              </div> : <button onClick={()=>{setEditando(o.id);setNovoStatus(o.status);setResponsavel(o.responsavel_tratativa??"");setRetorno(o.retorno_gestao??"");}} className="rounded-md border border-border px-3 py-2 text-xs">Atualizar tratativa</button>}
            </div>)}
          </div>}
        {repetidos.length>0 && <div className="mt-4 rounded-md bg-muted p-3">
          <h3 className="font-semibold">Clientes com recorrência</h3>
          <p className="mt-1 text-xs text-muted-foreground">{repetidos.map(([codigo,n])=>`${codigo} (${n} ocorrências)`).join(" • ")}</p>
        </div>}
      </section>
    </div>
  </AppShell>;
}
