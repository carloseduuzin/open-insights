# SIGO — Checklist de ativação

## Estado verificado em 21/10/2026
- Banco Supabase de desenvolvimento: `sxgziltpoputrzhgpjof`
- Migrations aplicadas: `sigo_initial` e `sigo_function_execute_hardening`
- 3 tabelas com RLS e 7 políticas
- Primeiro administrador provisionado no banco (sem senhas no repositório)
- Código de login, logout, cadastro de prestadores e recuperação de senha implementado na branch
- Compilação, autenticação de ponta a ponta e deploy **não validados**

## Configuração do ambiente de execução
1. Definir `VITE_SUPABASE_URL` e `VITE_SUPABASE_PUBLISHABLE_KEY` no ambiente da aplicação.
2. Nunca colocar `service_role` ou chaves secretas em variáveis `VITE_*`.
3. Em Supabase > Authentication > URL Configuration, adicionar a URL publicada do app à lista de URLs de redirecionamento, incluindo `https://SEU-DOMINIO/redefinir-senha`. Para ambiente local, incluir a URL de desenvolvimento equivalente.
4. Conferir o template de e-mail de recuperação e as regras de senha no Supabase Auth.

## Testes obrigatórios antes de publicar
- `npm install`, `npm run lint`, `npm run build`; registrar resultado no PR.
- Login do administrador; recarregar a página e verificar persistência.
- Usuário sem papel: login bloqueado no SIGO.
- Usuário operacional: visualizar, criar e editar prestadores, mas não excluir.
- Administrador: exclusão de prestadores permitida após confirmação.
- Usuário anônimo: acesso negado às três tabelas.
- Verificar que `created_by` e `created_at` não podem ser alterados.
- Recuperação de senha por e-mail com URL permitida, senha nova e novo login.
- Verificar avisos do Security Advisor e Performance Advisor.
- Validar que Financeiro não expõe dados ou endpoints sem autorização; proteção visual não substitui RLS.

## Próximos módulos orientados à operação
1. Bases e veículos: Cross Guarulhos, Cross Sul, Cross Barueri e CD Limão.
2. Rotas: 1ª saída, retorno à base, 2ª saída e região residencial dos prestadores.
3. Ocorrências: quebra de moto, chuva/alagamento, recusa de recebimento, reentrega e devolução.
4. Prestações: romaneios, pendências, responsável, SLA e histórico auditável.
5. Dashboard: efetividade, entregas, rotas críticas e produtividade por base.

**Não importar dados pessoais ou produção até validar papéis, políticas RLS e consentimento operacional.**
