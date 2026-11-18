\set ON_ERROR_STOP on
-- Estados sinteticos de regras em banco isolado; nao representam importacao GreenMile real.
BEGIN;
DO $teste$
DECLARE u uuid:=gen_random_uuid();op uuid:=gen_random_uuid();r jsonb;r2 jsonb;rota uuid;nf uuid;negado boolean;
BEGIN
 INSERT INTO auth.users(id,raw_user_meta_data) VALUES(u,'{}'),(op,'{}');
 INSERT INTO public.profiles(id,nome,ativo) VALUES(u,'Admin efetividade sintetico',true),(op,'Operador efetividade sintetico',true);
 INSERT INTO public.user_roles(user_id,role) VALUES(u,'admin'),(op,'operacional');
 PERFORM set_config('sigo.uid',u::text,true);
 r:=public.sigo_registrar_frequencia('Condutor regra sintetica',current_date,'PRESENTE');
 r2:=public.sigo_registrar_frequencia('Condutor regra sintetica',current_date,'PRESENTE');
 IF NOT (r->>'alterada')::boolean OR (r2->>'alterada')::boolean OR (SELECT count(*) FROM public.condutor_frequencia_auditoria)<>1 THEN RAISE EXCEPTION 'Lancamento repetido nao idempotente'; END IF;
 negado:=false;
 BEGIN PERFORM public.sigo_registrar_frequencia('Condutor regra sintetica',current_date,'FALTA');EXCEPTION WHEN OTHERS THEN negado:=true;END;
 IF NOT negado THEN RAISE EXCEPTION 'Correcao sem motivo foi aceita'; END IF;
 PERFORM public.sigo_registrar_frequencia('Condutor regra sintetica',current_date,'ATRASO',15,'Correcao apos conferir chegada');
 IF (SELECT count(*) FROM public.condutor_frequencia_auditoria)<>2 THEN RAISE EXCEPTION 'Correcao sem historico'; END IF;
 negado:=false;
 BEGIN PERFORM public.sigo_registrar_frequencia('Condutor regra sintetica',current_date+1,'FALTA');EXCEPTION WHEN OTHERS THEN negado:=true;END;
 IF NOT negado THEN RAISE EXCEPTION 'Falta futura foi aceita'; END IF;
 negado:=false;
 BEGIN PERFORM public.sigo_registrar_frequencia('Outro condutor',current_date,'FALTA_JUSTIFICADA');EXCEPTION WHEN OTHERS THEN negado:=true;END;
 IF NOT negado THEN RAISE EXCEPTION 'Justificativa vazia foi aceita'; END IF;
 INSERT INTO public.rotas(data_rota,codigo,motorista_gm,romaneio_gm,tipo_romaneio,tipo_rota) VALUES(current_date,'SINT-EFETIVIDADE','Condutor regra sintetica','987654329101','OFICIAL','ENTREGA') RETURNING id INTO rota;
 INSERT INTO public.notas_fiscais(numero,serie) VALUES('987654399','7') RETURNING id INTO nf;
 INSERT INTO public.paradas(id,rota_id,data_rota,codigo_rota,status_gm) VALUES(987654329101,rota,current_date,'SINT-EFETIVIDADE',NULL),(987654329102,rota,current_date,'SINT-EFETIVIDADE','ENTREGUE_TESTE');
 INSERT INTO public.parada_notas(parada_id,nf_id) VALUES(987654329101,nf),(987654329102,nf);
 r:=public.sigo_consultar_efetividade(current_date-6,current_date);
 IF (r->'condutores'->0->>'entregues')::integer<>0 OR (r->'condutores'->0->>'sem_resultado')::integer<>2 THEN RAISE EXCEPTION 'Estado sem mapeamento inventou resultado: %',r; END IF;
 PERFORM public.sigo_configurar_resultados_condutores(ARRAY['ENTREGUE_TESTE'],ARRAY['NAO_ENTREGUE_TESTE']);
 r:=public.sigo_consultar_efetividade(current_date-6,current_date);
 IF (r->'condutores'->0->>'entregues')::integer<>1 OR (r->'condutores'->0->>'sem_resultado')::integer<>1 THEN RAISE EXCEPTION 'Resultado explicito nao conferiu'; END IF;
 negado:=false;
 BEGIN PERFORM public.sigo_configurar_resultados_condutores(ARRAY['IGUAL'],ARRAY['IGUAL']);EXCEPTION WHEN OTHERS THEN negado:=true;END;
 IF NOT negado THEN RAISE EXCEPTION 'Mapeamento contraditorio foi aceito'; END IF;
 PERFORM set_config('sigo.uid',op::text,true);
 negado:=false;BEGIN PERFORM public.sigo_consultar_efetividade(current_date-6,current_date);EXCEPTION WHEN OTHERS THEN negado:=true;END;
 IF NOT negado THEN RAISE EXCEPTION 'Operador consultou desempenho gerencial'; END IF;
 negado:=false;BEGIN PERFORM public.sigo_registrar_frequencia('Outro condutor',current_date,'PRESENTE');EXCEPTION WHEN OTHERS THEN negado:=true;END;
 IF NOT negado THEN RAISE EXCEPTION 'Operador alterou presenca sem acesso'; END IF;
 IF has_table_privilege('authenticated','public.condutor_frequencias','INSERT') OR has_table_privilege('authenticated','public.condutor_frequencia_auditoria','UPDATE') OR has_function_privilege('anon','public.sigo_consultar_efetividade(date,date)','EXECUTE') THEN RAISE EXCEPTION 'Permissao excessiva no controle de condutores'; END IF;
END; $teste$;
ROLLBACK;
