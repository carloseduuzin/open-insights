import { useState, type ReactNode } from "react";
import { Link, useNavigate, useRouterState } from "@tanstack/react-router";
import {
  BarChart3,
  ClipboardList,
  FileText,
  LayoutDashboard,
  LogOut,
  Menu,
  Receipt,
  Route as RouteIcon,
  Settings,
  TriangleAlert,
  Users,
  Wallet,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { authService } from "@/services/auth";

const navItems = [
  { label: "Dashboard", to: "/dashboard", icon: LayoutDashboard },
  { label: "Prestadores", to: "/prestadores", icon: Users },
  { label: "Rotas", to: "/rotas", icon: RouteIcon },
  { label: "Romaneios", to: "/romaneios", icon: ClipboardList },
  { label: "Prestação", to: "/prestacao", icon: Receipt },
  { label: "Financeiro", to: "/financeiro", icon: Wallet },
  { label: "Ocorrências", to: "/ocorrencias", icon: TriangleAlert },
  { label: "Relatórios", to: "/relatorios", icon: BarChart3 },
  { label: "Configurações", to: "/configuracoes", icon: Settings },
] as const;

export function AppShell({
  titulo,
  descricao,
  children,
}: {
  titulo: string;
  descricao?: string;
  children: ReactNode;
}) {
  const [recolhida, setRecolhida] = useState(false);
  const [mobileAberta, setMobileAberta] = useState(false);
  const navigate = useNavigate();
  const pathname = useRouterState({ select: (s) => s.location.pathname });

  function sair() {
    authService.sair();
    navigate({ to: "/", replace: true });
  }

  return (
    <div className="flex min-h-screen w-full bg-background">
      {mobileAberta && (
        <button
          aria-label="Fechar menu"
          onClick={() => setMobileAberta(false)}
          className="fixed inset-0 z-30 bg-background/70 backdrop-blur-sm md:hidden"
        />
      )}

      <aside
        className={cn(
          "fixed inset-y-0 left-0 z-40 flex flex-col border-r border-sidebar-border bg-sidebar transition-[width,transform] duration-300 md:static md:translate-x-0",
          recolhida ? "w-[76px]" : "w-64",
          mobileAberta ? "translate-x-0" : "-translate-x-full",
        )}
      >
        <div className="flex h-16 items-center gap-3 px-4">
          <div className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-primary text-primary-foreground shadow-[var(--shadow-glow)]">
            <FileText className="size-5" />
          </div>
          {!recolhida && (
            <div className="min-w-0">
              <p className="truncate text-sm font-semibold tracking-wide text-sidebar-foreground">
                SIGO
              </p>
              <p className="truncate text-[11px] text-muted-foreground">RenoveLog Operations</p>
            </div>
          )}
        </div>

        <nav className="flex-1 space-y-1 overflow-y-auto px-3 py-4">
          {navItems.map((item) => {
            const ativo = pathname === item.to;
            return (
              <Link
                key={item.to}
                to={item.to}
                onClick={() => setMobileAberta(false)}
                title={item.label}
                className={cn(
                  "flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors",
                  ativo
                    ? "bg-sidebar-primary text-sidebar-primary-foreground"
                    : "text-sidebar-foreground/80 hover:bg-sidebar-accent hover:text-sidebar-accent-foreground",
                )}
              >
                <item.icon className="size-[18px] shrink-0" />
                {!recolhida && <span className="truncate">{item.label}</span>}
              </Link>
            );
          })}
        </nav>

        <div className="border-t border-sidebar-border p-3">
          <button
            onClick={sair}
            className="flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium text-sidebar-foreground/80 transition-colors hover:bg-sidebar-accent hover:text-sidebar-accent-foreground"
          >
            <LogOut className="size-[18px] shrink-0" />
            {!recolhida && <span>Sair</span>}
          </button>
        </div>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="sticky top-0 z-20 flex h-16 items-center gap-3 border-b border-border bg-background/80 px-4 backdrop-blur md:px-6">
          <button
            onClick={() => setRecolhida((v) => !v)}
            aria-label="Recolher menu"
            className="hidden rounded-lg border border-border p-2 text-muted-foreground transition-colors hover:bg-accent hover:text-foreground md:block"
          >
            <Menu className="size-4" />
          </button>
          <button
            onClick={() => setMobileAberta(true)}
            aria-label="Abrir menu"
            className="rounded-lg border border-border p-2 text-muted-foreground transition-colors hover:bg-accent hover:text-foreground md:hidden"
          >
            <Menu className="size-4" />
          </button>
          <div className="min-w-0">
            <h1 className="truncate text-base font-semibold md:text-lg">{titulo}</h1>
            {descricao && (
              <p className="hidden truncate text-xs text-muted-foreground sm:block">{descricao}</p>
            )}
          </div>
        </header>

        <main className="flex-1 p-4 md:p-6">{children}</main>
      </div>
    </div>
  );
}
