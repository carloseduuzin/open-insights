import test from "node:test";
import assert from "node:assert/strict";
import { criticidadePrestacao, vencimentoD3 } from "../src/lib/prestacao-sla.ts";

test("prazo D+3 conta dias corridos, inclusive virada do mês", () => {
  assert.equal(vencimentoD3("2026-10-30"), "2026-11-02");
  assert.equal(criticidadePrestacao({d0:"2026-10-30",status:"ABERTA"},"2026-11-02").nivel,"URGENTE");
});
test("conferida internamente ainda é pendência", () => {
  assert.equal(criticidadePrestacao({d0:"2026-10-27",status:"CONFERIDA"},"2026-11-02").nivel,"CRITICO");
});
test("enviada à JTI dá baixa e sai do SLA mesmo após D+3", () => {
  assert.equal(criticidadePrestacao({d0:"2026-10-27",status:"ENVIADA_JTI"},"2026-11-02").nivel,"CONCLUIDA");
  assert.equal(criticidadePrestacao({d0:"2026-10-27",status:"CONFIRMADA_JTI"},"2026-11-02").nivel,"CONCLUIDA");
});
