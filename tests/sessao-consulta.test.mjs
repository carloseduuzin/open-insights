import test from "node:test";
import assert from "node:assert/strict";
import { QueryClient } from "@tanstack/react-query";
import { chaveSessao, opcoesSessao, sincronizarSessaoCache } from "../src/lib/sessao-consulta.ts";

test("trocar de tela reaproveita validacao recente e compartilha consulta simultanea", async () => {
  const client = new QueryClient(); let chamadas = 0;
  const opcoes = opcoesSessao(async () => { chamadas++; return { nome: "A", email: "a@example.test" }; });
  try {
    const [a,b] = await Promise.all([client.fetchQuery(opcoes), client.fetchQuery(opcoes)]);
    assert.deepEqual(a,b);
    await client.fetchQuery(opcoes);
    assert.equal(chamadas,1);
    await sincronizarSessaoCache(client,"TOKEN_REFRESHED","a@example.test");
    await client.fetchQuery(opcoes);
    assert.equal(chamadas,2);
  } finally { client.clear(); }
});

test("logout remove permissao e dados do usuario e bloqueia resposta antiga atrasada", async () => {
  const client = new QueryClient(); let resolver;
  try {
    client.setQueryData(chaveSessao,{nome:"A",email:"a@example.test"});
    client.setQueryData(["sigo-admin","a@example.test"],true);
    const consulta = client.fetchQuery({queryKey:["dados-operacionais"],queryFn:()=>new Promise(r=>{resolver=r;})}).catch(()=>null);
    await sincronizarSessaoCache(client,"SIGNED_OUT");
    resolver(["resposta antiga"]); await consulta;
    assert.equal(client.getQueryData(chaveSessao),null);
    assert.equal(client.getQueryData(["sigo-admin","a@example.test"]),undefined);
    assert.equal(client.getQueryData(["dados-operacionais"]),undefined);
  } finally { client.clear(); }
});

test("troca de identidade invalida sessao e nao herda acesso de administrador anterior", async () => {
  const client = new QueryClient();
  try {
    client.setQueryData(chaveSessao,{nome:"A",email:"a@example.test"});
    client.setQueryData(["sigo-admin","a@example.test"],true);
    await sincronizarSessaoCache(client,"SIGNED_IN","b@example.test");
    assert.equal(client.getQueryData(chaveSessao),undefined);
    assert.equal(client.getQueryData(["sigo-admin","a@example.test"]),undefined);
    const nova = await client.fetchQuery(opcoesSessao(async()=>({nome:"B",email:"b@example.test"})));
    assert.equal(nova.email,"b@example.test");
  } finally { client.clear(); }
});
