/** GreenMile CSV parser. Pure functions: no writes, no real customer data in tests. */
export type Linha = Record<string, string>;
export type ResultadoCSV = { colunas: string[]; linhas: Linha[] };
export type NFNormalizada = { numero: string; serie: string | null; chaveAcesso: string | null };

export function lerCSV(conteudo: string): ResultadoCSV {
  const entrada = conteudo.replace(/^\uFEFF/, "");
  const primeiraLinha = entrada.split(/\r?\n/, 1)[0] ?? "";
  const separador = (primeiraLinha.match(/;/g)?.length ?? 0) > (primeiraLinha.match(/,/g)?.length ?? 0) ? ";" : ",";
  const linhas: string[][] = [];
  let campo = "", registro: string[] = [], entreAspas = false;
  for (let i = 0; i < entrada.length; i++) {
    const c = entrada[i];
    if (c === '"') {
      if (entreAspas && entrada[i + 1] === '"') { campo += '"'; i++; }
      else entreAspas = !entreAspas;
    } else if (c === separador && !entreAspas) {
      registro.push(campo); campo = "";
    } else if ((c === "\n" || c === "\r") && !entreAspas) {
      if (c === "\r" && entrada[i + 1] === "\n") i++;
      registro.push(campo); campo = "";
      if (registro.some((v) => v !== "")) linhas.push(registro);
      registro = [];
    } else campo += c;
  }
  if (entreAspas) throw new Error("CSV inválido: aspas não fechadas");
  registro.push(campo);
  if (registro.some((v) => v !== "")) linhas.push(registro);
  const colunas = linhas.shift()?.map((v) => v.trim()) ?? [];
  if (!colunas.length || new Set(colunas).size !== colunas.length) throw new Error("Cabeçalho CSV vazio ou duplicado");
  const dados = linhas.map((valores, i) => {
    if (valores.length !== colunas.length) throw new Error(`CSV: linha ${i + 2} com ${valores.length} campos; esperado ${colunas.length}`);
    return Object.fromEntries(colunas.map((coluna, indice) => [coluna, valores[indice] ?? ""]));
  });
  return { colunas, linhas: dados };
}

export function normalizarNF(valor: string): NFNormalizada | null {
  const limpo = valor.trim();
  if (/^\d{44}$/.test(limpo)) return {
    numero: limpo.slice(25, 34), serie: String(Number(limpo.slice(22, 25))), chaveAcesso: limpo,
  };
  const gm = /^(\d{1,9})-(\d{1,3})$/.exec(limpo);
  if (gm) return { numero: (gm[1] ?? "").padStart(9, "0"), serie: String(Number(gm[2] ?? "0")), chaveAcesso: null };
  if (/^\d{1,9}$/.test(limpo)) return { numero: limpo.padStart(9, "0"), serie: null, chaveAcesso: null };
  return null;
}

export function classificarRomaneio(valor: string): "OFICIAL_CANDIDATO" | "AUXILIAR" | "INVALIDO" {
  // Descricoes curtas e marcadores auxiliares arredondados no export nao sao origem fiscal.
  if (/^\d{1,11}$/.test(valor) || /^([1-9])[.,]\1{1,10}e\+?11$/i.test(valor)) return "AUXILIAR";
  if (!/^\d{12}$/.test(valor)) return "INVALIDO";
  if (/^(\d)\1{11}$/.test(valor) || valor.startsWith("6000000000")) return "AUXILIAR";
  return "OFICIAL_CANDIDATO";
}

export type VinculoGM = {
  idParada: string;
  data: string;
  codigoRota: string;
  romaneio: string | null;
  motorista: string | null;
  numeroNF: string;
  serie: string | null;
  tipoRomaneio: ReturnType<typeof classificarRomaneio>;
};

export function conciliarStopViews(paradas: Linha[], pedidos: Linha[]) {
  const erros: string[] = [];
  const porId = new Map<string, Linha>();
  for (const p of paradas) {
    const id = p["id"];
    if (!id || porId.has(id)) { erros.push(`ID de parada ausente ou duplicado: ${id}`); continue; }
    porId.set(id, p);
  }
  const vistos = new Set<string>();
  const vinculos: VinculoGM[] = [];
  for (const pedido of pedidos) {
    const id = pedido["id"];
    if (!id) { erros.push("Pedido sem ID de parada"); continue; }
    const parada = porId.get(id);
    if (!parada) { erros.push(`Pedido sem parada: ${id}`); continue; }
    vistos.add(id);
    const codigoRota = parada["Código da rota"] ?? "";
    const data = (parada["Data da Rota"] ?? "").slice(0, 10);
    if (codigoRota !== pedido["routeView.route.key"] || data !== (pedido["routeView.route.date"] ?? "").slice(0, 10)) {
      erros.push(`Divergência rota/data na parada ${id}`); continue;
    }
    const bruto = (pedido["stop.orders.number"] ?? "").trim();
    const nf = /^\d{1,2}$/.test(bruto) ? null : normalizarNF(bruto);
    if (!nf) { erros.push(`NF ausente ou inválida na parada ${id}`); continue; }
    const romaneio = parada["Descrição da rota"] || null;
    vinculos.push({
      idParada: id, data, codigoRota, romaneio,
      motorista: parada["Motoristas"] || null, numeroNF: nf.numero, serie: nf.serie,
      tipoRomaneio: classificarRomaneio(romaneio ?? ""),
    });
  }
  for (const id of porId.keys()) if (!vistos.has(id)) erros.push(`Parada sem pedido: ${id}`);
  return { vinculos, erros, totalParadas: porId.size, totalPedidos: pedidos.length };
}

/**
 * Staging para prestação: somente romaneios oficiais candidatos, vinculados
 * a exatamente uma rota e uma data. Nunca cria prestação de romaneio auxiliar.
 * O operador deve revisar e confirmar antes de gravar.
 */
export function prepararPrestacoesGM(paradas: Linha[], pedidos: Linha[]) {
  const conciliacao = conciliarStopViews(paradas, pedidos);
  // A NF ausente exige conferência, mas não impede abrir a fila do romaneio.
  // Erros estruturais de vínculo entre rota e parada continuam bloqueantes.
  const bloqueios = conciliacao.erros.filter(erro => !erro.startsWith("NF ausente ou inválida na parada "));
  const pendenciasNF = conciliacao.erros.filter(erro => erro.startsWith("NF ausente ou inválida na parada ")).map(erro => {
    const id = erro.replace("NF ausente ou inválida na parada ", "");
    const parada = paradas.find(p => p["id"] === id);
    return { idParada: id, rota: (parada?.["Código da rota"] ?? "").trim(),
      romaneio: (parada?.["Descrição da rota"] ?? "").trim(), descricao: erro };
  });
  const avisos = [...bloqueios];
  const agrupadas = new Map<string, { data: string; codigo: string; romaneios: Set<string>; quantidade: number }>();
  for (const parada of paradas) {
    const data = (parada["Data da Rota"] ?? "").slice(0, 10);
    const codigo = (parada["Código da rota"] ?? "").trim();
    const romaneio = (parada["Descrição da rota"] ?? "").trim();
    const chave = `${data}|${codigo}`;
    const grupo = agrupadas.get(chave) ?? { data, codigo, romaneios: new Set<string>(), quantidade: 0 };
    grupo.romaneios.add(romaneio);
    grupo.quantidade++;
    agrupadas.set(chave, grupo);
  }
  const candidatos: { romaneio: string; d0: string; rota: string; paradas: number }[] = [];
  let auxiliares = 0;
  for (const grupo of agrupadas.values()) {
    if (grupo.romaneios.size !== 1) {
      avisos.push(`Rota ${grupo.codigo} apresenta descrições de romaneio distintas`);
      continue;
    }
    const romaneio = [...grupo.romaneios][0] ?? "";
    const tipo = classificarRomaneio(romaneio);
    if (tipo === "AUXILIAR") { auxiliares++; continue; }
    if (tipo === "INVALIDO") { avisos.push(`Rota ${grupo.codigo}: romaneio inválido`); continue; }
    if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(grupo.data)) {
      avisos.push(`Rota ${grupo.codigo}: D0 inválido`);
      continue;
    }
    candidatos.push({ romaneio, d0: grupo.data, rota: grupo.codigo, paradas: grupo.quantidade });
  }
  const repetidos = new Set<string>();
  const vistos = new Set<string>();
  for (const c of candidatos) {
    if (vistos.has(c.romaneio)) repetidos.add(c.romaneio);
    vistos.add(c.romaneio);
  }
  if (repetidos.size) avisos.push(`${repetidos.size} romaneio(s) associado(s) a múltiplas rotas`);
  return { candidatos, auxiliares, avisos, pendenciasNF, bloqueado: avisos.length > 0 };
}


/**
 * Unifica os dois StopViews pelo ID da parada. Somente parse/validação de
 * estrutura: a RPC é responsável por classificar e persistir NFs e pendências.
 */
export function prepararLinhasStopView(paradas: ResultadoCSV, pedidos: ResultadoCSV, organizacao = "RENOVELOG-ZL"): Linha[] {
  const obrigatoriasParadas = ["id", "Código da rota", "Descrição da rota", "Data da Rota", "Organização"];
  const obrigatoriasPedidos = ["id", "stop.orders.number", "routeView.route.key", "routeView.route.date"];
  for (const nome of obrigatoriasParadas) {
    if (!paradas.colunas.includes(nome)) throw new Error("StopView Paradas: coluna obrigatória ausente: " + nome);
  }
  for (const nome of obrigatoriasPedidos) {
    if (!pedidos.colunas.includes(nome)) throw new Error("StopView Pedidos: coluna obrigatória ausente: " + nome);
  }
  const alvo = paradas.linhas.filter(l => l["Organização"]?.trim() === organizacao);
  if (!alvo.length) throw new Error("StopView: nenhuma parada da organização " + organizacao + " encontrada");
  const porId = new Map<string, Linha>();
  for (const p of alvo) {
    const id = p["id"]?.trim() ?? "";
    if (!/^[0-9]{1,18}$/.test(id) || /^0+$/.test(id) || porId.has(id)) {
      throw new Error("StopView: ID da parada inválido ou duplicado: " + (id || "(vazio)"));
    }
    const codigo = p["Código da rota"]?.trim() ?? "";
    const romaneio = p["Descrição da rota"]?.trim() ?? "";
    const data = (p["Data da Rota"] ?? "").slice(0, 10);
    if (!codigo) throw new Error("StopView: Código da rota vazio na parada " + id);
    if (classificarRomaneio(romaneio) === "INVALIDO") throw new Error("StopView: descrição de rota inválida; confira o romaneio completo ou a identificação de reentrega, parada " + id);
    if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(data)) throw new Error("StopView: Data da Rota inválida na parada " + id);
    porId.set(id, p);
  }
  const encontrados = new Set<string>();
  const linhas: Linha[] = [];
  for (const pedido of pedidos.linhas) {
    const id = pedido["id"]?.trim() ?? "";
    const parada = porId.get(id);
    if (!parada) continue; // Pedidos de outras organizações.
    encontrados.add(id);
    const codigo = parada["Código da rota"]?.trim() ?? "";
    const data = (parada["Data da Rota"] ?? "").slice(0, 10);
    if (pedido["routeView.route.key"]?.trim() !== codigo ||
      (pedido["routeView.route.date"] ?? "").slice(0, 10) !== data) {
      throw new Error("StopView: rota/data divergente entre Paradas e Pedidos, parada " + id);
    }
    linhas.push({
      ...parada, id,
      "Código da rota": codigo,
      "Descrição da rota": (parada["Descrição da rota"] ?? "").trim(),
      "Data da Rota": data,
      "routeView.route.key": pedido["routeView.route.key"],
      "routeView.route.date": data,
      "stop.orders.number": pedido["stop.orders.number"] ?? "",
    });
  }
  for (const [id, parada] of porId) {
    if (encontrados.has(id)) continue;
    // Parada sem pedido não pode desaparecer: gerará uma pendência SEM_NF.
    linhas.push({
      ...parada, id,
      "Código da rota": (parada["Código da rota"] ?? "").trim(),
      "Descrição da rota": (parada["Descrição da rota"] ?? "").trim(),
      "Data da Rota": (parada["Data da Rota"] ?? "").slice(0, 10),
      "stop.orders.number": "",
    });
  }
  return linhas;
}
