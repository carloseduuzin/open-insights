import { useMemo, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { AppShell } from "@/layout/AppShell";
import { lerCSV, type Linha } from "@/lib/greenmile-import";

export const Route = createFileRoute("/rotas")({
  head: () => ({ meta: [{ title: "Controle de KM e Produtividade — SIGO | RenoveLog" }] }),
  component: Rotas,
});

type Arquivo = { nome: string; linhas: Linha[] };
type MotoristaDia = {
  chave: string; dia: string; nome: string; rotas: string[]; planejado: number;
  realizadoGM: number; kmSuspeitos: string[]; varejo: number; grocery: number;
  semCategoria: number; insucessos: number; pdvs: number; potencial: number; groceryPorTempo: number; divergenciasCategoria: number;
};
const real = (v: string) => {
  const n = Number((v ?? "").trim().replace(",", "."));
  return Number.isFinite(n) ? n : 0;
};
const dinheiro = (n:number) => n.toLocaleString("pt-BR",{style:"currency",currency:"BRL"});
const km = (n:number) => n.toLocaleString("pt-BR",{minimumFractionDigits:1,maximumFractionDigits:1})+" km";
const formatado = (dia:string) => dia.split("-").reverse().join("/");
const campo = "rounded-md border border-input bg-background px-3 py-2 text-sm";
const requisitosRoute = ["Código","Descrição","Distância planejada","Distância realizada","Motoristas","Saída planejada"];
const requisitosStop = ["Código da rota","Código da Localidade","Instruções de localização","Motivo de Entrega s/ Sucesso","Tempo de Atendimento Planejado","Data da Rota","Organização"];
const nomeNormalizado = (s:string) => s.trim().replace(/\s+/g," ").toUpperCase();
const isMoto = (codigo:string) => /^SP-[12]MFV/i.test(codigo);
const dateRoute = (r:Linha) => (r["Saída planejada"] || "").slice(0,10);
const isAuxiliar = (r:Linha) => (r["Descrição"] || "").startsWith("333") || (r["Descrição"] || "").startsWith("6000000000");
const hoje = () => {
  const p = new Intl.DateTimeFormat("en-CA",{year:"numeric",month:"2-digit",day:"2-digit",timeZone:"America/Sao_Paulo"}).formatToParts(new Date());
  const get = (t:string) => p.find(x=>x.type===t)?.value || "";
  return get("year")+"-"+get("month")+"-"+get("day");
};

function Rotas() {
  const [rv,setRV] = useState<Arquivo|null>(null);
  const [sv,setSV] = useState<Arquivo|null>(null);
  const [erro,setErro] = useState("");
  const [data,setData] = useState("");
  const [busca,setBusca] = useState("");
  const [odometros,setOdometros] = useState<Record<string,{inicio:string;fim:string}>>({});
  const [somenteAlertas,setSomenteAlertas] = useState(false);

  async function ler(file:File|undefined,tipo:"R"|"S"){
    if(!file)return;
    setErro("");
    try{
      if(file.size>35*1024*1024)throw new Error("Arquivo acima de 35 MB.");
      const csv=lerCSV(await file.text());
      const obrigatorias=tipo==="R"?requisitosRoute:requisitosStop;
      const faltantes=obrigatorias.filter(c=>!csv.colunas.includes(c));
      if(faltantes.length)throw new Error("Arquivo incorreto. Colunas ausentes: "+faltantes.join(", "));
      if(tipo==="R")setRV({nome:file.name,linhas:csv.linhas});
      else setSV({nome:file.name,linhas:csv.linhas});
      setData("");setOdometros({});
    }catch(e){setErro(e instanceof Error?e.message:"Não foi possível ler o CSV");}
  }

  const analise=useMemo(()=>{
    if(!rv || !sv)return null;
    const rotas=rv.linhas.filter(r=>isMoto(r["Código"]??"") && !isAuxiliar(r) && (r["Motoristas"]??"").trim());
    const datas=[...new Set(rotas.map(dateRoute).filter(Boolean))].sort().reverse();
    const stopPorRota=new Map<string,Linha[]>();
    for(const parada of sv.linhas){
      if((parada["Organização"]??"").trim()!=="RENOVELOG-ZL")continue;
      const chave=(parada["Data da Rota"]??"").slice(0,10)+"|"+(parada["Código da rota"]??"").trim();
      const grupo=stopPorRota.get(chave)??[];
      grupo.push(parada);stopPorRota.set(chave,grupo);
    }
    const agrupado=new Map<string,{dia:string;nome:string;rotas:string[];planejado:number;realizadoGM:number;kmSuspeitos:string[];pdvs:Map<string,{tipo:string;insucesso:boolean;porTempo:boolean;divergente:boolean}>;insucessos:number;semCategoria:number}>();
    for(const r of rotas){
      const dia=dateRoute(r); const nome=nomeNormalizado(r["Motoristas"]??"");
      const chave=dia+"|"+nome; const codigo=(r["Código"]??"").trim();
      if(!dia || !nome)continue;
      const obj=agrupado.get(chave)??{dia,nome,rotas:[] as string[],planejado:0,realizadoGM:0,kmSuspeitos:[] as string[],pdvs:new Map<string,{tipo:string;insucesso:boolean;porTempo:boolean;divergente:boolean}>(),insucessos:0,semCategoria:0};
      obj.rotas.push(codigo);obj.planejado+=real(r["Distância planejada"]??"");
      const valor=(r["Distância realizada"]??"").trim();
      const realizado=real(valor);
      obj.realizadoGM+=realizado;
      if(!valor || realizado<1) obj.kmSuspeitos.push(codigo);
      for(const s of stopPorRota.get(dia+"|"+codigo)??[]){
        const local=(s["Código da Localidade"]??"").trim();
        const tipoGM=(s["Instruções de localização"]??"").trim().toLowerCase();
        const porTempo=real(s["Tempo de Atendimento Planejado"]??"")>=3600;
        const tipo=porTempo?"grocery":tipoGM;
        const divergente=porTempo && tipoGM==="varejo";
        const semSucesso=Boolean((s["Motivo de Entrega s/ Sucesso"]??"").trim());
        if(semSucesso)obj.insucessos++;
        if(tipo!=="grocery" && tipo!=="varejo")obj.semCategoria++;
        if(!local || (tipo!=="grocery" && tipo!=="varejo") || semSucesso)continue;
        const pdv=obj.pdvs.get(local);
        if(!pdv)obj.pdvs.set(local,{tipo,insucesso:false,porTempo,divergente});
        else { if(tipo==="grocery")pdv.tipo="grocery"; pdv.porTempo ||= porTempo; pdv.divergente ||= divergente; }
      }
      agrupado.set(chave,obj);
    }
    const pessoas:MotoristaDia[]=[...agrupado.entries()].map(([chave,v])=>{
      const pdvs=[...v.pdvs.values()];
      const grocery=pdvs.filter(p=>p.tipo==="grocery").length;
      const varejo=pdvs.filter(p=>p.tipo==="varejo").length;
      const groceryPorTempo=pdvs.filter(p=>p.porTempo).length;
      const divergenciasCategoria=pdvs.filter(p=>p.divergente).length;
      return {chave,dia:v.dia,nome:v.nome,rotas:v.rotas,planejado:v.planejado,realizadoGM:v.realizadoGM,
        kmSuspeitos:v.kmSuspeitos,varejo,grocery,pdvs:pdvs.length,semCategoria:v.semCategoria,
        insucessos:v.insucessos,potencial:varejo*7+grocery*35,groceryPorTempo,divergenciasCategoria};
    });
    pessoas.sort((a,b)=>b.planejado-a.planejado);
    return {datas,pessoas,rotas:rotas.length,paradas:sv.linhas.length};
  },[rv,sv]);

  const diaAtivo=data || analise?.datas[0] || hoje();
  const lista=useMemo(()=>{
    const d=analise?.pessoas.filter(p=>p.dia===diaAtivo && (p.nome.toLowerCase().includes(busca.toLowerCase())||p.rotas.some(r=>r.toLowerCase().includes(busca.toLowerCase()))))??[];
    if(!somenteAlertas)return d;
    return d.filter(p=>{
      const o=odometros[p.chave],validado=o?.inicio.trim()!==""&&o?.fim.trim()!==""&&Number(o?.fim)>=Number(o?.inicio);
      return p.planejado>150 || (validado?Number(o?.fim)-Number(o?.inicio)>150:p.kmSuspeitos.length>0);
    });
  },[analise,diaAtivo,busca,somenteAlertas,odometros]);

  const visiveis=analise?.pessoas.filter(p=>p.dia===diaAtivo)??[];
  const previsto=visiveis.reduce((s,p)=>s+p.planejado,0);
  const potenciais=visiveis.reduce((s,p)=>s+p.potencial,0);
  const excedentes=visiveis.filter(p=>p.planejado>150).length;
  const divergenciasCategoria=visiveis.reduce((s,p)=>s+p.divergenciasCategoria,0);
  function marcar(chave:string,campo:"inicio"|"fim",valor:string){
    if(valor!=="" && (!/^\d+(\.\d{0,2})?$/.test(valor) || Number(valor)>9999999))return;
    setOdometros(a=>({...a,[chave]:{inicio:a[chave]?.inicio??"",fim:a[chave]?.fim??"",[campo]:valor}}));
  }
  function exportar(){
    const colunas=["Data","Motociclista","Rotas","KM planejado","KM GreenMile","KM fisico validado","Varejos candidatos","Grocery candidatos","Grocery por tempo >= 3600s","Divergências tempo vs GM","Insucessos no arquivo","Valor potencial R$","Observacoes"];
    const linhas=visiveis.map(p=>{
      const o=odometros[p.chave];
      const medido=o?.inicio!=="" && o?.fim!=="" && o && Number(o.fim)>=Number(o.inicio) ? (Number(o.fim)-Number(o.inicio)).toFixed(2) : "";
      return [p.dia,p.nome,p.rotas.join(" / "),p.planejado.toFixed(3),p.realizadoGM.toFixed(3),medido,
        String(p.varejo),String(p.grocery),String(p.groceryPorTempo),String(p.divergenciasCategoria),String(p.insucessos),p.potencial.toFixed(2),p.kmSuspeitos.length?"KM GM incompleto: "+p.kmSuspeitos.join(", "):""];
    });
    const csv=[colunas,...linhas].map(row=>row.map(v=>'"'+String(v).replace(/"/g,'""')+'"').join(";")).join("\r\n");
    const blob=new Blob(["\uFEFF",csv],{type:"text/csv;charset=utf-8"});
    const url=URL.createObjectURL(blob);const a=document.createElement("a");
    a.href=url;a.download="sigo-km-produtividade-"+diaAtivo+".csv";a.click();URL.revokeObjectURL(url);
  }

  return <AppShell titulo="Rotas • Controle de KM e Produtividade" descricao="1ª + 2ª saída por motoca — comparativo planejado x realizado">
    <div className="space-y-5">
      <section className="rounded-xl border border-border bg-card p-5 space-y-3">
        <h2 className="text-lg font-semibold">Importação GreenMile — análise de KM</h2>
        <p className="text-sm text-muted-foreground">Carregue o RouteView e o StopView (Paradas) do mesmo período. A análise ocorre neste navegador; não grava dados no Supabase nem substitui a conferência da remuneração.</p>
        <div className="grid gap-3 md:grid-cols-2">
          <label className="space-y-2 text-sm">RouteView — rotas
            <input type="file" accept=".csv,text/csv" className="block w-full rounded-md border border-input p-2" onChange={e=>void ler(e.target.files?.[0],"R")}/>
            {rv&&<span className="block text-xs text-muted-foreground">{rv.nome} • {rv.linhas.length} rotas</span>}
          </label>
          <label className="space-y-2 text-sm">StopView — Paradas
            <input type="file" accept=".csv,text/csv" className="block w-full rounded-md border border-input p-2" onChange={e=>void ler(e.target.files?.[0],"S")}/>
            {sv&&<span className="block text-xs text-muted-foreground">{sv.nome} • {sv.linhas.length} paradas</span>}
          </label>
        </div>
        {erro&&<p role="alert" className="rounded-md border border-destructive/40 p-3 text-sm text-destructive">{erro}</p>}
        <p className="text-xs text-muted-foreground">A classificação de moto é inferida dos códigos de rota SP-1MFV/SP-2MFV. Rotas de Fiorino, auxiliares e sem condutor ficam fora deste cálculo. Se algum código mudar, revise o filtro antes de fechar os pagamentos.</p>
      </section>
      {analise&&<div className="space-y-5">
        <section className="rounded-xl border border-border bg-card p-5 space-y-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h2 className="text-lg font-semibold">Produtividade diária por motociclista</h2>
            <label className="text-sm">Data da operação
              <select className={campo+" ml-2"} value={diaAtivo} onChange={e=>setData(e.target.value)}>
                {analise.datas.map(d=><option key={d} value={d}>{formatado(d)}</option>)}
              </select>
            </label>
          </div>
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            {[
              ["Motociclistas",visiveis.length],
              ["KM planejado",km(previsto)],
              ["Planejados acima 150 km",excedentes],
              ["Pagamento potencial",dinheiro(potenciais)],
              ["Divergências Grocery / GM",divergenciasCategoria],
            ].map(([titulo,valor])=><div className="rounded-md bg-muted p-3" key={titulo}>
              <p className="text-xs text-muted-foreground">{titulo}</p><p className="mt-1 text-xl font-semibold">{valor}</p>
            </div>)}
          </div>
          <p className="text-xs text-amber-500">Os valores de R$ 7 (Varejo) e R$ 35 (Grocery) são simulações de pagamento por PDV distinto do mesmo condutor no dia. Tempo de atendimento planejado a partir de 3.600 segundos indica Grocery candidato; divergências com a etiqueta do GreenMile ficam sinalizadas para conferência. NF sem motivo de insucesso não comprova entrega. Não usar para folha ou faturamento sem conferência dos canhotos/status e regras contratuais.</p>
        </section>
        <section className="rounded-xl border border-border bg-card p-5 space-y-4">
          <div className="flex flex-wrap items-center gap-3">
            <input className={campo+" flex-1"} value={busca} onChange={e=>setBusca(e.target.value)} placeholder="Filtrar por motoca ou rota" aria-label="Buscar motociclista"/>
            <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={somenteAlertas} onChange={e=>setSomenteAlertas(e.target.checked)}/>Somente alertas</label>
            <button type="button" className="rounded-md border border-border px-3 py-2 text-sm" onClick={exportar}>Exportar CSV</button>
          </div>
          <div className="overflow-x-auto">
            <table className="min-w-[1100px] w-full text-left text-sm">
              <thead className="border-b border-border text-muted-foreground">
                <tr>{["Motociclista / rotas","KM planejado JTI","KM realizado GM","KM físico (hodômetro)","PDVs candidatos","Pagamento potencial","Análise"].map(x=><th className="px-3 py-3 font-medium" key={x}>{x}</th>)}</tr>
              </thead>
              <tbody>{lista.map(p=>{
                const od=odometros[p.chave];
                const informado=!!od && od.inicio!=="" && od.fim!=="";
                const validado=informado && Number(od.fim)>=Number(od.inicio);
                const fisico=validado?Number(od.fim)-Number(od.inicio):null;
                const alerta= fisico!==null ? fisico>150 : p.planejado>150;
                const variacao=fisico!==null?fisico-p.planejado:null;
                return <tr key={p.chave} className="border-b border-border/70 align-top">
                  <td className="px-3 py-3"><strong>{p.nome}</strong><p className="text-xs text-muted-foreground">{p.rotas.join(" • ")}</p><p className="text-xs text-muted-foreground">{p.rotas.length} rota(s) no dia</p></td>
                  <td className="px-3 py-3 font-medium">{km(p.planejado)}{p.planejado>150&&<p className="text-xs text-amber-500">Acima do limite planejado</p>}</td>
                  <td className="px-3 py-3">{km(p.realizadoGM)}{p.kmSuspeitos.length>0&&<p className="text-xs text-amber-500">Não confiável: {p.kmSuspeitos.length} rota(s) com 0 ou &lt;1 km</p>}</td>
                  <td className="px-3 py-3">
                    <div className="flex gap-1">
                      <input className={campo+" w-24"} inputMode="decimal" placeholder="Inicial" aria-label={"Hodômetro inicial "+p.nome} value={od?.inicio??""} onChange={e=>marcar(p.chave,"inicio",e.target.value)}/>
                      <input className={campo+" w-24"} inputMode="decimal" placeholder="Final" aria-label={"Hodômetro final "+p.nome} value={od?.fim??""} onChange={e=>marcar(p.chave,"fim",e.target.value)}/>
                    </div>
                    {fisico!==null?<p className="mt-1 font-semibold">{km(fisico)} <span className="text-xs text-muted-foreground">({variacao!==null&&variacao>=0?"+":""}{km(variacao??0)} vs. JTI)</span></p>:
                     informado?<p className="text-xs text-destructive">Final menor que inicial</p>:<p className="text-xs text-muted-foreground">Não informado</p>}
                  </td>
                  <td className="px-3 py-3">{p.varejo} varejo • {p.grocery} grocery{p.groceryPorTempo>0&&<p className="text-xs text-muted-foreground">{p.groceryPorTempo} grocery por tempo de 1h ou mais</p>}{p.divergenciasCategoria>0&&<p className="text-xs text-amber-500">{p.divergenciasCategoria} Varejo no GM, mas 1h+ planejada - conferir</p>}{p.insucessos>0&&<p className="text-xs text-amber-500">{p.insucessos} paradas com insucesso</p>}{p.semCategoria>0&&<p className="text-xs text-muted-foreground">{p.semCategoria} sem categoria</p>}</td>
                  <td className="px-3 py-3 font-semibold">{dinheiro(p.potencial)}<p className="text-xs font-normal text-muted-foreground">Não conferido</p></td>
                  <td className="px-3 py-3"><span className={alerta?"font-semibold text-destructive":"text-muted-foreground"}>{fisico!==null?(alerta?"Acima de 150 km":"Dentro de 150 km"):(p.planejado>150?"Planejamento acima de 150 km":"KM físico pendente")}</span></td>
                </tr>;
              })}</tbody>
            </table>
          </div>
          <p className="text-xs text-muted-foreground">O KM físico digitado é temporário nesta versão: não permanece após recarregar. Exporte o CSV para guardar o fechamento. Não há integração automática com GPS nem apuração de lucro (receita JTI e custos totais não estão neste export).</p>
        </section>
      </div>}
    </div>
  </AppShell>;
}
