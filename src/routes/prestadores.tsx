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
import { prestadores } from "@/data/mock";

export const Route = createFileRoute("/prestadores")({
  head: () => ({
    meta: [
      { title: "Prestadores — SIGO | RenoveLog" },
      {
        name: "description",
        content: "Cadastro e status dos prestadores de transporte da operação RenoveLog.",
      },
      { property: "og:title", content: "Prestadores — SIGO | RenoveLog" },
      { property: "og:description", content: "Gestão de prestadores, veículos e bases." },
    ],
  }),
  component: Prestadores,
});

function Prestadores() {
  return (
    <AppShell titulo="Prestadores" descricao="Cadastro e status da malha de prestadores">
      <Card className="border-border bg-card">
        <CardHeader>
          <CardTitle className="text-base">Prestadores cadastrados</CardTitle>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Nome</TableHead>
                <TableHead>Documento</TableHead>
                <TableHead>Veículo</TableHead>
                <TableHead>Base</TableHead>
                <TableHead>Status</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {prestadores.map((p) => (
                <TableRow key={p.id}>
                  <TableCell className="font-medium">{p.nome}</TableCell>
                  <TableCell>{p.documento}</TableCell>
                  <TableCell>{p.veiculo}</TableCell>
                  <TableCell>{p.base}</TableCell>
                  <TableCell>
                    <Badge
                      className={
                        p.status === "Ativo"
                          ? "bg-success/15 text-success"
                          : p.status === "Pendente"
                            ? "bg-warning/15 text-warning"
                            : "bg-muted text-muted-foreground"
                      }
                    >
                      {p.status}
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
