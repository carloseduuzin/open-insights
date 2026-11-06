import test from "node:test";
import assert from "node:assert/strict";
import { lerCSV, normalizarNF, classificarRomaneio, conciliarStopViews } from "../src/lib/greenmile-import.ts";

test("CSV: BOM, delimitador, aspas e quebra de linha", () => {
  const csv = lerCSV('\uFEFFid;Descrição da rota;Motoristas\r\n1;"333333333333";"Ana; Silva"\r\n2;"123456789012";"Bia\nSouza"');
  assert.equal(csv.linhas.length, 2);
  assert.equal(csv.linhas[0]["Motoristas"], "Ana; Silva");
  assert.equal(csv.linhas[1]["Motoristas"], "Bia\nSouza");
});
test("NF: mantém zeros e série GM", () => {
  assert.deepEqual(normalizarNF("005491895-7"), { numero: "005491895", serie: "7", chaveAcesso: null });
  assert.equal(normalizarNF("5491895")?.numero, "005491895");
  assert.equal(normalizarNF("NF errada"), null);
});
test("Chave de acesso: série posições 23-25 e NF 26-34", () => {
  const chave = "1".repeat(22) + "007" + "005491895" + "1".repeat(10);
  assert.equal(chave.length, 44);
  assert.deepEqual(normalizarNF(chave), { numero: "005491895", serie: "7", chaveAcesso: chave });
});
test("Romaneio auxiliar não vira prestação oficial", () => {
  assert.equal(classificarRomaneio("333333333333"), "AUXILIAR");
  assert.equal(classificarRomaneio("444444444444"), "AUXILIAR");
  assert.equal(classificarRomaneio("600000000002"), "AUXILIAR");
  assert.equal(classificarRomaneio("123456789012"), "OFICIAL_CANDIDATO");
  assert.equal(classificarRomaneio("123"), "INVALIDO");
});
test("Conciliação pelo ID da parada, não por localidade", () => {
  const paradas = [
    { id: "10", "Código da rota": "SP-1MFV34", "Data da Rota": "2026-10-01", "Descrição da rota": "123456789012", Motoristas: "A" },
    { id: "11", "Código da rota": "SP-2MFV34", "Data da Rota": "2026-10-01", "Descrição da rota": "333333333333", Motoristas: "B" },
  ];
  const pedidos = [
    { id: "11", "routeView.route.key": "SP-2MFV34", "routeView.route.date": "2026-10-01", "stop.orders.number": "005491895-7" },
    { id: "10", "routeView.route.key": "SP-1MFV34", "routeView.route.date": "2026-10-01", "stop.orders.number": "005491896-7" },
  ];
  const result = conciliarStopViews(paradas, pedidos);
  assert.equal(result.erros.length, 0);
  assert.equal(result.vinculos[0].motorista, "B");
  assert.equal(result.vinculos[0].tipoRomaneio, "AUXILIAR");
});
test("Não inventa NF quando pedido não possui número", () => {
  const r = conciliarStopViews([{ id: "1", "Código da rota": "A", "Data da Rota": "2026-10-01" }], [{ id: "1", "routeView.route.key": "A", "routeView.route.date": "2026-10-01", "stop.orders.number": "" }]);
  assert.equal(r.vinculos.length, 0);
  assert.match(r.erros[0], /NF ausente/);
});
