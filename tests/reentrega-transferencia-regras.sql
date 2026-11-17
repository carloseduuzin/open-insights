\set ON_ERROR_STOP on
-- TESTES SINTETICOS DE REGRAS: nao representam export real nem homologacao de conciliacao GM.
BEGIN;
DO $regras$
DECLARE a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();sem_role uuid:=gen_random_uuid();
 r1 uuid;r2 uuid;dest uuid;outro_dia uuid;vuc uuid;p1 uuid;p2 uuid;n1 uuid;n2 uuid;n3 uuid;nv uuid;
 res jsonb;re1 uuid;re2 uuid;inicio timestamptz;negado boolean;cont integer;
BEGIN
 INSERT INTO auth.users(id,raw_user_meta_data) VALUES(a,'{}'),(b,'{}'),(sem_role,'{}');
 INSERT INTO public.profiles(id,nome,ativo) VALUES(a,'Operador A sintetico',true),(b,'Operador B sintetico',true),(sem_role,'Sem role sintetico',true);
 INSERT INTO public.user_roles(user_id,role) VALUES(a,'operacional'),(b,'operacional');
 PERFORM set_config('sigo.uid',a::text,true);
 INSERT INTO public.rotas(data_rota,codigo,romaneio_gm,tipo_romaneio,tipo_rota,motorista_gm) VALUES
 (current_date,'TEST-ORIGEM-A','987654321001','OFICIAL','ENTREGA','Motorista A sintetico') RETURNING id INTO r1;
 INSERT INTO public.rotas(data_rota,codigo,romaneio_gm,tipo_romaneio,tipo_rota,motorista_gm) VALUES
 (current_date,'TEST-ORIGEM-B','987654321002','OFICIAL','ENTREGA','Motorista B sintetico') RETURNING id INTO r2;
 INSERT INTO public.rotas(data_rota,codigo,romaneio_gm,tipo_romaneio,tipo_rota,motorista_gm) VALUES
 (current_date,'TEST-DESTINO','987654321003','OFICIAL','ENTREGA','Motorista destino sintetico') RETURNING id INTO dest;
 INSERT INTO public.rotas(data_rota,codigo,romaneio_gm,tipo_romaneio,tipo_rota) VALUES
 (current_date+1,'TEST-OUTRO-DIA','987654321004','OFICIAL','ENTREGA') RETURNING id INTO outro_dia;
 INSERT INTO public.rotas(data_rota,codigo,romaneio_gm,tipo_romaneio,tipo_rota) VALUES
 (current_date,'TEST-VUC','600000000002','AUXILIAR','ABASTECIMENTO') RETURNING id INTO vuc;
 INSERT INTO public.prestacoes(romaneio_oficial,d0) VALUES('987654321001',current_date) RETURNING id INTO p1;
 INSERT INTO public.prestacoes(romaneio_oficial,d0) VALUES('987654321002',current_date) RETURNING id INTO p2;
 INSERT INTO public.notas_fiscais(numero,serie,romaneio_origem,origem_rota_id) VALUES('987654321','7','987654321001',r1) RETURNING id INTO n1;
 INSERT INTO public.notas_fiscais(numero,serie,romaneio_origem,origem_rota_id) VALUES('987654322','7','987654321002',r2) RETURNING id INTO n2;
 INSERT INTO public.notas_fiscais(numero,serie,romaneio_origem,origem_rota_id) VALUES('987654323','7','987654321002',r2) RETURNING id INTO n3;
 INSERT INTO public.notas_fiscais(numero,serie,romaneio_origem,origem_rota_id) VALUES('987654324','7','987654321002',vuc) RETURNING id INTO nv;
 INSERT INTO public.nf_execucoes(nf_id,rota_id,tipo,registrada_por) VALUES(n1,r1,'CARGA',a),(n2,r2,'CARGA',a),(n3,r2,'CARGA',a);

 res:=public.sigo_registrar_reentrega('987654321-7','INVALIDO');
 IF res->>'resultado'<>'MOTIVO_INVALIDO' THEN RAISE EXCEPTION 'Motivo invalido aceito'; END IF;
 res:=public.sigo_registrar_reentrega('987654324-7','PDV_FECHADO');
 IF res->>'detalhe'<>'ABASTECIMENTO' THEN RAISE EXCEPTION 'Abastecimento entrou em reentrega'; END IF;
 res:=public.sigo_registrar_reentrega('987654321-7','PDV_FECHADO');
 IF res->>'resultado'<>'REENTREGA_REGISTRADA' OR res->>'status'<>'AGUARDANDO' OR (res->>'tentativa')::integer<>1 THEN RAISE EXCEPTION 'Primeira falha incorreta: %',res; END IF;
 re1:=(res->>'reentrega_id')::uuid;
 IF NOT EXISTS(SELECT 1 FROM public.prestacao_nota_justificativas WHERE nf_id=n1 AND prestacao_id=p1 AND motivo='REENTREGA_PROGRAMADA') THEN RAISE EXCEPTION 'Justificativa ausente'; END IF;
 res:=public.sigo_registrar_reentrega('987654321-7','PDV_FECHADO');
 IF res->>'resultado'<>'JA_EM_REENTREGA' THEN RAISE EXCEPTION 'Duplicata nao bloqueada'; END IF;
 -- Relogio controlado apenas no teste: dois dias COMPLETOS; nao muda limite de tentativas.
 UPDATE public.nf_reentregas SET pendencia_iniciada_em=statement_timestamp()-interval '47 hours' WHERE id=re1;
 IF EXISTS(SELECT 1 FROM public.v_fila_reentrega WHERE reentrega_id=re1 AND atrasada) THEN RAISE EXCEPTION 'Alerta antes de 48h'; END IF;
 UPDATE public.nf_reentregas SET pendencia_iniciada_em=statement_timestamp()-interval '49 hours' WHERE id=re1;
 SELECT pendencia_iniciada_em INTO inicio FROM public.nf_reentregas WHERE id=re1;
 IF NOT EXISTS(SELECT 1 FROM public.v_fila_reentrega WHERE reentrega_id=re1 AND atrasada) THEN RAISE EXCEPTION 'Alerta de 48h ausente'; END IF;
 -- Estado EM_ROTA preparado diretamente: teste da maquina de estados, NAO importacao ficticia.
 UPDATE public.nf_reentregas SET status='EM_ROTA',rota_reentrega_id=dest,carregada_em=clock_timestamp() WHERE id=re1;
 PERFORM sigo_interno.mover_execucao(n1,dest,'REENTREGA',a);
 res:=public.sigo_registrar_reentrega('987654321-7','RESPONSAVEL_AUSENTE');
 re2:=(res->>'reentrega_id')::uuid;
 IF (res->>'tentativa')::integer<>2 OR res->>'status'<>'AGUARDANDO' THEN RAISE EXCEPTION 'Segunda falha gerou devolucao automatica'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.nf_reentregas WHERE id=re1 AND status='FALHOU' AND encerrada_por=a) OR NOT EXISTS(SELECT 1 FROM public.nf_reentregas WHERE id=re2 AND pendencia_iniciada_em=inicio) THEN RAISE EXCEPTION 'Historico/prazo reiniciado'; END IF;
 PERFORM set_config('sigo.uid',b::text,true);
 res:=public.sigo_bipar_canhoto('987654321-7','teste-sintetico');
 IF res->>'resultado'<>'OK_REENTREGA' OR NOT EXISTS(SELECT 1 FROM public.nf_reentregas WHERE id=re2 AND status='ENTREGUE' AND encerrada_por=b) THEN RAISE EXCEPTION 'Recebimento da reentrega falhou: %',res; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.prestacao_notas WHERE nf_id=n1 AND prestacao_id=p1 AND canhoto_recebido_por=b) THEN RAISE EXCEPTION 'Credito fiscal ou autor incorreto'; END IF;
 res:=public.sigo_registrar_reentrega('987654321-7','PDV_FECHADO');
 IF res->>'resultado'<>'JA_ENTREGUE' THEN RAISE EXCEPTION 'Reentrega apos canhoto foi aceita'; END IF;

 PERFORM set_config('sigo.uid',a::text,true);
 res:=public.sigo_transferir_nf('987654322-7','987654321003','ROTA_MAIS_PROXIMA');
 IF res->>'resultado'<>'TRANSFERIDA' THEN RAISE EXCEPTION 'Transferencia valida falhou: %',res; END IF;
 res:=public.sigo_transferir_nf('987654322-7','987654321003','ROTA_MAIS_PROXIMA');
 IF res->>'resultado'<>'MESMA_ROTA' THEN RAISE EXCEPTION 'Mesma rota nao bloqueada'; END IF;
 res:=public.sigo_transferir_nf('987654322-7','987654321004','ROTA_MAIS_PROXIMA');
 IF res->>'resultado'<>'DATA_DIFERENTE' THEN RAISE EXCEPTION 'Outro dia nao bloqueado'; END IF;
 res:=public.sigo_transferir_nf('987654322-7','600000000002','ROTA_MAIS_PROXIMA');
 IF res->>'resultado'<>'DESTINO_ABASTECIMENTO' THEN RAISE EXCEPTION 'Destino VUC aceito'; END IF;
 res:=public.sigo_transferir_nf('987654322-7','987654321002','OUTRO','Retorno sintetico');
 IF res->>'resultado'<>'TRANSFERIDA' THEN RAISE EXCEPTION 'Retorno a rota anterior perdeu historico'; END IF;
 res:=public.sigo_transferir_nf('987654322-7','987654321003','REBALANCEAMENTO');
 IF res->>'resultado'<>'TRANSFERIDA' OR (SELECT count(*) FROM public.nf_transferencias WHERE nf_id=n2)<>3 THEN RAISE EXCEPTION 'Historico de transferencias incompleto'; END IF;
 PERFORM set_config('sigo.uid',b::text,true);
 res:=public.sigo_bipar_canhoto('987654322-7','teste-sintetico');
 IF res->>'resultado'<>'ROTA_DIFERENTE' OR res->'transferencia'->>'rota'<>'TEST-DESTINO' THEN RAISE EXCEPTION 'Recebimento da transferencia incorreto'; END IF;
 IF (SELECT origem_rota_id FROM public.notas_fiscais WHERE id=n2)<>r2 THEN RAISE EXCEPTION 'Origem fiscal alterada'; END IF;
 IF (SELECT count(*) FROM public.v_transferencias_dia WHERE nf_id=n2 AND produtividade_positiva)<>1 THEN RAISE EXCEPTION 'Produtividade duplicada'; END IF;

 res:=public.sigo_registrar_reentrega('987654323-7','AVARIA');re1:=(res->>'reentrega_id')::uuid;
 PERFORM public.sigo_solicitar_devolucao(re1,'Solicitacao sintetica explicita');
 res:=public.sigo_encerrar_devolucao(re1,'Devolvida em teste');
 IF res->>'resultado'<>'DEVOLVIDA' THEN RAISE EXCEPTION 'Devolucao explicita nao encerrou'; END IF;
 res:=public.sigo_encerrar_devolucao(re1,'Repeticao');
 IF res->>'resultado'<>'JA_DEVOLVIDA' THEN RAISE EXCEPTION 'Devolucao nao idempotente'; END IF;
 IF has_table_privilege('authenticated','public.nf_reentregas','INSERT') OR has_schema_privilege('authenticated','sigo_interno','USAGE') OR has_function_privilege('anon','public.sigo_registrar_reentrega(text,text,text)','EXECUTE') THEN RAISE EXCEPTION 'Privilegios excessivos'; END IF;
 PERFORM set_config('sigo.uid',sem_role::text,true);
 FOR cont IN 1..5 LOOP
  negado:=false;
  BEGIN
   CASE cont WHEN 1 THEN PERFORM public.sigo_registrar_reentrega('987654321-7','PDV_FECHADO');
    WHEN 2 THEN PERFORM public.sigo_transferir_nf('987654322-7','987654321003','ROTA_MAIS_PROXIMA');
    WHEN 3 THEN PERFORM public.sigo_solicitar_devolucao(re1,'teste');
    WHEN 4 THEN PERFORM public.sigo_encerrar_devolucao(re1,'teste');
    WHEN 5 THEN PERFORM public.sigo_configurar_reentrega(2,ARRAY[]::text[]); END CASE;
  EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'Usuário sem acesso ativo ao SIGO' THEN RAISE; END IF;negado:=true; END;
  IF NOT negado THEN RAISE EXCEPTION 'Usuario sem role aceito na operacao %',cont; END IF;
 END LOOP;
END; $regras$;
ROLLBACK;
