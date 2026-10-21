#!/usr/bin/env python3
"""Interface HTTP local para o quadro e a configuração dos agentes."""

import json
import os
import re
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


DIR = Path(__file__).resolve().parent
NOME_TAREFA = re.compile(r"[a-z0-9-]{1,41}\Z")
LIMITE_CORPO = 16 * 1024


def ler_env(caminho):
    valores = {}
    try:
        linhas = caminho.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError):
        return valores
    for linha in linhas:
        linha = linha.strip()
        if not linha or linha.startswith("#") or "=" not in linha:
            continue
        chave, valor = linha.split("=", 1)
        valor = valor.strip()
        if len(valor) >= 2 and valor[0] == valor[-1] and valor[0] in "\"'":
            valor = valor[1:-1]
        valores[chave.strip()] = valor
    return valores


def presente(valores, chave):
    return valores.get(chave) or None


def agentes(projeto):
    estado = ler_env(projeto / ".git/agentes/gerente.env")
    config = os.environ.get("AGENTES_CODEX_CONFIG")
    if not config:
        config = str(Path(os.environ.get("XDG_CONFIG_HOME") or "~/.config").expanduser() / "agentes/codex.env")
    codex = ler_env(Path(config).expanduser())
    return {
        "gerente": {"modelo": presente(estado, "gerente_modelo"), "nivel": presente(estado, "gerente_nivel")},
        "codex": {"modelo": presente(codex, "modelo"), "nivel_fixo": presente(estado, "codex_nivel")},
        "claude": {"modelo": presente(estado, "claude_modelo"), "nivel": presente(estado, "claude_nivel")},
        "gemini": "desligado",
    }


def quadro(projeto):
    tarefas = []
    for caminho in sorted((projeto / ".git/agentes/tarefas").glob("*.json")):
        try:
            tarefa = json.loads(caminho.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError):
            continue
        if isinstance(tarefa, dict):
            tarefas.append(tarefa)
    return {"projeto": projeto.name, "tarefas": tarefas}


class Servidor(BaseHTTPRequestHandler):
    projeto = None
    porta = None

    def responder(self, status, dados):
        corpo = json.dumps(dados, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(corpo)))
        self.end_headers()
        self.wfile.write(corpo)

    def host_valido(self):
        hosts = self.headers.get_all("Host", [])
        return len(hosts) == 1 and hosts[0] in (f"127.0.0.1:{self.porta}", f"localhost:{self.porta}")

    def do_GET(self):
        if not self.host_valido():
            return self.responder(400, {"erro": "Host inválido"})
        if self.path == "/api/quadro":
            return self.responder(200, quadro(self.projeto))
        if self.path == "/api/agentes":
            return self.responder(200, agentes(self.projeto))
        if self.path == "/":
            index = DIR / "index.html"
            try:
                corpo = index.read_bytes()
            except OSError:
                corpo = b"<!doctype html><html lang='pt'><meta charset='utf-8'><title>UI</title><p>index.html nao existe.</p></html>"
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(corpo)))
            self.end_headers()
            self.wfile.write(corpo)
            return
        self.responder(404, {"erro": "Não encontrado"})

    def ler_corpo(self):
        tamanho = self.headers.get("Content-Length")
        try:
            tamanho = int(tamanho)
        except (TypeError, ValueError):
            return None
        if not 0 <= tamanho <= LIMITE_CORPO:
            return None
        try:
            dados = json.loads(self.rfile.read(tamanho))
        except (UnicodeError, json.JSONDecodeError):
            return None
        return dados if isinstance(dados, dict) else None

    def executar(self, argumentos):
        try:
            resultado = subprocess.run(argumentos, capture_output=True, text=True, encoding="utf-8", errors="replace", check=False)
        except OSError as erro:
            self.responder(500, {"erro": str(erro)})
            return False
        if resultado.returncode:
            self.responder(400, {"erro": resultado.stderr.strip()})
            return False
        return True

    def do_POST(self):
        if not self.host_valido():
            return self.responder(400, {"erro": "Host inválido"})
        origens = self.headers.get_all("Origin", [])
        if len(origens) > 1 or (origens and origens[0] != f"http://{self.headers['Host']}"):
            return self.responder(400, {"erro": "Origin inválido"})
        if self.path not in ("/api/config", "/api/cancelar"):
            return self.responder(404, {"erro": "Não encontrado"})
        dados = self.ler_corpo()
        if dados is None:
            return self.responder(400, {"erro": "Corpo inválido"})
        if self.path == "/api/config":
            alvo, args = dados.get("alvo"), dados.get("args")
            if alvo not in ("gerente", "codex", "claude") or not isinstance(args, list) or len(args) > 3 or any(not isinstance(arg, str) or len(arg) > 40 for arg in args):
                return self.responder(400, {"erro": "Configuração inválida"})
            comando = [str(DIR.parent / "scripts/gerente-config.sh"), str(self.projeto), alvo, *args]
            if self.executar(comando):
                self.responder(200, agentes(self.projeto))
        else:
            nome = dados.get("nome")
            if not isinstance(nome, str) or not NOME_TAREFA.fullmatch(nome):
                return self.responder(400, {"erro": "Nome inválido"})
            comando = [str(DIR.parent / "scripts/quadro.sh"), "cancelar", str(self.projeto), nome]
            if self.executar(comando):
                self.responder(200, {"ok": True})


def main():
    if len(sys.argv) not in (2, 3):
        raise SystemExit("Uso: python3 servidor.py <projeto> [porta]")
    projeto = Path(sys.argv[1]).expanduser().resolve()
    try:
        porta = int(sys.argv[2]) if len(sys.argv) == 3 else 8765
    except ValueError:
        raise SystemExit("Porta inválida") from None
    if not 1 <= porta <= 65535:
        raise SystemExit("Porta inválida")
    Servidor.projeto = projeto
    Servidor.porta = porta
    with HTTPServer(("127.0.0.1", porta), Servidor) as httpd:
        print(f"Servidor em http://127.0.0.1:{porta}/", flush=True)
        httpd.serve_forever()


if __name__ == "__main__":
    main()
