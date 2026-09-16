import type { LucideIcon } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { cn } from "@/lib/utils";

export function CardIndicador({
  titulo,
  valor,
  detalhe,
  icon: Icon,
  tom = "primary",
}: {
  titulo: string;
  valor: string;
  detalhe?: string;
  icon: LucideIcon;
  tom?: "primary" | "success" | "warning" | "destructive";
}) {
  const tons = {
    primary: "bg-primary/15 text-primary",
    success: "bg-success/15 text-success",
    warning: "bg-warning/15 text-warning",
    destructive: "bg-destructive/15 text-destructive",
  } as const;

  return (
    <Card className="border-border bg-card shadow-[var(--shadow-elevated)]">
      <CardContent className="flex items-start justify-between gap-4 p-5">
        <div className="min-w-0">
          <p className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
            {titulo}
          </p>
          <p className="mt-2 truncate text-2xl font-semibold tracking-tight">{valor}</p>
          {detalhe && <p className="mt-1 text-xs text-muted-foreground">{detalhe}</p>}
        </div>
        <div className={cn("flex size-10 shrink-0 items-center justify-center rounded-xl", tons[tom])}>
          <Icon className="size-5" />
        </div>
      </CardContent>
    </Card>
  );
}
