import type { EntregaPorBase, PendenciaPorDia, Prestador, Rota } from "@/types";

export const indicadores = {
  rotasDoDia: 128,
  motosDisponiveis: 46,
  fiorinos: 19,
  pendencias: 12,
  sla: 96.4,
  valorQuinzena: 284350.75,
};

export const entregasPorBase: EntregaPorBase[] = [
  { base: "Guarulhos", entregas: 412 },
  { base: "Osasco", entregas: 338 },
  { base: "Santo André", entregas: 296 },
  { base: "Campinas", entregas: 254 },
  { base: "Sorocaba", entregas: 187 },
  { base: "Jundiaí", entregas: 143 },
];

export const pendenciasPorDia: PendenciaPorDia[] = [
  { dia: "01", pendencias: 18 },
  { dia: "02", pendencias: 14 },
  { dia: "03", pendencias: 21 },
  { dia: "04", pendencias: 11 },
  { dia: "05", pendencias: 9 },
  { dia: "06", pendencias: 16 },
  { dia: "07", pendencias: 12 },
  { dia: "08", pendencias: 7 },
];

export const rotasCriticas: Rota[] = [
  {
    id: "1",
    codigo: "RT-2041",
    base: "Guarulhos",
    prestador: "Marcos Lima",
    entregas: 64,
    sla: 81.2,
    status: "Crítica",
  },
  {
    id: "2",
    codigo: "RT-2088",
    base: "Osasco",
    prestador: "Fernanda Rocha",
    entregas: 48,
    sla: 87.5,
    status: "Atrasada",
  },
  {
    id: "3",
    codigo: "RT-2112",
    base: "Campinas",
    prestador: "Diego Martins",
    entregas: 71,
    sla: 89.9,
    status: "Em rota",
  },
  {
    id: "4",
    codigo: "RT-2130",
    base: "Santo André",
    prestador: "Aline Souza",
    entregas: 39,
    sla: 78.4,
    status: "Crítica",
  },
  {
    id: "5",
    codigo: "RT-2156",
    base: "Sorocaba",
    prestador: "Rafael Nunes",
    entregas: 52,
    sla: 91.1,
    status: "Em rota",
  },
];

export const prestadores: Prestador[] = [
  {
    id: "1",
    nome: "Marcos Lima",
    documento: "128.455.900-21",
    veiculo: "Moto",
    base: "Guarulhos",
    status: "Ativo",
  },
  {
    id: "2",
    nome: "Fernanda Rocha",
    documento: "455.210.880-03",
    veiculo: "Fiorino",
    base: "Osasco",
    status: "Ativo",
  },
  {
    id: "3",
    nome: "Diego Martins",
    documento: "907.331.220-77",
    veiculo: "VUC",
    base: "Campinas",
    status: "Pendente",
  },
  {
    id: "4",
    nome: "Aline Souza",
    documento: "332.998.114-40",
    veiculo: "Moto",
    base: "Santo André",
    status: "Inativo",
  },
];
