export type ModoCanhoto = "RECEBER" | "REENTREGA" | "TRANSFERIR";

export function prepararMovimentacao(entrada: {
  modo: ModoCanhoto; codigo: string; motivo: string; destino: string; observacao: string;
}) {
  const codigo = entrada.codigo.trim();
  const observacao = entrada.observacao.trim() || null;
  if (!codigo) throw new Error("Leia o código da NF antes de registrar.");
  if (entrada.modo === "RECEBER") return {
    nome: "sigo_bipar_canhoto", argumentos: { p_codigo: codigo, p_dispositivo: "SIGO-web" },
  };
  if (!entrada.motivo) throw new Error("Selecione o motivo da movimentação.");
  if (entrada.modo === "REENTREGA") return {
    nome: "sigo_registrar_reentrega", argumentos: { p_codigo: codigo, p_motivo: entrada.motivo, p_observacao: observacao },
  };
  if (!entrada.destino.trim()) throw new Error("Informe o romaneio de destino.");
  if (entrada.motivo === "OUTRO" && !observacao) throw new Error("Descreva o motivo da transferência.");
  return {
    nome: "sigo_transferir_nf", argumentos: { p_codigo: codigo, p_romaneio_destino: entrada.destino.trim(), p_motivo: entrada.motivo, p_observacao: observacao },
  };
}
