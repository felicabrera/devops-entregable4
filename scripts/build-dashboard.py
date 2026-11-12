#!/usr/bin/env python3
"""Genera grafana/dashboard.json y la copia que embebe el Helm chart.

El dashboard se construye por codigo para que los paneles queden consistentes
(mismo datasource, misma unidad, mismo intervalo) y sea facil de versionar.
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUTS = [ROOT / "grafana" / "dashboard.json", ROOT / "helm-chart" / "files" / "dashboard.json"]
DS = {"type": "prometheus", "uid": "prometheus"}
EP = 'endpoint=~"$endpoint"'
RATE = "[$__rate_interval]"

_id = 0


def next_id() -> int:
    global _id
    _id += 1
    return _id


def target(expr: str, legend: str = "__auto") -> dict:
    return {"datasource": DS, "expr": expr, "legendFormat": legend, "refId": chr(64 + next_id() % 26 + 1)}


def panel(kind: str, title: str, targets: list, x: int, y: int, w: int, h: int, unit: str = "short", **extra) -> dict:
    p = {
        "id": next_id(),
        "type": kind,
        "title": title,
        "datasource": DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": targets,
        "fieldConfig": {"defaults": {"unit": unit, "color": {"mode": "palette-classic"}}, "overrides": []},
        "options": {},
    }
    if kind == "timeseries":
        p["options"] = {
            "legend": {"displayMode": "list", "placement": "bottom", "showLegend": True},
            "tooltip": {"mode": "multi", "sort": "desc"},
        }
        p["fieldConfig"]["defaults"]["custom"] = {"lineWidth": 2, "fillOpacity": 10, "showPoints": "never"}
    if kind == "stat":
        p["options"] = {
            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
            "colorMode": "value",
            "graphMode": "area",
            "textMode": "auto",
        }
    if kind == "gauge":
        p["options"] = {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}, "showThresholdMarkers": True}
    for k, v in extra.items():
        if k == "thresholds":
            p["fieldConfig"]["defaults"]["thresholds"] = v
        elif k == "min":
            p["fieldConfig"]["defaults"]["min"] = v
        elif k == "max":
            p["fieldConfig"]["defaults"]["max"] = v
        elif k == "stack":
            p["fieldConfig"]["defaults"]["custom"]["stacking"] = {"mode": "normal", "group": "A"}
        else:
            p["options"][k] = v
    return p


def row(title: str, y: int) -> dict:
    return {"id": next_id(), "type": "row", "title": title, "collapsed": False, "gridPos": {"x": 0, "y": y, "w": 24, "h": 1}, "panels": []}


def thresholds(*steps):
    return {"mode": "absolute", "steps": [{"color": c, "value": v} for c, v in steps]}


panels = []
y = 0
panels.append(row("Resumen", y)); y += 1
panels += [
    panel("stat", "Peticiones por segundo (RPS)",
          [target(f"sum(rate(http_request_duration_seconds_count{{{EP}}}{RATE}))")], 0, y, 4, 4, "reqps"),
    panel("stat", "Latencia promedio",
          [target(f"1000 * sum(rate(http_request_duration_seconds_sum{{{EP}}}{RATE})) / sum(rate(http_request_duration_seconds_count{{{EP}}}{RATE}))")],
          4, y, 4, 4, "ms", thresholds=thresholds(("green", None), ("orange", 100), ("red", 500))),
    panel("stat", "Latencia p95",
          [target(f"1000 * histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{{{EP}}}{RATE})))")],
          8, y, 4, 4, "ms", thresholds=thresholds(("green", None), ("orange", 200), ("red", 500))),
    panel("stat", "Errores 5xx",
          [target(f"100 * (sum(rate(http_request_duration_seconds_count{{status=~\"5..\",{EP}}}{RATE})) or vector(0)) / sum(rate(http_request_duration_seconds_count{{{EP}}}{RATE}))")],
          12, y, 4, 4, "percent", thresholds=thresholds(("green", None), ("orange", 1), ("red", 5))),
    panel("stat", "Notas guardadas", [target("max(notes_total)")], 16, y, 4, 4, "short"),
    panel("stat", "Replicas del backend arriba",
          [target('count(up{job="notes-backend"} == 1) or vector(0)')], 20, y, 4, 4, "short",
          thresholds=thresholds(("red", None), ("orange", 1), ("green", 2))),
]
y += 4

panels.append(row("Trafico", y)); y += 1
panels += [
    panel("timeseries", "RPS por endpoint",
          [target(f"sum by (endpoint) (rate(http_request_duration_seconds_count{{{EP}}}{RATE}))", "{{endpoint}}")], 0, y, 8, 8, "reqps", stack=True),
    panel("timeseries", "RPS por codigo de estado",
          [target(f"sum by (status) (rate(http_request_duration_seconds_count{{{EP}}}{RATE}))", "{{status}}")], 8, y, 8, 8, "reqps", stack=True),
    panel("timeseries", "RPS por pod",
          [target(f"sum by (instance) (rate(http_request_duration_seconds_count{{{EP}}}{RATE}))", "{{instance}}")], 16, y, 8, 8, "reqps"),
]
y += 8

panels.append(row("Latencia", y)); y += 1
panels += [
    panel("timeseries", "Latencia promedio por endpoint",
          [target(f"1000 * sum by (endpoint) (rate(http_request_duration_seconds_sum{{{EP}}}{RATE})) / sum by (endpoint) (rate(http_request_duration_seconds_count{{{EP}}}{RATE}))", "{{endpoint}}")],
          0, y, 8, 8, "ms"),
    panel("timeseries", "Percentiles de latencia",
          [target(f"1000 * histogram_quantile({q}, sum by (le) (rate(http_request_duration_seconds_bucket{{{EP}}}{RATE})))", f"p{int(q*100)}") for q in (0.5, 0.95, 0.99)],
          8, y, 8, 8, "ms"),
    panel("timeseries", "Latencia p95 por pod",
          [target(f"1000 * histogram_quantile(0.95, sum by (le, instance) (rate(http_request_duration_seconds_bucket{{{EP}}}{RATE})))", "{{instance}}")],
          16, y, 8, 8, "ms"),
]
y += 8

panels.append(row("Recursos por pod", y)); y += 1
panels += [
    panel("timeseries", "CPU por pod",
          [target(f'sum by (instance) (rate(process_cpu_seconds_total{{job="notes-backend"}}{RATE}))', "{{instance}}")], 0, y, 8, 8, "percentunit"),
    panel("timeseries", "Memoria residente por pod",
          [target('sum by (instance) (process_resident_memory_bytes{job="notes-backend"})', "{{instance}}")], 8, y, 8, 8, "bytes"),
    panel("timeseries", "Descriptores abiertos por pod",
          [target('sum by (instance) (process_open_fds{job="notes-backend"})', "{{instance}}")], 16, y, 8, 8, "short"),
]
y += 8

panels.append(row("Negocio: notas", y)); y += 1
panels += [
    panel("timeseries", "Notas guardadas (total)", [target("max(notes_total)", "notas")], 0, y, 8, 8, "short"),
    panel("timeseries", "Notas creadas y borradas por minuto",
          [target(f"sum(rate(notes_created_total{RATE})) * 60", "creadas"),
           target(f"sum(rate(notes_deleted_total{RATE})) * 60", "borradas")], 8, y, 8, 8, "short"),
    panel("timeseries", "Notas creadas en 5 min (umbral de alerta: $threshold)",
          [target("sum(increase(notes_created_total[5m]))", "creadas en 5m"), target("$threshold", "umbral")], 16, y, 8, 8, "short"),
]
y += 8

panels.append(row("Estado", y)); y += 1
panels += [
    panel("timeseries", "Targets de Prometheus (up)", [target("up", "{{job}} {{instance}}")], 0, y, 12, 6, "short", min=0, max=1),
    panel("timeseries", "Uptime del proceso por pod",
          [target('time() - process_start_time_seconds{job="notes-backend"}', "{{instance}}")], 12, y, 12, 6, "s"),
]

dashboard = {
    "uid": "notes-api",
    "title": "Notes: API, recursos y negocio",
    "description": "RPS, latencia, CPU/memoria por pod y metricas de negocio de la Notes API",
    "tags": ["notes", "fastapi", "devops"],
    "timezone": "browser",
    "editable": True,
    "graphTooltip": 1,
    "refresh": "10s",
    "time": {"from": "now-30m", "to": "now"},
    "schemaVersion": 39,
    "version": 1,
    "templating": {
        "list": [
            {
                "name": "endpoint",
                "label": "Endpoint",
                "type": "query",
                "datasource": DS,
                "query": {"query": "label_values(http_request_duration_seconds_count, endpoint)", "refId": "endpoint"},
                "definition": "label_values(http_request_duration_seconds_count, endpoint)",
                "refresh": 2,
                "includeAll": True,
                "multi": True,
                "allValue": ".*",
                "current": {"selected": True, "text": ["All"], "value": ["$__all"]},
                "sort": 1,
            },
            {
                "name": "threshold",
                "label": "Umbral de notas en 5 min",
                "type": "textbox",
                "query": "10",
                "current": {"selected": False, "text": "10", "value": "10"},
            },
        ]
    },
    "annotations": {"list": [{"builtIn": 1, "datasource": {"type": "grafana", "uid": "-- Grafana --"}, "enable": True, "hide": True, "iconColor": "rgba(0, 211, 255, 1)", "name": "Annotations & Alerts", "type": "dashboard"}]},
    "panels": panels,
}

for out in OUTPUTS:
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(dashboard, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"escrito {out.relative_to(ROOT)} ({len(panels)} paneles)")
