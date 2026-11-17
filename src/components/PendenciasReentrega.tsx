import { useEffect, useState } from "react";
import { requireSupabase } from "@/lib/supabase";

type Pendencia = {
  nf_id: string; numero: string; serie: string; romaneio_origem: string | null;
  cliente: string | null; situacao: string; motivo_reentrega: string;
  motorista_atual: string | null; rota_atual: string | null;
  pendencia_iniciada_em: string; vence_em: string; atrasada: boolean; tentativa: number;
};
const situacoes: Record<string, string> = {
  AGUARDANDO_REENTREGA: "Aguardando reentrega", EM_REENTREGA: "Em reentrega",
  ENTREGUE_AGUARDANDO_CANHOTO: "Entregue — aguardando canhoto", DEVOLUCAO_PENDENTE: "Devolução pendente",
};
const data = (valor: string) => new Date(valor).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" });

export function PendenciasReentrega({ revisao }: { revisao: number }) {
  const [itens, setItens] = useState<Pendencia[]>([]);
  const [total, setTotal] = useState(0);
  const [erro, setErro] = useState("");
  const [carregando, setCarregando] = useState(true);
  const [atualizacao, setAtualizacao] = useState(0);
  useEffect(() => {
    let cancelado = false;
    async function carregar() {
      setCarregando(true); setErro("");
      try {
        const { data: linhas, error, count } = await requireSupabase().from("v_fila_reentrega")
          .select("nf_id,numero,serie,romaneio_origem,cliente,situacao,motivo_reentrega,motorista_atual,rota_atual,pendencia_iniciada_em,vence_em,atrasada,tentativa", { count: "exact" })
          .order("vence_em", { ascending: true }).order("nf_id").limit(100);
        if (error) throw error;
        if (!cancelado) { setItens((linhas ?? []) as Pendencia[]); setTotal(count ?? 0); }
      } catch {
        if (!cancelado) { setItens([]); setErro("Não foi possível consultar as reentregas. Atualize a consulta; a ausência de dados não confirma que não há pendências."); }
      } finally { if (!cancelado) setCarregando(false); }
    }
    void carregar();
    return () => { cancelado = true; };
  }, [revisao, atualizacao]);
  useEffect(() => {
    const atualizar = () => { if (document.visibilityState === "visible") setAtualizacao(v => v + 1); };
    const intervalo = window.setInterval(atualizar, 60_000);
    document.addEventListener("visibilitychange", atualizar);
    return () => { window.clearInterval(intervalo); document.removeEventListener("visibilitychange", atualizar); };
  }, []);
  return <section className="rounded-xl border border-border bg-card p-5 space-y-3">
    <div className="flex flex-wrap items-center justify-between gap-3"><h2 className="font-semibold">NFs em reentrega e prestações pendentes</h2>
      <button type="button" disabled={carregando} onClick={() => setAtualizacao(v => v + 1)} className="rounded-md border border-border px-3 py-2 text-sm disabled:opacity-40">Atualizar pendências</button></div>
    <p className="text-sm text-muted-foreground">O prazo começa no registro do retorno para reentrega. Novas tentativas não reiniciam a contagem. O recebimento físico do canhoto é registrado pela bipagem.</p>
    {carregando && <p role="status">Atualizando prazos...</p>}
    {erro && <p role="alert" className="text-destructive">{erro}</p>}
    {!carregando && !erro && total === 0 && <p>Nenhuma reentrega pendente nesta consulta.</p>}
    {!carregando && !erro && total > 0 && <>
      <p>{total} NF(s) pendente(s). {total > itens.length && `Exibindo as ${itens.length} com vencimento mais próximo.`}</p>
      <div className="overflow-x-auto"><table className="w-full text-left text-sm"><thead><tr>
        <th className="p-2">NF / romaneio de origem</th><th className="p-2">Situação / motivo</th><th className="p-2">Rota / motorista atual</th><th className="p-2">Retorno / prazo</th>
      </tr></thead><tbody>{itens.map(item => <tr key={item.nf_id} className={`border-t border-border ${item.atrasada ? "bg-destructive/10" : ""}`}>
        <td className="p-2"><strong>{item.numero}-{item.serie}</strong><div>{item.romaneio_origem || "Sem origem vinculada"}</div><div>{item.cliente || "—"}</div></td>
        <td className="p-2">{item.atrasada && <strong className="block text-destructive">Prestação atrasada</strong>}{situacoes[item.situacao] || item.situacao}<div>{item.motivo_reentrega.replaceAll("_", " ")}</div><div>Tentativa {item.tentativa}</div></td>
        <td className="p-2">{item.rota_atual || "—"}<div>{item.motorista_atual || "Motorista não informado"}</div></td>
        <td className="p-2">Retorno: {data(item.pendencia_iniciada_em)}<div>Prazo: {data(item.vence_em)}</div></td>
      </tr>)}</tbody></table></div>
    </>}
  </section>;
}
