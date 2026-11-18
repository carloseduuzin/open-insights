import { useQuery } from "@tanstack/react-query";
import { createFileRoute } from "@tanstack/react-router";
import { AppShell } from "@/layout/AppShell";
import { requireSupabase } from "@/lib/supabase";

export const Route = createFileRoute("/relatorios")({head:()=>({meta:[{title:"Relatórios — SIGO | RenoveLog"}]}),component:Relatorios});
type Exportacao = {id:string;chave:string;criada_em:string;status:string;email_destino:string|null;concluida_em:string|null;arquivadas:number;arquivo_caminho:string|null};
function Relatorios() {
  const consulta = useQuery({queryKey:["sigo-exportacoes"],queryFn:async()=>{
    const {data,error}=await requireSupabase().from("exportacoes_prestacoes").select("id,chave,criada_em,status,email_destino,concluida_em,arquivadas,arquivo_caminho").order("criada_em",{ascending:false}).limit(100);
    if(error)throw error;return (data??[]) as Exportacao[];
  },staleTime:15_000,retry:false});
  return <AppShell titulo="Relatórios" descricao="Histórico de exportações e arquivamento operacional"><section className="rounded-xl border border-border bg-card p-5 space-y-4">
    <div className="flex flex-wrap justify-between gap-3"><h2 className="font-semibold">Exportação mensal da base</h2><button type="button" disabled={consulta.isFetching} onClick={()=>void consulta.refetch()} className="rounded-md border border-border px-3 py-2 text-sm disabled:opacity-40">Atualizar histórico</button></div>
    <p className="text-sm text-muted-foreground">A cada 30 dias, a base é salva em planilha e enviada para monitoramento@renovelog.com.br. Somente prestações baixadas há pelo menos 30 dias e confirmadas na exportação saem da listagem operacional; os indicadores do dashboard permanecem.</p>
    <p className="text-sm text-muted-foreground">A execução é feita pela automação do Codex conectada a este computador. O histórico detalhado é restrito ao administrador.</p>
    {consulta.isPending&&<p role="status">Carregando exportações...</p>}
    {consulta.isError&&<p role="alert" className="text-destructive">Não foi possível consultar o histórico. Atualize a consulta.</p>}
    {!consulta.isPending&&!consulta.isError&&consulta.data?.length===0&&<p>Nenhuma exportação disponível para este usuário.</p>}
    {!!consulta.data?.length&&<div className="overflow-x-auto"><table className="w-full text-left text-sm"><thead><tr>{["Data","Situação","Arquivo / pasta","Destino","Arquivadas"].map(c=><th key={c} className="p-2">{c}</th>)}</tr></thead><tbody>{consulta.data.map(e=><tr key={e.id} className="border-t border-border"><td className="p-2">{new Date(e.criada_em).toLocaleString("pt-BR",{timeZone:"America/Sao_Paulo"})}</td><td className="p-2">{e.status==="CONCLUIDA"?"Enviada e concluída":"Preparada — aguardando arquivo e envio"}</td><td className="p-2 break-all">{e.arquivo_caminho||"Aguardando gravação"}</td><td className="p-2">{e.email_destino||"Aguardando envio"}</td><td className="p-2">{e.arquivadas}</td></tr>)}</tbody></table></div>}
  </section></AppShell>;
}
