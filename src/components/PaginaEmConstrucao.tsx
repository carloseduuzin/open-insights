import { Construction } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";

export function PaginaEmConstrucao({ modulo }: { modulo: string }) {
  return (
    <Card className="border-border bg-card">
      <CardContent className="flex flex-col items-center justify-center gap-3 py-20 text-center">
        <div className="flex size-12 items-center justify-center rounded-xl bg-warning/15 text-warning">
          <Construction className="size-6" />
        </div>
        <h2 className="text-lg font-semibold">Módulo {modulo}</h2>
        <p className="max-w-md text-sm text-muted-foreground">
          Estrutura pronta para receber as telas operacionais deste módulo do SIGO.
        </p>
      </CardContent>
    </Card>
  );
}
