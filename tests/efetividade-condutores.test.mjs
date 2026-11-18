import test from 'node:test';
import assert from 'node:assert/strict';
import {avaliarPresenca,avaliarEntregas,rascunhoCondutor} from '../src/lib/efetividade-condutores.ts';
const f=situacao=>({data:'2026-11-18',situacao,minutos_atraso:situacao==='ATRASO'?10:0});
test('sem registro nao vira falta nem nota zero',()=>{assert.equal(avaliarPresenca([]).indice,null);assert.equal(avaliarPresenca([f('ESCALADO'),f('FOLGA'),f('FALTA_JUSTIFICADA')]).avaliados,0);});
test('placar usa apenas presenca confirmada, atraso e falta; amostra curta fica em formacao',()=>{const r=avaliarPresenca([f('PRESENTE'),f('ATRASO'),f('FALTA'),f('FOLGA')]);assert.equal(r.pontos,17);assert.equal(r.avaliados,3);assert.equal(r.classificavel,false);assert.ok(Math.abs(r.indice-100*17/30)<0.0001);});
test('cinco dias confirmados permitem classificar sem exigir dias de folga',()=>{assert.equal(avaliarPresenca(Array.from({length:5},()=>f('PRESENTE'))).faixa,'Meta atingida');});
test('entrega sem status nao recebe sucesso nem falha e parcial nao vira resultado completo',()=>{assert.equal(avaliarEntregas({paradas:10,entregues:0,nao_entregues:0,sem_resultado:10}).indice,null);const p=avaliarEntregas({paradas:10,entregues:4,nao_entregues:1,sem_resultado:5});assert.equal(p.indice,80);assert.equal(p.cobertura,50);assert.equal(p.completo,false);});
test('WhatsApp e apenas texto factual e nao culpa condutor por motivo do cliente',()=>{const c={nome:'Condutor teste',frequencias:[],rotas:1,paradas:10,entregues:0,nao_entregues:0,sem_resultado:10,reentregas_cliente:1,reentregas_operacao:0};const t=rascunhoCondutor(c,'2026-11-01','2026-11-18');assert.match(t,/resultado ainda não confirmado/);assert.match(t,/não descontam pontos de presença/);assert.doesNotMatch(t,/0\.0%|indo mal|enviado/);});
