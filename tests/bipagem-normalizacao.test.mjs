import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { normalizarNF } from "../src/lib/greenmile-import.ts";

const casos = JSON.parse(fs.readFileSync(new URL("./bipagem-normalizacao-cases.json", import.meta.url), "utf8"));
function assinaturaTS(codigo) {
  const nf = normalizarNF(codigo);
  return nf === null ? "<NULL>" : nf.chaveAcesso ?? nf.numero + "-" + (nf.serie ?? "?");
}

test("normalizarNF TS: exemplos de 44 dígitos, zeros, hífen e rejeição estrita", () => {
  assert.equal(assinaturaTS("1234567-7"), "001234567-7");
  assert.equal(assinaturaTS("0001234567"), "<NULL>");
  assert.equal(assinaturaTS("abc"), "<NULL>");
  assert.equal(assinaturaTS(casos[0]), "<NULL>"); // espaço interno na chave
  assert.equal(assinaturaTS(casos[4]), casos[4]);
  assert.equal(assinaturaTS(" 1234567-007 "), "001234567-7");
});

test("SQL e TypeScript produzem resultados idênticos para os mesmos códigos da fixture", () => {
  const arquivo = process.env.SIGO_SQL_NORMALIZATION_OUTPUT;
  if (!arquivo) {
    // Execução local de teste JS permanece válida; o CI define o arquivo SQL.
    return;
  }
  const linhas = fs.readFileSync(arquivo, "utf8").trimEnd().split(/\r?\n/);
  assert.equal(linhas.length, casos.length, "CI SQL deve devolver uma linha por caso");
  for (let i = 0; i < casos.length; i++) {
    assert.equal(linhas[i], assinaturaTS(casos[i]), "divergência SQL x TS para " + JSON.stringify(casos[i]));
  }
});
