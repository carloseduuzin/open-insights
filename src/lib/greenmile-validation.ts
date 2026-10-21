/** Audit-first GreenMile import staging.
 * Preview only: all raw records remain client-side until server-side import is approved.
 */
import { lerCSV, conciliarStopViews, classificarRomaneio, type Linha } from "./greenmile-import";

export type ResumoImportacao = {
  totalParadasZL: number;
  totalPedidosZL: number;
  totalVinculos: number;
  totalOcorrencias: number;
  rotas: number;
  romaneiosAuxiliares: number;
  duplicidadesPossiveis: number;
  ocorrencias: string[];
};

function chaveRota(linha: Linha): string {
  return [linha["Data da Rota"]?.slice(0, 10), linha["Código da rota"]].join("|");
}

export function validarCargaZL(paradasCsv: string, pedidosCsv: string): ResumoImportacao {
  const paradas = lerCSV(paradasCsv);
  const pedidos = lerCSV(pedidosCsv);
  for (const coluna of ["id", "Organização", "Data da Rota", "Código da rota", "Descrição da rota"]) {
    if (!paradas.colunas.includes(coluna)) throw new Error(`Paradas: coluna obrigatória ausente: ${coluna}`);
  }
  for (const coluna of ["id", "stop.orders.number", "routeView.route.key", "routeView.route.date"]) {
    if (!pedidos.colunas.includes(coluna)) throw new Error(`Pedidos: coluna obrigatória ausente: ${coluna}`);
  }
  const linhasZL = paradas.linhas.filter(linha => linha["Organização"]?.trim() === "RENOVELOG-ZL");
  if (linhasZL.length === 0) throw new Error("Nenhuma parada RENOVELOG-ZL encontrada. Verifique o filtro e o período.");
  const ids = new Set(linhasZL.map(linha => linha["id"]));
  const pedidosZL = pedidos.linhas.filter(linha => ids.has(linha["id"]));
  const conciliacao = conciliarStopViews(linhasZL, pedidosZL);
  const romaneioPorRota = new Map<string, string>();
  const ocorrencias = [...conciliacao.erros];
  for (const linha of linhasZL) {
    const chave = chaveRota(linha);
    const romaneio = linha["Descrição da rota"] ?? "";
    const anterior = romaneioPorRota.get(chave);
    if (anterior && anterior !== romaneio) ocorrencias.push(`Rota/data com dois romaneios: ${chave}`);
    romaneioPorRota.set(chave, romaneio);
  }
  const nfPorRota = new Map<string, Set<string>>();
  let duplicidadesPossiveis = 0;
  for (const vinculo of conciliacao.vinculos) {
    const nf = `${vinculo.numeroNF}-${vinculo.serie ?? "SEM_SERIE"}`;
    const chave = `${vinculo.data}|${nf}`;
    const rotas = nfPorRota.get(chave) ?? new Set<string>();
    if (rotas.size > 0 && !rotas.has(vinculo.codigoRota)) duplicidadesPossiveis++;
    rotas.add(vinculo.codigoRota);
    nfPorRota.set(chave, rotas);
  }
  if (duplicidadesPossiveis) ocorrencias.push(`${duplicidadesPossiveis} ocorrências de NF em rotas distintas no mesmo dia; revisar antes de remuneração`);
  return {
    totalParadasZL: linhasZL.length,
    totalPedidosZL: pedidosZL.length,
    totalVinculos: conciliacao.vinculos.length,
    totalOcorrencias: ocorrencias.length,
    rotas: romaneioPorRota.size,
    romaneiosAuxiliares: [...romaneioPorRota.values()].filter(v=>classificarRomaneio(v)==="AUXILIAR").length,
    duplicidadesPossiveis,
    ocorrencias,
  };
}
