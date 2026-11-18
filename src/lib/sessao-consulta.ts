import type { QueryClient } from "@tanstack/react-query";

export const chaveSessao = ["sigo-sessao"] as const;
type SessaoCache = { nome: string; email: string } | null;

export function opcoesSessao<T>(carregar: () => Promise<T>) {
  return { queryKey: chaveSessao, queryFn: carregar, staleTime: 30_000, gcTime: 300_000, retry: false as const };
}

export async function sincronizarSessaoCache(client: QueryClient, evento: string, email?: string) {
  if (evento === "SIGNED_OUT") {
    await client.cancelQueries();
    client.removeQueries({ predicate: query => query.queryKey[0] !== chaveSessao[0] });
    client.setQueryData(chaveSessao, null);
    return;
  }
  if (!["SIGNED_IN", "TOKEN_REFRESHED", "USER_UPDATED"].includes(evento)) return;
  const anterior = client.getQueryData<SessaoCache>(chaveSessao);
  if (anterior?.email && anterior.email !== email) {
    await client.cancelQueries();
    client.removeQueries({ predicate: query => query.queryKey[0] !== chaveSessao[0] });
    await client.resetQueries({ queryKey: chaveSessao });
  } else {
    await client.invalidateQueries({ queryKey: chaveSessao }, { cancelRefetch: false });
  }
}
