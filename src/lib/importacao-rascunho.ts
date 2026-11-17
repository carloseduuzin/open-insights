import type { Linha } from "@/lib/greenmile-import";

export type ArquivoImportacao = { nome: string; conteudo: string; linhas: Linha[]; colunas: string[] };
type Rascunho = {
  paradas: ArquivoImportacao | null;
  pedidos: ArquivoImportacao | null;
  confirmada: boolean;
  feedback: string;
};
// Somente memoria da aba: nao grava CSVs operacionais no armazenamento do navegador.
// As chamadas ocorrem em efeitos/eventos do cliente; nenhum rascunho e lido no SSR.
const porUsuario = new Map<string, Rascunho>();
export function obterRascunhoImportacao(usuarioId: string) {
  if (typeof window === "undefined") return undefined;
  return porUsuario.get(usuarioId);
}
export function guardarRascunhoImportacao(usuarioId: string, rascunho: Rascunho) {
  if (typeof window === "undefined") return;
  // Uma conta nunca recebe os arquivos da conta anterior na mesma aba.
  for (const id of porUsuario.keys()) if (id !== usuarioId) porUsuario.delete(id);
  porUsuario.set(usuarioId, rascunho);
}

