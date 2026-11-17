import { useEffect, useRef, useState, type FormEvent } from "react";
import { requireSupabase } from "@/lib/supabase";

type Prestacao = { id: string; romaneio_oficial: string; status: string };
type Faltante = { nf_id: string; numero: string; serie: string; cliente: string | null; justificativa: string | null };
type Progresso = { total_nfs: number; bipados: number; faltantes: number };
type Leitura = {
  resultado: string;
  detalhe?: string | null;
  nf?: { numero: string; serie: string } | null;
  prestacao?: Prestacao | null;
  rota_origem?: { codigo: string } | null;
  rota_execucao?: { codigo: string } | null;
  bipada_anteriormente_por?: { nome: string; em: string } | null;
};
const mensagens: Record<string, string> = {
  OK: "Canhoto recebido",
  ROTA_DIFERENTE: "Canhoto recebido na prestação de origem. A execução ocorreu em outra rota.",
  JA_BIPADA: "Este canhoto já foi recebido. Nenhum novo recebimento foi registrado.",
  NAO_ENCONTRADA: "NF não encontrada. Confira o código e a importação do StopView completo.",
  SEM_PRESTACAO: "NF sem prestação vinculada. Confira a importação antes de continuar.",
  PRESTACAO_FECHADA: "Prestação fechada. O recebimento não foi alterado.",
  CODIGO_INVALIDO: "Código inválido. Leia a chave de 44 dígitos ou informe número e série.",
};
function mensagemErro(error: unknown) {
  if (error && typeof error === "object" && "message" in error && typeof error.message === "string") return error.message;
  return "Não foi possível confirmar a operação. Confira o histórico antes de tentar novamente.";
}
const motivos = [
  ["DEVOLUCAO", "Devolução"], ["REENTREGA_PROGRAMADA", "Reentrega programada"],
  ["REQUISICAO", "Requisição"], ["RECOLHA", "Recolha"], ["EXTRAVIO", "Extravio"], ["OUTRO", "Outro"],
] as const;
export function BipagemCanhotos({ prestacoes, aoAtualizar }: { prestacoes: Prestacao[]; aoAtualizar: () => Promise<void> }) {
  const [aberto, setAberto] = useState(false);
  const [codigo, setCodigo] = useState("");
  const [leitura, setLeitura] = useState<Leitura | null>(null);
  const [erro, setErro] = useState("");
  const [ocupado, setOcupado] = useState(false);
  const [selecionada, setSelecionada] = useState("");
  const [faltantes, setFaltantes] = useState<Faltante[]>([]);
  const [progresso, setProgresso] = useState<Progresso | null>(null);
  const [consultando, setConsultando] = useState(false);
  const [nf, setNf] = useState("");
  const [motivo, setMotivo] = useState<string>("DEVOLUCAO");
  const [observacao, setObservacao] = useState("");
  const [aviso, setAviso] = useState("");
  const [revisao, setRevisao] = useState(0);
  const trava = useRef(false);
  const campo = useRef<HTMLInputElement>(null);
  const atual = prestacoes.find(p => p.id === selecionada);
  const editavel = atual?.status === "ABERTA" || atual?.status === "RETORNADA";
  useEffect(() => {
    if (!aberto || !selecionada) { setFaltantes([]); setProgresso(null); return; }
    let cancelado = false;
    setConsultando(true); setFaltantes([]); setProgresso(null); setNf("");
    async function consultar() {
      try {
        const client = requireSupabase();
        const [lista, resumo] = await Promise.all([
          client.rpc("sigo_canhotos_faltantes", { p_prestacao_id: selecionada }),
          client.from("v_prestacao_progresso").select("total_nfs,bipados,faltantes").eq("prestacao_id", selecionada).single(),
        ]);
        if (lista.error) throw lista.error;
        if (resumo.error) throw resumo.error;
        if (!cancelado) { setFaltantes((lista.data ?? []) as Faltante[]); setProgresso(resumo.data as Progresso); }
      } catch (error) { if (!cancelado) setErro(mensagemErro(error)); }
      finally { if (!cancelado) setConsultando(false); }
    }
    void consultar();
    return () => { cancelado = true; };
  }, [aberto, selecionada, revisao]);
  async function bipar(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (trava.current || !codigo.trim()) return;
    trava.current = true; setOcupado(true); setErro(""); setAviso(""); setLeitura(null);
    try {
      const { data, error } = await requireSupabase().rpc("sigo_bipar_canhoto", { p_codigo: codigo, p_dispositivo: "SIGO-web" });
      if (error) throw error;
      const resultado = data as Leitura | null;
      if (!resultado || !Object.hasOwn(mensagens, resultado.resultado)) throw new Error("Resposta de bipagem não reconhecida. Confira o histórico antes de repetir.");
      setLeitura(resultado); setCodigo("");
      if (resultado.prestacao?.id) setSelecionada(resultado.prestacao.id);
      setRevisao(v => v + 1);
      await aoAtualizar();
    } catch (error) { setErro(mensagemErro(error)); }
    finally { trava.current = false; setOcupado(false); campo.current?.focus(); }
  }
  async function justificar(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const item = faltantes.find(f => f.nf_id === nf && !f.justificativa);
    if (trava.current || !editavel || !item || (['EXTRAVIO', 'OUTRO'].includes(motivo) && !observacao.trim())) return;
    if (!window.confirm(`Registrar ${motivos.find(m => m[0] === motivo)?.[1]} para a NF ${item.numero}-${item.serie}, romaneio ${atual?.romaneio_oficial}? A justificativa será auditada.`)) return;
    trava.current = true; setOcupado(true); setErro(""); setAviso("");
    try {
      const { data, error } = await requireSupabase().rpc("sigo_justificar_faltante", { p_prestacao_id: selecionada, p_nf_id: item.nf_id, p_motivo: motivo, p_observacao: observacao.trim() || null });
      if (error) throw error;
      if (!data?.registrada) throw new Error("O banco não confirmou a justificativa.");
      setAviso("Justificativa registrada. A NF continua fisicamente faltante até o canhoto chegar.");
      setNf(""); setObservacao(""); setRevisao(v => v + 1);
    } catch (error) { setErro(mensagemErro(error)); }
    finally { trava.current = false; setOcupado(false); }
  }
  const inputClass = "w-full rounded-md border border-input bg-background px-3 py-2";
  const buttonClass = "rounded-md bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-40";
  return <section className="rounded-xl border border-border bg-card p-5 space-y-4">
    <button type="button" aria-expanded={aberto} onClick={() => setAberto(v => !v)} className="font-semibold">Bipagem de canhotos — {aberto ? "recolher" : "abrir"}</button>
    {aberto && <>
      <p className="text-sm text-muted-foreground">Importe os dois StopViews completos antes de bipar. O canhoto é registrado no romaneio de origem identificado pelo banco.</p>
      <form onSubmit={event => void bipar(event)} className="flex flex-wrap items-end gap-3">
        <label className="min-w-0 flex-1 space-y-1 text-sm">Código do canhoto<input ref={campo} value={codigo} onChange={e => setCodigo(e.target.value)} readOnly={ocupado} autoComplete="off" autoCapitalize="off" spellCheck={false} placeholder="Leia o código e pressione Enter" className={inputClass}/></label>
        <button type="submit" disabled={ocupado || !codigo.trim()} className={buttonClass}>{ocupado ? "Confirmando..." : "Registrar canhoto"}</button>
      </form>
      {erro && <p role="alert" className="rounded-md border border-destructive p-3 text-sm text-destructive">{erro}</p>}
      {aviso && <p role="status" className="rounded-md border border-border p-3 text-sm">{aviso}</p>}
      {leitura && <div role="status" aria-live="polite" className="rounded-md border border-border bg-muted p-4 space-y-1">
        <p className="font-semibold">{mensagens[leitura.resultado]}</p>
        {leitura.nf && <p>NF {leitura.nf.numero}-{leitura.nf.serie}</p>}
        {leitura.prestacao && <p>Romaneio de origem: <strong>{leitura.prestacao.romaneio_oficial}</strong></p>}
        {leitura.rota_execucao && <p>Rota de execução: {leitura.rota_execucao.codigo}</p>}
        {leitura.detalhe && <p className="text-sm">Detalhe: {leitura.detalhe}</p>}
        {leitura.bipada_anteriormente_por && <p className="text-sm">Recebido por {leitura.bipada_anteriormente_por.nome || "usuário registrado"} em {new Date(leitura.bipada_anteriormente_por.em).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" })}.</p>}
      </div>}
      <div className="flex flex-wrap items-end gap-3">
        <label className="min-w-0 flex-1 space-y-1 text-sm">Consultar romaneio<select value={selecionada} disabled={ocupado} onChange={e => { setSelecionada(e.target.value); setErro(""); setAviso(""); }} className={inputClass}>
          <option value="">Selecione uma prestação</option>{prestacoes.map(p => <option key={p.id} value={p.id}>{p.romaneio_oficial} — {p.status}</option>)}
        </select></label>
        <button type="button" disabled={!selecionada || ocupado || consultando} onClick={() => { setErro(""); setRevisao(v => v + 1); }} className={buttonClass}>Atualizar faltantes</button>
      </div>
      {consultando && <p role="status">Consultando canhotos...</p>}
      {progresso && <p>Total de NFs: <strong>{progresso.total_nfs}</strong> · Bipadas: <strong>{progresso.bipados}</strong> · Faltantes físicos: <strong>{progresso.faltantes}</strong></p>}
      {progresso?.total_nfs === 0 && <p role="alert" className="text-amber-500">Sem NFs vinculadas. Confira a importação antes de conferir esta prestação.</p>}
      {faltantes.length > 0 && <div className="overflow-x-auto"><table className="w-full text-left text-sm"><thead><tr><th className="p-2">NF / série</th><th className="p-2">Cliente</th><th className="p-2">Justificativa</th></tr></thead><tbody>{faltantes.map(f => <tr key={f.nf_id} className="border-t border-border"><td className="p-2">{f.numero}-{f.serie}</td><td className="p-2">{f.cliente || "—"}</td><td className="p-2">{motivos.find(m => m[0] === f.justificativa)?.[1] || f.justificativa || "Sem justificativa"}</td></tr>)}</tbody></table></div>}
      {editavel && faltantes.some(f => !f.justificativa) && !consultando && <form onSubmit={event => void justificar(event)} className="grid gap-3 sm:grid-cols-2">
        <label className="space-y-1 text-sm">NF faltante<select required value={nf} onChange={e => setNf(e.target.value)} disabled={ocupado} className={inputClass}><option value="">Selecione a NF</option>{faltantes.filter(f => !f.justificativa).map(f => <option key={f.nf_id} value={f.nf_id}>{f.numero}-{f.serie}</option>)}</select></label>
        <label className="space-y-1 text-sm">Motivo<select value={motivo} onChange={e => setMotivo(e.target.value)} disabled={ocupado} className={inputClass}>{motivos.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
        <label className="space-y-1 text-sm sm:col-span-2">Observação<textarea value={observacao} onChange={e => setObservacao(e.target.value)} required={['EXTRAVIO', 'OUTRO'].includes(motivo)} disabled={ocupado} className={inputClass}/></label>
        <button type="submit" disabled={ocupado || !nf} className={buttonClass}>Registrar justificativa</button>
      </form>}
    </>}
  </section>;
}

