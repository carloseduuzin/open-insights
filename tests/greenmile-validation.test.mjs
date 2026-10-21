import test from "node:test";
import assert from "node:assert/strict";
import { validarCargaZL } from "../src/lib/greenmile-validation.ts";

const paradas = [
"id,Organização,Data da Rota,Código da rota,Descrição da rota",
"1,RENOVELOG-ZL,2026-10-20,SP-1MFV34,123456789012",
"2,RENOVELOG-ZL,2026-10-20,SP-2MFV34,333333333333",
"3,OUTRA-OPERACAO,2026-10-20,SP-1MFV77,999999999999",
].join("\n");
const pedidos = [
"id,stop.orders.number,routeView.route.key,routeView.route.date",
"1,005491895-7,SP-1MFV34,2026-10-20",
"2,005491895-7,SP-2MFV34,2026-10-20",
"3,005491896-7,SP-1MFV77,2026-10-20",
].join("\n");

test("Valida apenas ZL, identifica auxiliar e duplicidade entre rotas", () => {
  const resultado = validarCargaZL(paradas,pedidos);
  assert.equal(resultado.totalParadasZL,2);
  assert.equal(resultado.totalPedidosZL,2);
  assert.equal(resultado.rotas,2);
  assert.equal(resultado.romaneiosAuxiliares,1);
  assert.equal(resultado.duplicidadesPossiveis,1);
});
test("Não aceita exportação de outra operação como carga ZL", () => {
  assert.throws(()=>validarCargaZL(paradas.replaceAll("RENOVELOG-ZL","OUTRA-OPERACAO"),pedidos),/Nenhuma parada/);
});
