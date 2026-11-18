import { requireSupabase } from "@/lib/supabase";
import type { Prestador } from "@/types";

type PrestadorInput = Omit<Prestador, "id">;

function db() { return requireSupabase(); }

export const prestadoresService = {
  async listar(): Promise<Prestador[]> {
    const { data, error } = await db().from("prestadores")
      .select("id,nome,documento,veiculo,placa,base,disponibilidade,status")
      .order("nome");
    if (error) throw error;
    return (data ?? []) as Prestador[];
  },
  async criar(input: PrestadorInput): Promise<void> {
    const { data: { user }, error: authError } = await db().auth.getUser();
    if (authError || !user) throw new Error("Sessão expirada. Entre novamente.");
    const { error } = await db().from("prestadores").insert({
      ...input, created_by: user.id, updated_by: user.id,
    });
    if (error) throw error;
  },
  async atualizar(id: string, input: PrestadorInput): Promise<void> {
    const { data: { user }, error: authError } = await db().auth.getUser();
    if (authError || !user) throw new Error("Sessão expirada. Entre novamente.");
    const { error } = await db().from("prestadores")
      .update({ ...input, updated_by: user.id }).eq("id", id);
    if (error) throw error;
  },
  async excluir(id: string): Promise<void> {
    const { error } = await db().from("prestadores").delete().eq("id", id);
    if (error) throw error;
  },
  async ehAdmin(): Promise<boolean> {
    const { data, error } = await db().rpc("sigo_has_role", { requested_role: "admin" });
    if (error) throw error;
    return data === true;
  },
};
