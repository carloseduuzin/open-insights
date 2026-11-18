import test from "node:test";
import assert from "node:assert/strict";
import { prepararPrestacoesGM } from "../src/lib/greenmile-import.ts";

function parada(id, rota, romaneio, data = "2026-11-01") {
  return { id, "Código da rota": rota, "Data da Rota": data,
    "Descrição da rota": romaneio };
}
function pedido(id, rota, numero = "1234567-7", data = "2026-11-01") {
  return { id, "routeView.route.key": rota, "routeView.route.date": data,
    "stop.orders.number": numero };
}
test("gera uma prestação por romaneio oficial, não por cliente ou por NF", () => {
  const resultado = prepararPrestacoesGM(
    [parada("1","R1","601615021154"), parada("2","R1","601615021154")],
    [pedido("1","R1","1234567-7"),pedido("2","R1","1234568-7")],
  );
  assert.equal(resultado.bloqueado,false);
  assert.equal(resultado.candidatos.length,1);
  assert.equal(resultado.candidatos[0].romaneio,"601615021154");
});
test("não gera prestação para romaneio auxiliar", () => {
  const r=prepararPrestacoesGM([parada("1","R1","600000000002")],[pedido("1","R1")]);
  assert.equal(r.candidatos.length,0);
  assert.equal(r.auxiliares,1);
});
test("bloqueia ambiguidade de romaneios na mesma rota", () => {
  const r=prepararPrestacoesGM([parada("1","R1","601615021154"),parada("2","R1","601615021155")],[pedido("1","R1"),pedido("2","R1")]);
  assert.equal(r.bloqueado,true);
  assert.equal(r.candidatos.length,0);
});
test("NF ausente vira pendência explícita, sem impedir abertura da fila", () => {
  const r=prepararPrestacoesGM([parada("1","R1","601615021154")],[pedido("1","R1","")]);
  assert.equal(r.bloqueado,false);
  assert.equal(r.candidatos.length,1);
  assert.equal(r.pendenciasNF.length,1);
  assert.equal(r.pendenciasNF[0].idParada,"1");
  assert.equal(r.pendenciasNF[0].rota,"R1");
});

test("bloqueia divergência de rota/data apesar da NF válida", () => {
  const r=prepararPrestacoesGM([parada("1","R1","601615021154")],[pedido("1","R2")]);
  assert.equal(r.bloqueado,true);
  assert.equal(r.avisos.some(x=>x.includes("Divergência rota/data")),true);
});
