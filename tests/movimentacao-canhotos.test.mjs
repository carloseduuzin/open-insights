import test from "node:test";
import assert from "node:assert/strict";
import { prepararMovimentacao } from "../src/lib/movimentacao-canhotos.ts";

const base = { codigo: " 005608109-7 ", motivo: "PDV_FECHADO", destino: "601632021060", observacao: "" };
test("recebimento ignora motivo e destino de uma configuracao anterior", () => {
  const req = prepararMovimentacao({ ...base, modo: "RECEBER" });
  assert.equal(req.nome, "sigo_bipar_canhoto");
  assert.deepEqual(req.argumentos, { p_codigo: "005608109-7", p_dispositivo: "SIGO-web" });
});
test("retorno identifica NF pelo codigo sem escolher NF faltante ou marcar canhoto recebido", () => {
  const req = prepararMovimentacao({ ...base, modo: "REENTREGA" });
  assert.equal(req.nome, "sigo_registrar_reentrega");
  assert.deepEqual(req.argumentos, { p_codigo: "005608109-7", p_motivo: "PDV_FECHADO", p_observacao: null });
});
test("transferencia registra destino sem enviar substituicao da origem fiscal", () => {
  const req = prepararMovimentacao({ ...base, modo: "TRANSFERIR", motivo: "OUTRO", observacao: " Troca operacional " });
  assert.equal(req.nome, "sigo_transferir_nf");
  assert.deepEqual(req.argumentos, { p_codigo: "005608109-7", p_romaneio_destino: "601632021060", p_motivo: "OUTRO", p_observacao: "Troca operacional" });
});
test("dados incompletos impedem preparar uma movimentacao", () => {
  assert.throws(() => prepararMovimentacao({ ...base, modo: "RECEBER", codigo: " " }));
  assert.throws(() => prepararMovimentacao({ ...base, modo: "REENTREGA", motivo: "" }));
  assert.throws(() => prepararMovimentacao({ ...base, modo: "TRANSFERIR", destino: " " }));
  assert.throws(() => prepararMovimentacao({ ...base, modo: "TRANSFERIR", motivo: "OUTRO" }));
});
