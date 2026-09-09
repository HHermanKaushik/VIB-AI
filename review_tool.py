#!/usr/bin/env python3
"""Small local review UI for migration_output/organizations.jsonl."""
from __future__ import annotations

import argparse
import csv
import json
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

TYPES = [
    "eye_bank", "school", "hospital", "ngo", "government",
    "vocational_training", "rehabilitation_centre", "hostel",
    "association", "resource_centre", "other",
]
SERVICES = [
    "eye_bank", "eye_care", "healthcare", "education", "vocational_training",
    "rehabilitation", "employment", "financial_support", "assistive_technology",
    "hostel", "advocacy_or_government", "library_or_information",
]


def load_source(path: Path) -> dict[int, dict[str, str]]:
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    header = next((i for i, line in enumerate(lines) if "Name of Institution" in line), None)
    if header is None:
        raise ValueError("Could not find CSV header")
    return {
        number: row
        for number, row in enumerate(csv.DictReader(lines[header:]), start=header + 2)
    }


def read_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write_jsonl(path: Path, records: list[dict]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text("".join(json.dumps(record, ensure_ascii=False) + "\n" for record in records), encoding="utf-8")
    temporary.replace(path)


def source_fields(record: dict, source: dict[int, dict[str, str]]) -> dict[str, str]:
    return source.get(record.get("provenance", {}).get("sourceRow", -1), {})


def checkbox_group(name: str, values: list[str], selected: list[str]) -> str:
    return "".join(
        f'<label><input type="checkbox" name="{name}" value="{value}" '
        f'{"checked" if value in selected else ""}>{value}</label>'
        for value in values
    )


PAGE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>VIB migration review</title>
<style>
:root { font: 15px/1.4 system-ui,sans-serif; color:#17212b; background:#eef2f5 }
body { margin:0 } header { background:#17324d; color:white; padding:14px 22px; display:flex; justify-content:space-between; gap:12px; align-items:center }
main { max-width:1400px; margin:auto; padding:18px } button, input, textarea { font:inherit } button { cursor:pointer; border:0; border-radius:4px; padding:9px 13px; background:#176b87; color:white } button.secondary { background:#607080 } button.reject { background:#9d3b3b }
.layout { display:grid; grid-template-columns: minmax(280px, .8fr) minmax(420px, 1.2fr); gap:16px } section { background:white; border:1px solid #d5dde3; border-radius:6px; padding:16px; box-shadow:0 1px 2px #0001 }
h1,h2 { margin:0 0 8px } h1 { font-size:1.2rem } h2 { font-size:1rem; color:#31546d } .meta { color:#607080; font-size:.88rem } .reasons { display:flex; flex-wrap:wrap; gap:5px; margin:10px 0 } .reason { background:#fff0d5; border:1px solid #e7c47e; padding:3px 6px; border-radius:3px; font-size:.82rem }
dl { display:grid; grid-template-columns:145px 1fr; gap:7px 10px; margin:0 } dt { color:#607080; font-weight:600 } dd { margin:0; white-space:pre-wrap; overflow-wrap:anywhere }
.toolbar { display:flex; flex-wrap:wrap; align-items:center; gap:8px; margin-bottom:14px } .toolbar .count { margin-right:auto; font-weight:600 } .fields { display:grid; grid-template-columns:1fr 1fr; gap:10px } .field { display:flex; flex-direction:column; gap:3px } .field.full { grid-column:1/-1 } label { font-size:.84rem; color:#526575 } input[type=text], textarea { width:100%; box-sizing:border-box; border:1px solid #bbc7d0; border-radius:4px; padding:7px } textarea { min-height:60px; resize:vertical } .checks { display:flex; flex-wrap:wrap; gap:5px 12px; border:1px solid #d5dde3; padding:8px; border-radius:4px } .checks label { color:#17212b } .savebar { display:flex; gap:8px; margin-top:15px; border-top:1px solid #dde4e9; padding-top:14px } .empty { text-align:center; padding:50px 10px; color:#607080 }
@media (max-width:800px) { .layout { grid-template-columns:1fr } .fields { grid-template-columns:1fr } }
</style></head><body>
<header><h1>J.S. Trust VIB migration review</h1><div id="headerCount"></div></header>
<main><div class="toolbar"><span class="count" id="count"></span><button class="secondary" onclick="move(-1)">Previous</button><button onclick="move(1)">Next</button></div>
<div id="app" class="layout"></div></main>
<script>
let records=[], index=0;
const TYPE_OPTIONS = ["eye_bank","school","hospital","ngo","government","vocational_training","rehabilitation_centre","hostel","association","resource_centre","other"];
const SERVICE_OPTIONS = ["eye_bank","eye_care","healthcare","education","vocational_training","rehabilitation","employment","financial_support","assistive_technology","hostel","advocacy_or_government","library_or_information"];
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const val = (obj, path) => path.split('.').reduce((x,k) => x?.[k], obj) ?? '';
async function load() { const response=await fetch('/api/records'); records=await response.json(); index=Math.min(index,Math.max(0,records.length-1)); render(); }
function checks(name, values, selected) { return values.map(value => `<label><input type="checkbox" name="${name}" value="${value}" ${selected.includes(value)?'checked':''}> ${value}</label>`).join(''); }
function render() {
  document.querySelector('#count').textContent=records.length ? `Record ${index+1} of ${records.length}` : 'No needs-review records remaining';
  document.querySelector('#headerCount').textContent=`${records.length} open`;
  if (!records.length) { document.querySelector('#app').innerHTML='<section class="empty">All currently loaded records have been reviewed.</section>'; return; }
  const r=records[index], raw=r.rawSource||{};
  document.querySelector('#app').innerHTML=`
  <section><h2>Raw source fields</h2><p class="meta">CSV row ${esc(r.provenance?.sourceRow)} · ${esc(r.organization?.name)}</p>
  <dl>${Object.entries(raw).map(([key,value])=>`<dt>${esc(key)}</dt><dd>${esc(value)}</dd>`).join('')}</dl>
  <h2 style="margin-top:18px">Review reasons</h2><div class="reasons">${(r.review?.reasons||[]).map(x=>`<span class="reason">${esc(x)}</span>`).join('')||'<span>none</span>'}</div>
  </section>
  <section><h2>Normalized fields</h2><form id="form">
    <div class="fields">
      ${field('Organization name','organization.name',r.organization?.name)}
      ${field('Raw type (reference)','organization.rawType',r.organization?.rawType)}
      ${field('Address','location.address',r.location?.address,'full')}
      ${field('City / district','location.city',r.location?.city)}${field('State','location.state',r.location?.state)}
      ${field('Postal code','location.postalCode',r.location?.postalCode)}${field('Website URL','contact.websiteUrl',r.contact?.websiteUrl)}
      ${field('Phones (one per line)','contact.phones',(r.contact?.phones||[]).join('\n'),'full','textarea')}
      ${field('Alternate phones (one per line)','contact.alternatePhones',(r.contact?.alternatePhones||[]).join('\n'),'full','textarea')}
      ${field('Emails (one per line)','contact.emails',(r.contact?.emails||[]).join('\n'),'full','textarea')}
      ${field('Services description','services.rawDescription',r.services?.rawDescription,'full','textarea')}
    </div>
    <h2>Organization types</h2><div class="checks">${checks('types',TYPE_OPTIONS,r.organization?.types||[])}</div>
    <h2>Service codes</h2><div class="checks">${checks('services',SERVICE_OPTIONS,r.services?.codes||[])}</div>
    <div class="savebar"><button type="button" onclick="save('verified')">Save as verified</button><button type="button" class="reject" onclick="save('rejected')">Save as rejected</button></div>
  </form></section>`;
}
function field(label,path,value,extra='',kind='input') { const control=kind==='textarea'?`<textarea data-path="${path}">${esc(value)}</textarea>`:`<input type="text" data-path="${path}" value="${esc(value)}">`; return `<div class="field ${extra}"><label>${label}</label>${control}</div>`; }
function move(delta) { if (records.length) { index=(index+delta+records.length)%records.length; render(); } }
async function save(status) {
  const r=records[index], form=document.querySelector('#form');
  form.querySelectorAll('[data-path]').forEach(control => { const [group,key]=control.dataset.path.split('.'); r[group][key]=control.value; });
  r.contact.phones=form.querySelector('[data-path="contact.phones"]').value.split('\n').map(x=>x.trim()).filter(Boolean);
  r.contact.alternatePhones=form.querySelector('[data-path="contact.alternatePhones"]').value.split('\n').map(x=>x.trim()).filter(Boolean);
  r.contact.emails=form.querySelector('[data-path="contact.emails"]').value.split('\n').map(x=>x.trim()).filter(Boolean);
  r.organization.types=[...form.querySelectorAll('input[name="types"]:checked')].map(x=>x.value);
  r.services.codes=[...form.querySelectorAll('input[name="services"]:checked')].map(x=>x.value);
  r.review.status=status; r.review.reviewedAt=new Date().toISOString();
  const response=await fetch('/api/review',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(r)});
  if (!response.ok) { alert(await response.text()); return; }
  records.splice(index,1); if(index>=records.length) index=Math.max(0,records.length-1); render();
}
function keydown(event) { if (event.key==='ArrowRight') move(1); if (event.key==='ArrowLeft') move(-1); }
document.addEventListener('keydown',keydown); load();
</script></body></html>"""


class ReviewHandler(BaseHTTPRequestHandler):
    records: list[dict] = []
    reviewed_path: Path
    source: dict[int, dict[str, str]]
    lock = threading.Lock()

    def send_json(self, value: object, status: int = 200) -> None:
        payload = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/":
            payload = PAGE.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        elif path == "/api/records":
            self.send_json(self.records)
        else:
            self.send_error(404)

    def do_POST(self) -> None:
        if urlparse(self.path).path != "/api/review":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            record = json.loads(self.rfile.read(length))
            self.validate(record)
            with self.lock:
                reviewed = read_jsonl(self.reviewed_path)
                reviewed = [item for item in reviewed if item.get("id") != record.get("id")]
                reviewed.append(record)
                write_jsonl(self.reviewed_path, reviewed)
                type(self).records = [item for item in type(self).records
                                      if item.get("id") != record.get("id")]
            self.send_json({"ok": True})
        except (ValueError, KeyError, json.JSONDecodeError) as error:
            self.send_json({"error": str(error)}, 400)

    @staticmethod
    def validate(record: dict) -> None:
        if not isinstance(record, dict) or not record.get("id"):
            raise ValueError("record id is required")
        if record.get("review", {}).get("status") not in {"verified", "rejected"}:
            raise ValueError("review status must be verified or rejected")
        organization = record.get("organization", {})
        services = record.get("services", {})
        if any(value not in TYPES for value in organization.get("types", [])):
            raise ValueError("invalid organization type")
        if any(value not in SERVICES for value in services.get("codes", [])):
            raise ValueError("invalid service code")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=Path("migration_output/organizations.jsonl"))
    parser.add_argument("--source", type=Path, default=Path("blind-schools-eye-banks-ngos-and-other-resources-for-visually-impaired-in-india.csv"))
    parser.add_argument("--reviewed", type=Path, default=Path("migration_output/organizations_reviewed.jsonl"))
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    reviewed_ids = {record.get("id") for record in read_jsonl(args.reviewed)}
    records = [record for record in read_jsonl(args.input)
               if record.get("review", {}).get("status") == "needs_review" and record.get("id") not in reviewed_ids]
    for record in records:
        record["rawSource"] = source_fields(record, load_source(args.source))
    ReviewHandler.records = records
    ReviewHandler.reviewed_path = args.reviewed
    ReviewHandler.source = load_source(args.source)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), ReviewHandler)
    print(f"Review tool: http://127.0.0.1:{args.port}/")
    print(f"Open records: {len(records)}; reviewed output: {args.reviewed}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()