import { createFileRoute } from "@tanstack/react-router";
import {
  Bike,
  CircleGauge,
  Truck,
  TriangleAlert,
  Wallet,
  Route as RouteIcon,
} from "lucide-react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { AppShell } from "@/layout/AppShell";
import { CardIndicador } from "@/components/CardIndicador";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { entregasPorBase, indicadores, pendenciasPorDia, rotasCriticas } from "@/data/mock";

export const Route = createFileRoute("/dashboard")({
  head: () => ({
    meta: [
      { title: "Dashboard Operacional — SIGO | RenoveLog" },
      {
        name: "description",
        content:
          "Indicadores diários de rotas, frota, pendências, SLA e faturamento da operação RenoveLog.",
      },
      { property: "og:title", content: "Dashboard Operacional — SIGO | RenoveLog" },
      {
        property: "og:description",
        content: "Rotas do dia, SLA, pendências e rotas críticas em tempo real.",
      },
    ],
  }),
  component: Dashboard,
});

const tooltipStyle = {
  backgroundColor: "var(--card)",
  border: "1px solid var(--border)",
  borderRadius: "10px",
  color: "var(--foreground)",
  fontSize: "12px",
};

function Dashboard() {
  return (
    <AppShell titulo="Dashboard" descricao="Visão geral da operação do dia">
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        <CardIndicador
          titulo="Rotas do dia"
          valor={String(indicadores.rotasDoDia)}
          detalhe="+8 em relação a ontem"
          icon={RouteIcon}
        />
        <CardIndicador
          titulo="Motos disponíveis"
          valor={String(indicadores.motosDisponiveis)}
          detalhe="Frota leve"
          icon={Bike}
          tom="success"
        />
        <CardIndicador
          titulo="Fiorinos"
          valor={String(indicadores.fiorinos)}
          detalhe="Frota utilitária"
          icon={Truck}
          tom="primary"
        />
        <CardIndicador
          titulo="Pendências"
          valor={String(indicadores.pendencias)}
          detalhe="Aguardando tratativa"
          icon={TriangleAlert}
          tom="warning"
        />
        <CardIndicador
          titulo="SLA"
          valor={`${indicadores.sla.toFixed(1)}%`}
          detalhe="Meta 95%"
          icon={CircleGauge}
          tom="success"
        />
        <CardIndicador
          titulo="Valor da quinzena"
          valor={indicadores.valorQuinzena.toLocaleString("pt-BR", {
            style: "currency",
            currency: "BRL",
          })}
          detalhe="Prévia de pagamento"
          icon={Wallet}
          tom="primary"
        />
      </div>

      <div className="mt-6 grid gap-4 lg:grid-cols-2">
        <Card className="border-border bg-card">
          <CardHeader>
            <CardTitle className="text-base">Entregas por Base</CardTitle>
          </CardHeader>
          <CardContent className="h-72">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={entregasPorBase}>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" vertical={false} />
                <XAxis
                  dataKey="base"
                  stroke="var(--muted-foreground)"
                  fontSize={11}
                  tickLine={false}
                  axisLine={false}
                />
                <YAxis
                  stroke="var(--muted-foreground)"
                  fontSize={11}
                  tickLine={false}
                  axisLine={false}
                />
                <Tooltip contentStyle={tooltipStyle} cursor={{ fill: "var(--accent)" }} />
                <Bar dataKey="entregas" fill="var(--chart-1)" radius={[6, 6, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>

        <Card className="border-border bg-card">
          <CardHeader>
            <CardTitle className="text-base">Pendências por Dia</CardTitle>
          </CardHeader>
          <CardContent className="h-72">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={pendenciasPorDia}>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" vertical={false} />
                <XAxis
                  dataKey="dia"
                  stroke="var(--muted-foreground)"
                  fontSize={11}
                  tickLine={false}
                  axisLine={false}
                />
                <YAxis
                  stroke="var(--muted-foreground)"
                  fontSize={11}
                  tickLine={false}
                  axisLine={false}
                />
                <Tooltip contentStyle={tooltipStyle} />
                <Line
                  type="monotone"
                  dataKey="pendencias"
                  stroke="var(--chart-3)"
                  strokeWidth={2.5}
                  dot={{ r: 3, fill: "var(--chart-3)" }}
                />
              </LineChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>
      </div>

      <Card className="mt-6 border-border bg-card">
        <CardHeader>
          <CardTitle className="text-base">Rotas Críticas</CardTitle>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Rota</TableHead>
                <TableHead>Base</TableHead>
                <TableHead>Prestador</TableHead>
                <TableHead className="text-right">Entregas</TableHead>
                <TableHead className="text-right">SLA</TableHead>
                <TableHead>Status</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rotasCriticas.map((rota) => (
                <TableRow key={rota.id}>
                  <TableCell className="font-medium">{rota.codigo}</TableCell>
                  <TableCell>{rota.base}</TableCell>
                  <TableCell>{rota.prestador}</TableCell>
                  <TableCell className="text-right">{rota.entregas}</TableCell>
                  <TableCell className="text-right">{rota.sla.toFixed(1)}%</TableCell>
                  <TableCell>
                    <Badge
                      className={
                        rota.status === "Crítica"
                          ? "bg-destructive/15 text-destructive"
                          : rota.status === "Atrasada"
                            ? "bg-warning/15 text-warning"
                            : "bg-success/15 text-success"
                      }
                    >
                      {rota.status}
                    </Badge>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </AppShell>
  );
}
