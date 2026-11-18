import { useEffect, useRef, useState, type FormEvent } from "react";
import { requireSupabase } from "@/lib/supabase";
import { PendenciasReentrega } from "./PendenciasReentrega";
import { prepararMovimentacao } from "@/lib/movimentacao-canhotos";

type Prestacao = { id: string; romaneio_oficial: string; status: string };
type Faltante = { nf_id: string; numero: string; serie: string; cliente: string | null; justificativa: string | null; situacao?: string; motivo_reentrega?: string; vence_em?: string | null; atrasada?: boolean; tentativa?: number | null };
type Progresso = { total_nfs: number; bipados: number; faltantes: number };
type Leitura = {
  resultado: string;
  detalhe?: string | null;
  nf?: { numero: string; serie: string } | null;
  prestacao?: Prestacao | null;
  prestacao_origem?: { id: string; romaneio_oficial: string } | null;
  origem?: { romaneio: string } | null;
  destino?: { romaneio: string; rota: string; motorista: string | null } | null;
  tentativa?: number;
  rota_origem?: { codigo: string } | null;
  rota_execucao?: { codigo: string } | null;
  bipada_anteriormente_por?: { nome: string; em: string } | null;
};
const mensagens: Record<string, string> = {
  OK: "Canhoto recebido",
  OK_REENTREGA: "Canhoto recebido. A reentrega foi encerrada na prestação de origem.",
  REENTREGA_REGISTRADA: "Retorno para reentrega registrado. O prazo do retorno inicial foi preservado.",
  TRANSFERIDA: "Transferência registrada. O romaneio fiscal de origem foi preservado.",
  JA_EM_REENTREGA: "A NF já aguarda reentrega. Nenhuma tentativa duplicada foi criada.",
  JA_EM_DEVOLUCAO: "A NF está em devolução pendente. Confira seu histórico.",
  JA_ENTREGUE: "O canhoto desta NF já foi recebido. Nenhuma movimentação foi criada.",
  MOTIVO_INVALIDO: "Selecione um motivo válido e preencha a observação quando exigida.",
  ROTA_INVALIDA: "A NF não tem rota de entrega válida para esta movimentação.",
  SAIDA_NAO_CONFIRMADA: "A nova saída ainda não foi confirmada pelo GreenMile. Confira a importação.",
  NF_AGUARDANDO_REENTREGA: "A NF aguarda reentrega ou devolução; confira seu histórico antes de transferir.",
  DESTINO_INEXISTENTE: "Romaneio de destino não encontrado. Confira a importação.",
  DESTINO_AMBIGUO: "Há mais de uma rota para esse romaneio. Confira o destino antes de continuar.",
  DESTINO_ABASTECIMENTO: "A rota de abastecimento não pode receber transferência de NF.",
  MESMA_ROTA: "A NF já está nesta rota. Nenhuma transferência foi criada.",
  DATA_DIFERENTE: "A transferência exige rotas do mesmo dia. Para nova saída, use o fluxo de reentrega.",
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
type Modo = "RECEBER" | "REENTREGA" | "TRANSFERIR";
type MotivoReentrega = { codigo: string; descricao: string };
const motivosTransferencia = [
  ["ROTA_MAIS_PROXIMA", "Rota mais próxima"], ["REBALANCEAMENTO", "Rebalanceamento"],
  ["VEICULO_INDISPONIVEL", "Veículo indisponível"], ["MOTORISTA_AUSENTE", "Motorista ausente"], ["OUTRO", "Outro"],
] as const;
const situacoes: Record<string, string> = { AGUARDANDO_REENTREGA: "Aguardando reentrega", EM_REENTREGA: "Em reentrega", ENTREGUE_AGUARDANDO_CANHOTO: "Entregue — aguardando canhoto", DEVOLUCAO_PENDENTE: "Devolução pendente", TRANSFERIDA: "Transferida", JUSTIFICADA: "Justificada", AGUARDANDO_CANHOTO: "Aguardando canhoto" };
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
  const [modo, setModo] = useState<Modo>("RECEBER");
  const [motivosRetorno, setMotivosRetorno] = useState<MotivoReentrega[]>([]);
  const [erroMotivos, setErroMotivos] = useState("");
  const [motivo, setMotivo] = useState("");
  const [destino, setDestino] = useState("");
  const [observacao, setObservacao] = useState("");
  const [aviso, setAviso] = useState("");
  const [revisao, setRevisao] = useState(0);
  const trava = useRef(false);
  const campo = useRef<HTMLInputElement>(null);
  const exigeObservacao = modo === "TRANSFERIR" && motivo === "OUTRO";
  const pronto = modo === "RECEBER" || (modo === "REENTREGA" ? motivosRetorno.some(m => m.codigo === motivo) : Boolean(destino.trim() && motivo && (!exigeObservacao || observacao.trim())));
  useEffect(() => {
    if (!aberto || modo !== "REENTREGA") return;
    let cancelado = false;
    setMotivosRetorno([]); setErroMotivos("");
    void (async () => {
      try {
        const { data, error } = await requireSupabase().from("motivos_reentrega").select("codigo,descricao").eq("ativo", true).order("descricao");
        if (error) throw error;
        if (!cancelado) { setMotivosRetorno((data ?? []) as MotivoReentrega[]); if (!data?.length) setErroMotivos("Nenhum motivo de reentrega ativo. Solicite a configuração ao administrador."); }
      } catch { if (!cancelado) setErroMotivos("Não foi possível carregar os motivos. A reentrega não será registrada até a consulta ser confirmada."); }
    })();
    return () => { cancelado = true; };
  }, [aberto, modo]);
  useEffect(() => {
    if (!aberto || !selecionada) { setFaltantes([]); setProgresso(null); return; }
    let cancelado = false;
    setConsultando(true); setFaltantes([]); setProgresso(null);
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
    if (trava.current || !codigo.trim() || !pronto) return;
    trava.current = true; setOcupado(true); setErro(""); setAviso(""); setLeitura(null);
    try {
      const client = requireSupabase();
      const pedido = prepararMovimentacao({ modo, codigo, motivo, destino, observacao });
      const { data, error } = await client.rpc(pedido.nome, pedido.argumentos);
      if (error) throw error;
      const resultado = data as Leitura | null;
      if (!resultado || !Object.hasOwn(mensagens, resultado.resultado)) throw new Error("Resposta de bipagem não reconhecida. Confira o histórico antes de repetir.");
      setLeitura(resultado);
      if (["OK", "OK_REENTREGA", "ROTA_DIFERENTE", "JA_BIPADA", "REENTREGA_REGISTRADA", "TRANSFERIDA", "JA_EM_REENTREGA", "JA_ENTREGUE"].includes(resultado.resultado)) setCodigo("");
      const prestacaoId = resultado.prestacao?.id || resultado.prestacao_origem?.id || prestacoes.find(p => p.romaneio_oficial === resultado.origem?.romaneio)?.id;
      if (prestacaoId) setSelecionada(prestacaoId);
      setRevisao(v => v + 1);
      try { await aoAtualizar(); } catch { setAviso("O resultado acima foi confirmado pelo banco. A atualização da lista falhou; atualize a consulta sem repetir a movimentação."); }
    } catch (error) { setErro(mensagemErro(error)); }
    finally { trava.current = false; setOcupado(false); campo.current?.focus(); }
  }
  const inputClass = "w-full rounded-md border border-input bg-background px-3 py-2";
  const buttonClass = "rounded-md bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-40";
  return <><section className="rounded-xl border border-border bg-card p-5 space-y-4">
    <button type="button" aria-expanded={aberto} onClick={() => { if (!aberto) { setModo("RECEBER"); setMotivo(""); setCodigo(""); setLeitura(null); setErro(""); setAviso(""); } setAberto(v => !v); }} className="font-semibold">Bipagem de canhotos — {aberto ? "recolher" : "abrir"}</button>
    {aberto && <>
      <p className="text-sm text-muted-foreground">Importe os dois StopViews completos antes de bipar. O canhoto é registrado no romaneio de origem identificado pelo banco.</p>
      <div className="flex flex-wrap gap-2" role="group" aria-label="Movimentação da NF">
        {([["RECEBER", "Receber canhoto", "bg-emerald-700"], ["REENTREGA", "Retorno para reentrega", "bg-orange-700"], ["TRANSFERIR", "Transferir NF", "bg-blue-700"]] as const).map(([valor, label, cor]) => <button key={valor} type="button" disabled={ocupado} aria-pressed={modo === valor} onClick={() => { setModo(valor); setMotivo(""); setLeitura(null); setErro(""); setCodigo(""); setObservacao(""); campo.current?.focus(); }} className={`rounded-md border px-3 py-2 text-sm ${modo === valor ? `${cor} text-white border-transparent` : "border-border"}`}>{label}</button>)}
      </div>
      <p className="text-sm">{modo === "RECEBER" ? "Registra o recebimento físico do canhoto na prestação de origem." : modo === "REENTREGA" ? "Registra o retorno sem entrega. O alerta vence após dois dias do retorno inicial; novas tentativas preservam esse prazo." : "Registra a movimentação entre rotas do mesmo dia, preservando o romaneio fiscal de origem."}</p>
      <form onSubmit={event => void bipar(event)} className="flex flex-wrap items-end gap-3">
        {modo !== "RECEBER" && <div className="w-full grid gap-3 sm:grid-cols-2">
          {modo === "TRANSFERIR" && <label className="space-y-1 text-sm">Romaneio de destino<input required value={destino} onChange={e => setDestino(e.target.value)} readOnly={ocupado} className={inputClass}/></label>}
          <label className="space-y-1 text-sm">Motivo<select required value={motivo} onChange={e => setMotivo(e.target.value)} disabled={ocupado} className={inputClass}><option value="">Selecione o motivo</option>{modo === "REENTREGA" ? motivosRetorno.map(m => <option key={m.codigo} value={m.codigo}>{m.descricao}</option>) : motivosTransferencia.map(([valor, label]) => <option key={valor} value={valor}>{label}</option>)}</select></label>
          <label className="space-y-1 text-sm sm:col-span-2">Observação{exigeObservacao ? " (obrigatória)" : " (opcional)"}<input value={observacao} onChange={e => setObservacao(e.target.value)} required={exigeObservacao} readOnly={ocupado} className={inputClass}/></label>
          {modo === "REENTREGA" && erroMotivos && <p role="alert" className="text-destructive sm:col-span-2">{erroMotivos}</p>}
        </div>}
        <label className="min-w-0 flex-1 space-y-1 text-sm">Código da NF / canhoto<input ref={campo} value={codigo} onChange={e => setCodigo(e.target.value)} readOnly={ocupado} autoComplete="off" autoCapitalize="off" spellCheck={false} placeholder="Leia o código e pressione Enter" className={inputClass}/></label>
        <button type="submit" disabled={ocupado || !codigo.trim() || !pronto} className={buttonClass}>{ocupado ? "Confirmando..." : modo === "RECEBER" ? "Receber canhoto" : modo === "REENTREGA" ? "Registrar retorno" : "Registrar transferência"}</button>
      </form>
      {erro && <p role="alert" className="rounded-md border border-destructive p-3 text-sm text-destructive">{erro}</p>}
      {aviso && <p role="status" className="rounded-md border border-border p-3 text-sm">{aviso}</p>}
      {leitura && <div role="status" aria-live="polite" className="rounded-md border border-border bg-muted p-4 space-y-1">
        <p className="font-semibold">{mensagens[leitura.resultado]}</p>
        {leitura.nf && <p>NF {leitura.nf.numero}-{leitura.nf.serie}</p>}
        {leitura.prestacao && <p>Romaneio de origem: <strong>{leitura.prestacao.romaneio_oficial}</strong></p>}
        {leitura.prestacao_origem && <p>Romaneio de origem: <strong>{leitura.prestacao_origem.romaneio_oficial}</strong></p>}
        {leitura.origem && <p>Romaneio de origem: <strong>{leitura.origem.romaneio}</strong></p>}
        {leitura.destino && <p>Destino: <strong>{leitura.destino.romaneio}</strong> — {leitura.destino.rota} · {leitura.destino.motorista || "Motorista não informado"}</p>}
        {leitura.tentativa && <p>Tentativa {leitura.tentativa}</p>}
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
      {faltantes.length > 0 && <div className="overflow-x-auto"><table className="w-full text-left text-sm"><thead><tr><th className="p-2">NF / série</th><th className="p-2">Cliente</th><th className="p-2">Situação / motivo</th><th className="p-2">Prazo</th></tr></thead><tbody>{faltantes.map(f => <tr key={f.nf_id} className={`border-t border-border ${f.atrasada ? "bg-destructive/10" : ""}`}><td className="p-2">{f.numero}-{f.serie}</td><td className="p-2">{f.cliente || "—"}</td><td className="p-2">{f.atrasada && <strong className="block text-destructive">Prestação atrasada</strong>}{situacoes[f.situacao || ""] || "Aguardando canhoto"}<div>{f.justificativa?.replaceAll("_", " ") || "Sem movimentação registrada"}</div></td><td className="p-2">{f.vence_em ? new Date(f.vence_em).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" }) : "—"}</td></tr>)}</tbody></table></div>}
    </>}
  </section><PendenciasReentrega revisao={revisao}/></>;
}
