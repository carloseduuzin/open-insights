export type StatusRota = "Em rota" | "Atrasada" | "Concluída" | "Crítica";

export interface Prestador {
  id: string;
  nome: string;
  documento: string;
  veiculo: "Moto" | "Fiorino" | "VUC";
  base: string;
  status: "Ativo" | "Inativo" | "Pendente";
}

export interface Rota {
  id: string;
  codigo: string;
  base: string;
  prestador: string;
  entregas: number;
  sla: number;
  status: StatusRota;
}

export interface EntregaPorBase {
  base: string;
  entregas: number;
}

export interface PendenciaPorDia {
  dia: string;
  pendencias: number;
}

export interface SessaoUsuario {
  nome: string;
  email: string;
}
