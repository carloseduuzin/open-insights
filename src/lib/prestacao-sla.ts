/** Prestação JTI: D0 é a data da rota no GreenMile; D+3 usa dias corridos. */
export type StatusPrestacao = "ABERTA" | "RETORNADA" | "CONFERIDA" | "ENVIADA_JTI" | "CONFIRMADA_JTI";
export type PrestacaoRegistro = {
  id: string; romaneio_oficial: string; d0: string; status: StatusPrestacao;
  responsavel_id: string | null; retornada_em: string | null; conferida_em: string | null;
  enviada_em: string | null; confirmada_em: string | null;
};
function dataUTC(iso: string): Date {
  const [ano, mes, dia] = iso.slice(0, 10).split("-").map(Number);
  if (!ano || !mes || !dia) throw new Error("Data da rota inválida");
  return new Date(Date.UTC(ano, mes - 1, dia));
}
export function vencimentoD3(d0: string): string {
  const data = dataUTC(d0);
  data.setUTCDate(data.getUTCDate() + 3);
  return data.toISOString().slice(0, 10);
}
export function diferencaDias(d0: string, hoje: string): number {
  return Math.floor((dataUTC(hoje).getTime() - dataUTC(d0).getTime()) / 86400000);
}
export function criticidadePrestacao(item: Pick<PrestacaoRegistro,"d0"|"status">, hoje: string) {
  const dias = diferencaDias(item.d0, hoje);
  if (item.status === "CONFIRMADA_JTI") return { nivel: "CONCLUIDA" as const, dias, rotulo: "Confirmada JTI" };
  if (dias >= 4) return { nivel: "CRITICO" as const, dias, rotulo: "Crítico — D+4 ou mais" };
  if (dias === 3) return { nivel: "URGENTE" as const, dias, rotulo: "Urgente — vence hoje" };
  if (dias === 2) return { nivel: "ALERTA" as const, dias, rotulo: "Alerta — D+2" };
  if (dias >= 0) return { nivel: "NO_PRAZO" as const, dias, rotulo: `No prazo — D+${dias}` };
  return { nivel: "FUTURA" as const, dias, rotulo: "Rota futura" };
}
