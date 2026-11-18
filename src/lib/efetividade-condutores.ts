export type Frequencia = {id?:string;data:string;situacao:string;minutos_atraso:number;observacao?:string|null};
export type Regras = {pontos_presente:number;pontos_atraso:number;pontos_falta:number;minimo_dias_classificar:number;meta_presenca:number;meta_entregas:number};
export const regrasIniciais:Regras={pontos_presente:10,pontos_atraso:7,pontos_falta:0,minimo_dias_classificar:5,meta_presenca:95,meta_entregas:95};
export type Condutor = {nome:string;frequencias:Frequencia[];rotas:number;paradas:number;entregues:number;nao_entregues:number;sem_resultado:number;reentregas_cliente:number;reentregas_operacao:number};
export function avaliarPresenca(frequencias:Frequencia[],regras:Regras=regrasIniciais) {
 const presentes=frequencias.filter(f=>f.situacao==='PRESENTE').length;
 const atrasos=frequencias.filter(f=>f.situacao==='ATRASO').length;
 const faltas=frequencias.filter(f=>f.situacao==='FALTA').length;
 const avaliados=presentes+atrasos+faltas;
 const pontos=presentes*regras.pontos_presente+atrasos*regras.pontos_atraso+faltas*regras.pontos_falta;
 const indice=avaliados&&regras.pontos_presente>0?100*pontos/(avaliados*regras.pontos_presente):null;
 const classificavel=avaliados>=regras.minimo_dias_classificar;
 return {presentes,atrasos,faltas,avaliados,pontos,indice,classificavel,
  frequencia:avaliados?100*(presentes+atrasos)/avaliados:null,
  pendentes:frequencias.filter(f=>f.situacao==='ESCALADO').length,
  justificadas:frequencias.filter(f=>f.situacao==='FALTA_JUSTIFICADA').length,
  faixa:!classificavel?'Em formação':indice!==null&&indice>=regras.meta_presenca?'Meta atingida':indice!==null&&indice>=80?'Em evolução':'Acompanhar'};
}
export function avaliarEntregas(c:Pick<Condutor,'paradas'|'entregues'|'nao_entregues'|'sem_resultado'>) {
 const confirmadas=c.entregues+c.nao_entregues;
 return {confirmadas,indice:confirmadas?100*c.entregues/confirmadas:null,
  cobertura:c.paradas?100*confirmadas/c.paradas:null,
  completo:c.paradas>0&&c.sem_resultado===0&&confirmadas===c.paradas};
}
export function rascunhoCondutor(c:Condutor,inicio:string,fim:string,regras:Regras=regrasIniciais) {
 const p=avaliarPresenca(c.frequencias,regras),e=avaliarEntregas(c);
 const data=(iso:string)=>iso.split('-').reverse().join('/');
 const linhas=[`Olá, ${c.nome}. Segue seu acompanhamento de ${data(inicio)} a ${data(fim)}:`,
  p.avaliados?`Presença: ${p.presentes+p.atrasos} de ${p.avaliados} dias avaliados. Atrasos: ${p.atrasos}. Faltas sem justificativa: ${p.faltas}.`:'Presença: ainda não há lançamentos suficientes para avaliar.',
  p.avaliados?`Pontos de presença: ${p.pontos}. Índice: ${p.indice?.toFixed(1)}%.${p.classificavel?'':' Amostra inicial; ainda sem classificação.'}`:'',
  e.indice===null?'Entregas: resultado ainda não confirmado no GreenMile.':`Entregas: ${c.entregues} realizadas e ${c.nao_entregues} não realizadas entre ${e.confirmadas} paradas com resultado. Efetividade ${e.completo?'do período':'parcial'}: ${e.indice.toFixed(1)}%.`,
  e.indice!==null&&!e.completo?`${c.sem_resultado} parada(s) ainda sem resultado confirmado.`:'',
  c.reentregas_cliente||c.reentregas_operacao?`Reentregas registradas: ${c.reentregas_cliente} atribuídas ao cliente e ${c.reentregas_operacao} à operação. Esses motivos não descontam pontos de presença.`:'',
  'Podemos conferir os motivos e alinhar o próximo objetivo juntos?','Equipe RenoveLog'];
 return linhas.filter(Boolean).join('\n\n');
}
