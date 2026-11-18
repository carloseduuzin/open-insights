import { useMemo, useRef, useState, type FormEvent } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { createFileRoute } from "@tanstack/react-router";
import { AppShell } from "@/layout/AppShell";
import { requireSupabase } from "@/lib/supabase";
import { avaliarPresenca, avaliarEntregas, rascunhoCondutor, regrasIniciais, type Condutor, type Regras } from "@/lib/efetividade-condutores";

export const Route=createFileRoute("/romaneios")({head:()=>({meta:[{title:"Condutores e efetividade — SIGO"}]}),component:Romaneios});
type Painel={condutores:Condutor[];regras:Regras;entrega_configurada:boolean};
const rotulos:Record<string,string>={ESCALADO:"Escalado — aguardando confirmação",PRESENTE:"Presente no horário",ATRASO:"Presente com atraso",FALTA:"Falta sem justificativa",FALTA_JUSTIFICADA:"Falta justificada",FOLGA:"Folga"};
function hojeSP(){const partes=new Intl.DateTimeFormat("en-CA",{timeZone:"America/Sao_Paulo",year:"numeric",month:"2-digit",day:"2-digit"}).formatToParts(new Date());const get=(t:string)=>partes.find(p=>p.type===t)?.value;return `${get("year")}-${get("month")}-${get("day")}`;}
function diasAntes(iso:string,dias:number){const d=new Date(iso+"T12:00:00Z");d.setUTCDate(d.getUTCDate()-dias);return d.toISOString().slice(0,10);}
function erroTexto(e:unknown){return e&&typeof e==="object"&&"message" in e&&typeof e.message==="string"?e.message:"Não foi possível confirmar a operação.";}
const percentual=(n:number|null)=>n===null?"Sem avaliação":`${n.toFixed(1)}%`;

function Romaneios(){
 const hoje=hojeSP();const clientCache=useQueryClient();
 const [inicio,setInicio]=useState(()=>diasAntes(hoje,6));const [fim,setFim]=useState(hoje);const [busca,setBusca]=useState("");
 const [nome,setNome]=useState("");const [dia,setDia]=useState(hoje);const [situacao,setSituacao]=useState("ESCALADO");const [minutos,setMinutos]=useState("");const [observacao,setObservacao]=useState("");
 const presencaRef=useRef<HTMLElement|null>(null);const mensagemRef=useRef<HTMLElement|null>(null);
 const [gravando,setGravando]=useState(false);const [erro,setErro]=useState("");const [aviso,setAviso]=useState("");const [rascunho,setRascunho]=useState("");const [destinoNome,setDestinoNome]=useState("");
 const periodoValido=Boolean(inicio&&fim&&fim>=inicio&&(Date.parse(fim)-Date.parse(inicio))/86400000<=92);
 const consulta=useQuery({queryKey:["sigo-efetividade",inicio,fim],enabled:periodoValido,queryFn:async()=>{
  const {data,error}=await requireSupabase().rpc("sigo_consultar_efetividade",{p_inicio:inicio,p_fim:fim});if(error)throw error;
  if(!data||!Array.isArray(data.condutores))throw new Error("O banco não confirmou os dados dos condutores.");return data as Painel;
 },staleTime:15_000,retry:false});
 const regras=consulta.data?.regras??regrasIniciais;
 const linhas=useMemo(()=>(consulta.data?.condutores??[]).map(c=>({...c,presenca:avaliarPresenca(c.frequencias,regras),entrega:avaliarEntregas(c)})).sort((a,b)=>Number(b.presenca.classificavel)-Number(a.presenca.classificavel)||(b.presenca.classificavel&&a.presenca.classificavel?(b.presenca.indice??0)-(a.presenca.indice??0):0)||a.nome.localeCompare(b.nome)),[consulta.data,regras]);
 const visiveis=linhas.filter(c=>c.nome.toLocaleLowerCase("pt-BR").includes(busca.toLocaleLowerCase("pt-BR")));
 const totais=linhas.reduce((a,c)=>({presentes:a.presentes+c.presenca.presentes+c.presenca.atrasos,faltas:a.faltas+c.presenca.faltas,atrasos:a.atrasos+c.presenca.atrasos,semResultado:a.semResultado+c.sem_resultado}),{presentes:0,faltas:0,atrasos:0,semResultado:0});
 const condutorSelecionado=linhas.find(c=>c.nome===nome.trim());const historico=condutorSelecionado?.frequencias??[];
 const input="w-full rounded-md border border-input bg-background px-3 py-2 text-sm";
 const botao="rounded-md border border-border px-3 py-2 text-sm font-medium disabled:opacity-40";
 function selecionar(condutor:string,data=hoje){const f=linhas.find(c=>c.nome===condutor)?.frequencias.find(f=>f.data===data);setNome(condutor);setDia(data);setSituacao(f?.situacao??"ESCALADO");setMinutos(f?.minutos_atraso?String(f.minutos_atraso):"");setObservacao(f?.observacao??"");setErro("");setAviso("");}
 function abrirPresenca(condutor:string){selecionar(condutor);presencaRef.current?.scrollIntoView({behavior:"smooth",block:"start"});presencaRef.current?.focus({preventScroll:true});}
 async function salvar(e:FormEvent<HTMLFormElement>){e.preventDefault();if(gravando||!nome.trim()||!dia)return;setGravando(true);setErro("");setAviso("");
  try{const {data,error}=await requireSupabase().rpc("sigo_registrar_frequencia",{p_nome:nome.trim(),p_data:dia,p_situacao:situacao,p_minutos_atraso:situacao==="ATRASO"?Number(minutos):0,p_observacao:observacao.trim()||null});if(error)throw error;if(!data?.registrada)throw new Error("O banco não confirmou a presença.");
   setAviso(data.alterada?"Lançamento salvo com usuário, horário e histórico de alteração.":"Este lançamento já estava salvo. Nenhuma alteração duplicada foi criada.");
   await clientCache.invalidateQueries({queryKey:["sigo-efetividade"]});
  }catch(e){setErro(erroTexto(e));}finally{setGravando(false);}
 }
 function mensagem(c:Condutor){setDestinoNome(c.nome);setRascunho(rascunhoCondutor(c,inicio,fim,regras));setAviso("");requestAnimationFrame(()=>{mensagemRef.current?.scrollIntoView({behavior:"smooth",block:"start"});mensagemRef.current?.focus({preventScroll:true});});}
 async function copiar(){try{await navigator.clipboard.writeText(rascunho);setAviso("Mensagem copiada. Revise o destinatário antes de enviar.");}catch{setErro("Não foi possível copiar. Selecione o texto e copie manualmente.");}}
 return <AppShell titulo="Condutores e efetividade" descricao="Presença manual, metas e evolução das entregas"><div className="space-y-5">
  <section className="rounded-xl border border-border bg-card p-5 space-y-4">
   <div className="flex flex-wrap justify-between gap-3"><div><h2 className="font-semibold">🏆 Placar dos condutores</h2><p className="text-sm text-muted-foreground">Acompanhe evolução e combine objetivos com cada condutor.</p></div><button type="button" className={botao} disabled={consulta.isFetching||!periodoValido} onClick={()=>void consulta.refetch()}>Atualizar placar</button></div>
   <div className="grid gap-3 sm:grid-cols-3"><label className="text-sm space-y-1">Início<input type="date" value={inicio} onChange={e=>setInicio(e.target.value)} className={input}/></label><label className="text-sm space-y-1">Fim<input type="date" value={fim} onChange={e=>setFim(e.target.value)} className={input}/></label><label className="text-sm space-y-1">Buscar condutor<input value={busca} onChange={e=>setBusca(e.target.value)} placeholder="Nome do condutor" className={input}/></label></div>
   {!periodoValido&&<p role="alert" className="text-amber-500">Escolha um período de até 93 dias.</p>}
   {consulta.isPending&&periodoValido&&<p role="status">Consultando condutores e lançamentos...</p>}
   {consulta.isError&&<p role="alert" className="text-destructive">{erroTexto(consulta.error)} O controle é restrito ao administrador.</p>}
   {consulta.data&&!consulta.isError&&<>
    <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">{[["Condutores no período",linhas.length],["Presenças confirmadas",totais.presentes],["Atrasos registrados",totais.atrasos],["Faltas sem justificativa",totais.faltas]].map(([label,value])=><div key={label} className="rounded-lg bg-muted p-4"><p className="text-xs text-muted-foreground">{label}</p><p className="mt-1 text-2xl font-semibold">{value}</p></div>)}</div>
    <details className="rounded-lg border border-border p-3 text-sm"><summary className="cursor-pointer font-medium">Regras do jogo e metas</summary><p className="mt-2">Presente no horário: {regras.pontos_presente} pontos. Atraso: {regras.pontos_atraso}. Falta sem justificativa: {regras.pontos_falta}. Folgas, justificadas e dias ainda não confirmados ficam fora da nota.</p><p className="mt-2">A classificação começa com {regras.minimo_dias_classificar} dias avaliados. Meta inicial de presença: {regras.meta_presenca}%. Os pontos são proporcionais aos dias avaliados; o volume de rotas não aumenta a nota de presença.</p><p className="mt-2">Entregas são medidas por parada com NF vinculada, evitando contar várias NFs do mesmo atendimento como entregas diferentes. Resultados de cliente/operação não descontam pontos de presença. O placar apoia a conversa e deve ser analisado com o contexto de cada rota.</p></details>
    {(!consulta.data.entrega_configurada||totais.semResultado>0)&&<p className="rounded-lg border border-amber-500/40 p-3 text-sm text-amber-500">{totais.semResultado} parada(s) ainda sem resultado de entrega confirmado. O placar de entregas fica sem avaliação ou parcial até importar e mapear os resultados do GreenMile. Rota concluída ou canhoto recebido não comprova entrega.</p>}
    {linhas.length===0?<p>Nenhum condutor identificado nesse período. Você pode lançar a presença pelo nome completo abaixo.</p>:<div className="overflow-x-auto"><table className="w-full min-w-[950px] text-left text-sm"><thead><tr>{["Condutor / evolução","Presença","Atrasos / faltas","Pontos de presença","Rotas / entregas","Ações"].map(t=><th key={t} className="p-2">{t}</th>)}</tr></thead><tbody>{visiveis.map(c=><tr key={c.nome} className="border-t border-border"><td className="p-3"><strong>{c.nome}</strong><div className={c.presenca.faixa==="Meta atingida"?"text-emerald-500":c.presenca.faixa==="Acompanhar"?"text-amber-500":"text-muted-foreground"}>{c.presenca.faixa==="Meta atingida"?"🏅 ":""}{c.presenca.faixa}</div></td>
     <td className="p-3">{percentual(c.presenca.frequencia)}<div className="text-xs text-muted-foreground">{c.presenca.avaliados} dia(s) avaliados · {c.presenca.pendentes} aguardando confirmação</div></td><td className="p-3">{c.presenca.atrasos} atraso(s)<div>{c.presenca.faltas} falta(s) sem justificativa</div><div className="text-xs text-muted-foreground">{c.presenca.justificadas} justificada(s)</div></td>
     <td className="p-3">{c.presenca.avaliados?`${c.presenca.pontos} pontos · ${percentual(c.presenca.indice)}`:"Sem lançamentos"}{c.presenca.indice!==null&&<progress aria-label={`Índice de presença de ${c.nome}`} max={100} value={c.presenca.indice} className="mt-2 h-2 w-36 accent-emerald-500"/>}</td>
     <td className="p-3">{c.rotas} rota(s) · {c.paradas} parada(s)<div>{c.entrega.indice===null?"Entregas: sem avaliação":`${percentual(c.entrega.indice)} de efetividade${c.entrega.completo?"":" parcial"}`}</div>{c.entrega.indice!==null&&<div className="text-xs text-muted-foreground">{c.entregues} entregue(s) · {c.nao_entregues} não entregue(s) · {c.sem_resultado} sem resultado</div>}<div className="text-xs text-muted-foreground">Reentregas: cliente {c.reentregas_cliente} · operação {c.reentregas_operacao}</div></td>
     <td className="p-3 space-y-2"><button type="button" className={botao} onClick={()=>abrirPresenca(c.nome)}>Lançar presença</button><button type="button" className={botao} onClick={()=>mensagem(c)}>Preparar WhatsApp</button></td></tr>)}</tbody></table></div>}
   </>}
  </section>
  <section ref={presencaRef} tabIndex={-1} aria-label="Lançamento manual de presença" className="scroll-mt-20 rounded-xl border border-border bg-card p-5 space-y-4"><h2 className="font-semibold">Lançamento manual de presença</h2><p className="text-sm text-muted-foreground">Use sempre o mesmo nome completo do GreenMile. Nomes iguais podem representar pessoas diferentes; confirme a identidade antes de lançar ou compartilhar o acompanhamento.</p>
   <form onSubmit={e=>void salvar(e)} className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3"><fieldset disabled={gravando} className="contents">
    <label className="space-y-1 text-sm">Condutor<input required list="nomes-condutores" value={nome} onChange={e=>{setNome(e.target.value);setSituacao("ESCALADO");setMinutos("");setObservacao("");setAviso("");}} maxLength={160} className={input} placeholder="Selecione ou informe o nome completo"/><datalist id="nomes-condutores">{linhas.map(c=><option key={c.nome} value={c.nome}/>)}</datalist></label>
    <label className="space-y-1 text-sm">Data<input required type="date" value={dia} onChange={e=>selecionar(nome,e.target.value)} className={input}/></label>
    <label className="space-y-1 text-sm">Situação<select value={situacao} onChange={e=>setSituacao(e.target.value)} className={input}>{Object.entries(rotulos).map(([v,t])=><option key={v} value={v}>{t}</option>)}</select></label>
    {situacao==="ATRASO"&&<label className="space-y-1 text-sm">Minutos de atraso<input required type="number" min={1} max={1440} value={minutos} onChange={e=>setMinutos(e.target.value)} className={input}/></label>}
    <label className="space-y-1 text-sm sm:col-span-2">Observação / motivo da correção<textarea value={observacao} onChange={e=>setObservacao(e.target.value)} required={situacao==="FALTA_JUSTIFICADA"} className={input}/></label>
    <div><button type="submit" disabled={gravando||!nome.trim()||!dia} className="rounded-md bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-40">{gravando?"Salvando...":"Salvar presença"}</button></div>
   </fieldset></form>
   {erro&&<p role="alert" className="text-destructive">{erro}</p>}{aviso&&<p role="status" className="text-emerald-500">{aviso}</p>}
   {!!historico.length&&<details><summary className="cursor-pointer text-sm">Ver lançamentos de {nome}</summary><ul className="mt-2 space-y-2 text-sm">{historico.map(f=><li key={f.id||f.data}><button type="button" onClick={()=>selecionar(nome,f.data)} className="underline">{f.data}</button> — {rotulos[f.situacao]||f.situacao}{f.minutos_atraso?` · ${f.minutos_atraso} minutos`:""}{f.observacao?` · ${f.observacao}`:""}</li>)}</ul></details>}
  </section>
  {rascunho&&<section ref={mensagemRef} tabIndex={-1} aria-label="Rascunho de WhatsApp" className="scroll-mt-20 rounded-xl border border-emerald-600/40 bg-card p-5 space-y-3"><h2 className="font-semibold">Mensagem para {destinoNome}</h2><p className="text-sm text-muted-foreground">Revise o texto, os motivos e o destinatário. O SIGO prepara a mensagem; você confirma o envio no WhatsApp.</p><textarea aria-label="Mensagem para revisar" value={rascunho} onChange={e=>setRascunho(e.target.value)} rows={12} className={input}/><div className="flex flex-wrap gap-3"><button type="button" className={botao} onClick={()=>void copiar()}>Copiar mensagem</button><a href={`https://wa.me/?text=${encodeURIComponent(rascunho)}`} target="_blank" rel="noopener noreferrer" className="rounded-md bg-emerald-700 px-4 py-2 text-sm font-semibold text-white">Abrir WhatsApp com rascunho</a></div></section>}
 </div></AppShell>;
}
