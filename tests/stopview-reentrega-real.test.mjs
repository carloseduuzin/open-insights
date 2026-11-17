import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { lerCSV, prepararLinhasStopView, prepararPrestacoesGM, classificarRomaneio } from "../src/lib/greenmile-import.ts";

test("export real 17/11: descricao operacional e preservada, sem criar candidato fiscal", () => {
  const csv = lerCSV(readFileSync(new URL("./fixtures/stopview_reentrega_2026-11-17.csv", import.meta.url), "utf8"));
  const linhas = prepararLinhasStopView(csv, csv);
  assert.equal(linhas.length, 1);
  assert.equal(linhas[0].id, "11619529");
  assert.equal(linhas[0]["Descrição da rota"], "3,33333E+11");
  assert.equal(linhas[0]["stop.orders.number"], "000000001-7");
  assert.equal(classificarRomaneio(linhas[0]["Descrição da rota"]), "AUXILIAR");
  const previa = prepararPrestacoesGM(csv.linhas, csv.linhas);
  assert.equal(previa.candidatos.length, 0);
  assert.equal(previa.auxiliares, 1);
  assert.equal(previa.bloqueado, false);
});

