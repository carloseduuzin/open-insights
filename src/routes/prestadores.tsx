import { useEffect, useMemo, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Pencil, Plus, Search, Trash2 } from "lucide-react";
import { z } from "zod";
import { AppShell } from "@/layout/AppShell";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { prestadoresService } from "@/services/prestadores";
import type { Disponibilidade, Prestador, TipoVeiculo } from "@/types";

export const Route = createFileRoute("/prestadores")({
  head: () => ({
    meta: [
      { title: "Prestadores — SIGO | RenoveLog" },
      {
        name: "description",
        content: "Cadastro, edição e listagem dos prestadores de transporte da RenoveLog.",
      },
      { property: "og:title", content: "Prestadores — SIGO | RenoveLog" },
      { property: "og:description", content: "Gestão de prestadores, veículos, bases e disponibilidade." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: Prestadores,
});

const BASES = ["Cross Guarulhos", "Cross Sul", "Cross Barueri", "CD Limão"];
const VEICULOS: TipoVeiculo[] = ["Moto", "Fiorino", "VUC"];
const DISPON: Disponibilidade[] = ["Disponível", "Em rota", "Indisponível"];
const STATUS: Prestador["status"][] = ["Ativo", "Pendente", "Inativo"];

const schema = z.object({
  nome: z.string().trim().min(3, "Informe o nome").max(100),
  documento: z.string().trim().min(11, "Documento inválido").max(20),
  placa: z.string().trim().min(7, "Placa inválida").max(8),
  base: z.string().min(1, "Selecione a base"),
});

type Form = Omit<Prestador, "id">;
const vazio: Form = {
  nome: "",
  documento: "",
  veiculo: "Moto",
  placa: "",
  base: "",
  disponibilidade: "Disponível",
  status: "Ativo",
};

const tomDisp: Record<Disponibilidade, string> = {
  Disponível: "bg-success/15 text-success",
  "Em rota": "bg-primary/15 text-primary",
  Indisponível: "bg-muted text-muted-foreground",
};
const tomStatus: Record<Prestador["status"], string> = {
  Ativo: "bg-success/15 text-success",
  Pendente: "bg-warning/15 text-warning",
  Inativo: "bg-muted text-muted-foreground",
};

function Prestadores() {
  const [lista, setLista] = useState<Prestador[]>([]);
  const [busca, setBusca] = useState("");
  const [carregando, setCarregando] = useState(true);
  const [salvando, setSalvando] = useState(false);
  const [erroApi, setErroApi] = useState<string | null>(null);
  const [admin, setAdmin] = useState(false);

  async function recarregar() {
    setErroApi(null);
    try { setLista(await prestadoresService.listar()); }
    catch (e) { setErroApi(e instanceof Error ? e.message : "Falha ao consultar prestadores."); }
    finally { setCarregando(false); }
  }

  useEffect(() => {
    void recarregar();
    prestadoresService.ehAdmin().then(setAdmin).catch(() => setAdmin(false));
  }, []);
  const [fBase, setFBase] = useState("todas");
  const [fDisp, setFDisp] = useState("todas");
  const [aberto, setAberto] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState<Form>(vazio);
  const [erros, setErros] = useState<Record<string, string>>({});

  const basesDisponiveis = useMemo(() => [...new Set([...BASES, ...lista.map((p) => p.base)])].sort(), [lista]);

  const filtrados = useMemo(
    () =>
      lista.filter(
        (p) =>
          (fBase === "todas" || p.base === fBase) &&
          (fDisp === "todas" || p.disponibilidade === fDisp) &&
          `${p.nome} ${p.documento} ${p.placa}`.toLowerCase().includes(busca.toLowerCase()),
      ),
    [lista, busca, fBase, fDisp],
  );

  const abrirNovo = () => {
    setErroApi(null);
    setEditId(null);
    setForm(vazio);
    setErros({});
    setAberto(true);
  };
  const abrirEdicao = (p: Prestador) => {
    setErroApi(null);
    const { id, ...resto } = p;
    setEditId(id);
    setForm(resto);
    setErros({});
    setAberto(true);
  };

  const salvar = async () => {
    const r = schema.safeParse(form);
    if (!r.success) {
      const e: Record<string, string> = {};
      r.error.issues.forEach((i) => (e[String(i.path[0])] = i.message));
      setErros(e);
      return;
    }
    setSalvando(true);
    setErroApi(null);
    try {
      const dados = { ...form, placa: form.placa.toUpperCase() };
      if (editId) await prestadoresService.atualizar(editId, dados);
      else await prestadoresService.criar(dados);
      setAberto(false);
      await recarregar();
    } catch (e) {
      const mensagem = e instanceof Error ? e.message : "Não foi possível salvar.";
      setErroApi(mensagem);
      setErros((anterior) => ({ ...anterior, formulario: mensagem }));
    } finally {
      setSalvando(false);
    }
  };

  const excluir = async (p: Prestador) => {
    if (!admin || !window.confirm(`Excluir permanentemente ${p.nome}? Esta ação não pode ser desfeita.`)) return;
    setErroApi(null);
    try {
      await prestadoresService.excluir(p.id);
      await recarregar();
    } catch (e) {
      setErroApi(e instanceof Error ? e.message : "Não foi possível excluir.");
    }
  };

  const set = <K extends keyof Form>(k: K, v: Form[K]) => setForm((f) => ({ ...f, [k]: v }));

  return (
    <AppShell titulo="Prestadores" descricao="Cadastro, edição e disponibilidade da malha">
      {erroApi && <p role="alert" className="mb-4 rounded-lg border border-destructive/40 p-3 text-sm text-destructive">{erroApi}</p>}
      <Card className="border-border bg-card">
        <CardHeader className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
          <CardTitle className="text-base">{carregando ? "Carregando prestadores..." : `Prestadores cadastrados (${filtrados.length})`}</CardTitle>
          <Button onClick={abrirNovo}>
            <Plus className="h-4 w-4" /> Novo prestador
          </Button>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid gap-3 md:grid-cols-3">
            <div className="relative">
              <Search className="absolute left-3 top-2.5 h-4 w-4 text-muted-foreground" />
              <Input
                className="pl-9"
                placeholder="Buscar por nome, documento ou placa"
                value={busca}
                onChange={(e) => setBusca(e.target.value)}
              />
            </div>
            <Select value={fBase} onValueChange={setFBase}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="todas">Todas as bases</SelectItem>
                {basesDisponiveis.map((b) => <SelectItem key={b} value={b}>{b}</SelectItem>)}
              </SelectContent>
            </Select>
            <Select value={fDisp} onValueChange={setFDisp}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="todas">Toda disponibilidade</SelectItem>
                {DISPON.map((d) => <SelectItem key={d} value={d}>{d}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Nome</TableHead>
                  <TableHead>Documento</TableHead>
                  <TableHead>Veículo</TableHead>
                  <TableHead>Placa</TableHead>
                  <TableHead>Base</TableHead>
                  <TableHead>Disponibilidade</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Ações</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filtrados.map((p) => (
                  <TableRow key={p.id}>
                    <TableCell className="font-medium">{p.nome}</TableCell>
                    <TableCell>{p.documento}</TableCell>
                    <TableCell>{p.veiculo}</TableCell>
                    <TableCell className="font-mono text-xs">{p.placa}</TableCell>
                    <TableCell>{p.base}</TableCell>
                    <TableCell><Badge className={tomDisp[p.disponibilidade]}>{p.disponibilidade}</Badge></TableCell>
                    <TableCell><Badge className={tomStatus[p.status]}>{p.status}</Badge></TableCell>
                    <TableCell className="text-right">
                      <Button size="icon" variant="ghost" aria-label="Editar" onClick={() => abrirEdicao(p)}>
                        <Pencil className="h-4 w-4" />
                      </Button>
                      {admin && <Button
                        size="icon"
                        variant="ghost"
                        aria-label="Excluir permanentemente"
                        onClick={() => void excluir(p)}
                      >
                        <Trash2 className="h-4 w-4 text-destructive" />
                      </Button>}
                    </TableCell>
                  </TableRow>
                ))}
                {filtrados.length === 0 && (
                  <TableRow>
                    <TableCell colSpan={8} className="py-8 text-center text-muted-foreground">
                      Nenhum prestador encontrado.
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      <Dialog open={aberto} onOpenChange={setAberto}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>{editId ? "Editar prestador" : "Novo prestador"}</DialogTitle>
          </DialogHeader>
          {erros["formulario"] && <p role="alert" className="text-sm text-destructive">{erros["formulario"]}</p>}
          <div className="grid gap-4 sm:grid-cols-2">
            <Campo label="Nome" erro={erros["nome"]} className="sm:col-span-2">
              <Input value={form.nome} maxLength={100} onChange={(e) => set("nome", e.target.value)} />
            </Campo>
            <Campo label="CPF/CNPJ" erro={erros["documento"]}>
              <Input value={form.documento} maxLength={20} onChange={(e) => set("documento", e.target.value)} />
            </Campo>
            <Campo label="Base" erro={erros["base"]}>
              <Select value={form.base} onValueChange={(v) => set("base", v)}>
                <SelectTrigger><SelectValue placeholder="Selecione" /></SelectTrigger>
                <SelectContent>{BASES.map((b) => <SelectItem key={b} value={b}>{b}</SelectItem>)}</SelectContent>
              </Select>
            </Campo>
            <Campo label="Veículo">
              <Select value={form.veiculo} onValueChange={(v) => set("veiculo", v as TipoVeiculo)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{VEICULOS.map((v) => <SelectItem key={v} value={v}>{v}</SelectItem>)}</SelectContent>
              </Select>
            </Campo>
            <Campo label="Placa" erro={erros["placa"]}>
              <Input value={form.placa} maxLength={8} placeholder="ABC-1D23" onChange={(e) => set("placa", e.target.value)} />
            </Campo>
            <Campo label="Disponibilidade">
              <Select value={form.disponibilidade} onValueChange={(v) => set("disponibilidade", v as Disponibilidade)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{DISPON.map((d) => <SelectItem key={d} value={d}>{d}</SelectItem>)}</SelectContent>
              </Select>
            </Campo>
            <Campo label="Status">
              <Select value={form.status} onValueChange={(v) => set("status", v as Prestador["status"])}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{STATUS.map((s) => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
              </Select>
            </Campo>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setAberto(false)}>Cancelar</Button>
            <Button onClick={() => void salvar()} disabled={salvando}>{salvando ? "Salvando..." : editId ? "Salvar alterações" : "Cadastrar"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </AppShell>
  );
}

function Campo({
  label,
  erro,
  className,
  children,
}: {
  label: string;
  erro?: string | undefined;
  className?: string | undefined;
  children: React.ReactNode;
}) {
  return (
    <div className={`space-y-1.5 ${className ?? ""}`}>
      <Label>{label}</Label>
      {children}
      {erro && <p className="text-xs text-destructive">{erro}</p>}
    </div>
  );
}
