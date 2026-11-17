import { useEffect, useState } from "react";
import { requireSupabase } from "@/lib/supabase";

type Registro = { id: string; tipo: string; arquivo_nome: string; registros: number; criado_em: string };
type Pendencia = { linha: number; codigo_rota: string; motivo: string; status: string };
function erroTexto(erro: unknown) {
  return erro && typeof erro === "object" && "message" in erro && typeof erro.message === "string" ? erro.message : "Não foi possível consultar o histórico. Tente atualizar.";
}
export function HistoricoImportacoes({ revisao }: { revisao: number }) {
  const [registros, setRegistros] = useState<Registro[]>([]);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState("");
  const [atualizacao, setAtualizacao] = useState(0);
  const [selecionada, setSelecionada] = useState("");
  const [pendencias, setPendencias] = useState<Pendencia[]>([]);
  const [consultando, setConsultando] = useState(false);
  const [erroPendencias, setErroPendencias] = useState("");
  useEffect(() => {
    let cancelado = false;
    setCarregando(true); setErro("");
    async function carregar() {
      try {
        const { data, error } = await requireSupabase().from("gm_importacoes").select("id,tipo,arquivo_nome,registros,criado_em").order("criado_em", { ascending: false }).limit(50);
        if (error) throw error;
        if (!cancelado) setRegistros((data ?? []) as Registro[]);
      } catch (error) { if (!cancelado) setErro(erroTexto(error)); }
      finally { if (!cancelado) setCarregando(false); }
    }
    void carregar();
    return () => { cancelado = true; };
  }, [revisao, atualizacao]);
  useEffect(() => {
    let cancelado = false;
    setPendencias([]); setErroPendencias("");
    if (!selecionada) { setConsultando(false); return; }
    setConsultando(true);
    async function carregar() {
      try {
        const { data, error } = await requireSupabase().from("pendencias_importacao").select("linha,codigo_rota,motivo,status").eq("importacao_id", selecionada).order("linha").limit(200);
        if (error) throw error;
        if (!cancelado) setPendencias((data ?? []) as Pendencia[]);
      } catch (error) { if (!cancelado) setErroPendencias(erroTexto(error)); }
      finally { if (!cancelado) setConsultando(false); }
    }
    void carregar();
    return () => { cancelado = true; };
  }, [selecionada, revisao, atualizacao]);
  return <section className="rounded-xl border border-border bg-card p-5 space-y-3">
    <div className="flex flex-wrap items-center justify-between gap-3"><h2 className="font-semibold">Histórico de importações confirmadas</h2><button type="button" disabled={carregando} onClick={() => setAtualizacao(v => v + 1)} className="rounded-md border border-border px-3 py-2 text-sm disabled:opacity-40">Atualizar histórico</button></div>
    <p className="text-sm text-muted-foreground">Últimas 50 importações salvas no banco. Este histórico permanece ao trocar de tela ou reabrir o SIGO.</p>
    {erro && <p role="alert" className="text-destructive">{erro}</p>}
    {carregando ? <p role="status">Consultando histórico...</p> : !erro && registros.length === 0 ? <p className="rounded-md bg-muted p-3 text-sm">Nenhuma importação confirmada no banco. Selecionar arquivos gera uma prévia; use “Confirmar e salvar importação” para gravar.</p> : registros.length > 0 && <div className="overflow-x-auto"><table className="w-full min-w-[620px] text-left text-sm"><thead><tr><th className="p-2">Data e hora</th><th className="p-2">Arquivos</th><th className="p-2">Linhas</th><th className="p-2">Situação</th><th className="p-2">Detalhes</th></tr></thead><tbody>{registros.map(r => <tr key={r.id} className="border-t border-border"><td className="p-2">{new Date(r.criado_em).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" })}</td><td className="p-2 break-all">{r.arquivo_nome}<span className="block text-xs text-muted-foreground">{r.tipo}</span></td><td className="p-2">{r.registros}</td><td className="p-2 text-emerald-500">Salva no banco</td><td className="p-2"><button type="button" onClick={() => setSelecionada(r.id === selecionada ? "" : r.id)} className="underline underline-offset-4">Ver pendências</button></td></tr>)}</tbody></table></div>}
    {selecionada && <div className="rounded-md border border-border p-3 space-y-2"><h3 className="font-medium">Pendências da importação selecionada</h3>{consultando ? <p role="status">Consultando pendências...</p> : erroPendencias ? <p role="alert" className="text-destructive">{erroPendencias}</p> : pendencias.length === 0 ? <p>Nenhuma pendência registrada nesta importação.</p> : <><ul className="max-h-64 overflow-auto text-sm space-y-1">{pendencias.map(p => <li key={p.linha}>Linha {p.linha} · Rota {p.codigo_rota} · {p.motivo} · {p.status}</li>)}</ul>{pendencias.length === 200 && <p className="text-xs text-muted-foreground">Exibindo até 200 pendências.</p>}</>}</div>}
  </section>;
}

