import { createFileRoute } from "@tanstack/react-router";
import { AppShell } from "@/layout/AppShell";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { rotasCriticas } from "@/data/mock";

export const Route = createFileRoute("/rotas")({
  head: () => ({
    meta: [
      { title: "Rotas — SIGO | RenoveLog" },
      { name: "description", content: "Acompanhamento das rotas em operação, SLA e status." },
      { property: "og:title", content: "Rotas — SIGO | RenoveLog" },
      { property: "og:description", content: "Rotas ativas, entregas e desempenho por base." },
    ],
  }),
  component: Rotas,
});

function Rotas() {
  return (
    <AppShell titulo="Rotas" descricao="Acompanhamento das rotas em operação">
      <Card className="border-border bg-card">
        <CardHeader>
          <CardTitle className="text-base">Rotas em operação</CardTitle>
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
              {rotasCriticas.map((r) => (
                <TableRow key={r.id}>
                  <TableCell className="font-medium">{r.codigo}</TableCell>
                  <TableCell>{r.base}</TableCell>
                  <TableCell>{r.prestador}</TableCell>
                  <TableCell className="text-right">{r.entregas}</TableCell>
                  <TableCell className="text-right">{r.sla.toFixed(1)}%</TableCell>
                  <TableCell>
                    <Badge
                      className={
                        r.status === "Crítica"
                          ? "bg-destructive/15 text-destructive"
                          : r.status === "Atrasada"
                            ? "bg-warning/15 text-warning"
                            : "bg-success/15 text-success"
                      }
                    >
                      {r.status}
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
