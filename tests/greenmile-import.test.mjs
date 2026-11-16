import test from "node:test";
import assert from "node:assert/strict";
import { lerCSV, normalizarNF, classificarRomaneio, conciliarStopViews, prepararLinhasStopView } from "../src/lib/greenmile-import.ts";

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

test("16/11: NF 005605465-7 e 5605465 têm o mesmo número (uma com série, outra sem)", () => {
  const a = normalizarNF("005605465-7");
  const b = normalizarNF("5605465");
  assert.equal(a?.numero, "005605465");
  assert.equal(a?.numero, b?.numero);
  assert.equal(a?.serie, "7");
  assert.equal(b?.serie, null);
});

test("StopView persistente exige as quatro colunas críticas antes de gravar", () => {
  const paradas = lerCSV("id;Organização;Data da Rota;Código da rota;Descrição da rota\n1;RENOVELOG-ZL;2026-11-16;SP-1;123456789012");
  const pedidos = lerCSV("id;routeView.route.key;routeView.route.date\n1;SP-1;2026-11-16");
  assert.throws(() => prepararLinhasStopView(paradas,pedidos), /stop\.orders\.number/);
  for (const coluna of ["Código da rota","Descrição da rota","id"]) {
    const invalido = { ...paradas, colunas: paradas.colunas.filter(c => c!==coluna) };
    assert.throws(() => prepararLinhasStopView(invalido,
      lerCSV("id;stop.orders.number;routeView.route.key;routeView.route.date\n1;005605465-7;SP-1;2026-11-16")), new RegExp(coluna));
  }
});

test("StopView preserva seis números sem série, três vazios e duas VT de valor 5", () => {
  const paradas = ["id;Organização;Data da Rota;Código da rota;Descrição da rota"];
  const pedidos = ["id;stop.orders.number;routeView.route.key;routeView.route.date"];
  const valores = ["005605465-7", "5605465", "5605466", "5605467", "5605468", "5605469", "5605470", "5605471", "", "", "", "5", "5"];
  for(let i=0;i<valores.length;i++) {
    const vt = i>=11, codigo=vt?"VT-1":"SP-1",rom=vt?"333333333333":"123456789012";
    paradas.push(String(i+1)+";RENOVELOG-ZL;2026-11-16;"+codigo+";"+rom);
    pedidos.push(String(i+1)+";"+valores[i]+";"+codigo+";2026-11-16");
  }
  const linhas=prepararLinhasStopView(lerCSV(paradas.join("\n")),lerCSV(pedidos.join("\n")));
  assert.equal(linhas.length,13);
  assert.equal(linhas.filter(l=>/^\d{7}$/.test(l["stop.orders.number"])).length,7);
  assert.equal(linhas.filter(l=>l["stop.orders.number"]==="").length,3);
  assert.equal(linhas.filter(l=>l["Código da rota"]==="VT-1"&&l["stop.orders.number"]==="5").length,2);
  assert.equal(linhas.find(l=>l["stop.orders.number"]==="005605465-7")?.["Descrição da rota"],"123456789012");
});

test("Parada sem pedido é preservada para virar pendência SEM_NF", () => {
  const paradas=lerCSV("id;Organização;Data da Rota;Código da rota;Descrição da rota\n100;RENOVELOG-ZL;2026-11-16;SP-1;123456789012");
  const pedidos=lerCSV("id;stop.orders.number;routeView.route.key;routeView.route.date\n999;1;SP-3;2026-11-16");
  const linhas=prepararLinhasStopView(paradas,pedidos);
  assert.equal(linhas.length,1);
  assert.equal(linhas[0]["stop.orders.number"],"");
});

test("Prévia nunca considera NF de 1 a 2 dígitos como documento fiscal", () => {
  const paradas=[{id:"1","Código da rota":"VT-1","Data da Rota":"2026-11-16","Descrição da rota":"333333333333"}];
  const pedidos=[{id:"1","stop.orders.number":"5","routeView.route.key":"VT-1","routeView.route.date":"2026-11-16"}];
  const r=conciliarStopViews(paradas,pedidos);
  assert.equal(r.vinculos.length,0);
  assert.match(r.erros[0],/NF ausente/);
});
