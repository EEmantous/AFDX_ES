"""Check independent source registration, provenance and generated artifacts."""
from pathlib import Path
import hashlib,json,re,xml.etree.ElementTree as ET
from run_regression import TESTS
ROOT=Path(__file__).resolve().parents[1]

def main():
    tree=ET.parse(ROOT/'AFDX_v3.xpr');errors=[];sets={x.get('Name'):x for x in tree.findall('./FileSets/FileSet')}
    rtl=list((ROOT/'AFDX_v3.srcs/sources_1/new').glob('*.v'));tb=list((ROOT/'AFDX_v3.srcs/sim_1/new').glob('*.v'))
    for name,paths in [('sources_1',rtl),('sim_1',tb)]:
        registered=[x.get('Path','').replace('\\','/') for x in sets[name].findall('File')]
        for p in paths:
            if not any(x.endswith('/'+p.name) for x in registered):errors.append('Not registered: '+str(p))
        expected={p.name for p in paths}
        extra=[x for x in registered if x.endswith('.v') and x.rsplit('/',1)[-1] not in expected]
        if extra:errors.append('Obsolete source registration: '+','.join(extra))
        if any('ADFX_V2' in x or '.xci' in x for x in registered):errors.append('External V2/vendor IP dependency')
    if any('tb_' in x.get('Path','') for x in sets['sources_1'].findall('File')):errors.append('Testbench incorrectly classified as design RTL')
    manifest=json.loads((ROOT/'docs/migration_manifest.json').read_text(encoding='utf-8'))
    for row in manifest['copied']:
        if hashlib.sha256(Path(row['source']).read_bytes()).hexdigest()!=row['sha256']:errors.append('V2 source changed: '+row['source'])
        target=Path(row['target'])
        if row.get('removed_from_v3'):
            if target.exists():errors.append('Removed source reintroduced: '+str(target))
            row['v3_sha256']=None;row['modified']=None
        else:
            row['v3_sha256']=hashlib.sha256(target.read_bytes()).hexdigest();row['modified']=row['v3_sha256']!=row['sha256']
    (ROOT/'docs/migration_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    regression=json.loads((ROOT/'artifacts/regression/latest.json').read_text(encoding='utf-8'))
    if not regression['passed'] or {r['test'] for r in regression['results']}!=set(TESTS) or len(regression['results'])!=len(TESTS):errors.append('Full V3 regression missing/failing')
    hashes=[dict(path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in sorted(rtl+tb)]
    compiled=dict(line.split('  ',1)[::-1] for line in (Path(regression['folder'])/'sources.sha256').read_text(encoding='utf-8').splitlines())
    for row in hashes:
        if compiled.get(row['path'])!=row['sha256']:errors.append('Regression source stale: '+row['path'])
    inventory=json.loads((ROOT/'docs/source_inventory.json').read_text(encoding='utf-8'))
    catalog={m['name']:m for m in inventory['modules'] if not m['name'].startswith('tb_')}
    reachable=set();pending=['AFDX_top']
    while pending:
        name=pending.pop()
        if name in reachable:continue
        reachable.add(name)
        pending.extend(i['module'] for i in catalog[name]['instances'])
    unused=sorted(set(catalog)-reachable)
    if unused:errors.append('RTL unused by AFDX_top: '+','.join(unused))
    for row in inventory['sources']:
        if hashlib.sha256(Path(row['path']).read_bytes()).hexdigest()!=row['sha256']:errors.append('Documentation stale: '+row['path'])
    xsim_log=ROOT/'artifacts/xsim_tb_afdx_end_system.log'
    xsim_passed=xsim_log.exists() and 'V3 END SYSTEM PASSED' in xsim_log.read_text(encoding='utf-8')
    if not xsim_passed:errors.append('V3 XSim self-check missing/failing')
    protection_log=ROOT/'artifacts/xsim_tb_afdx_rx_protection_stats.log'
    protection_passed=protection_log.exists() and 'RX PROTECTION STATS PASSED' in protection_log.read_text(encoding='utf-8')
    if not protection_passed:errors.append('RX protection XSim self-check missing/failing')
    latest_source_time=max(p.stat().st_mtime for p in rtl+tb)
    for log in [xsim_log,protection_log]:
        if log.exists() and log.stat().st_mtime<latest_source_time:errors.append('XSim evidence older than source: '+str(log))
    synth_log=ROOT/'artifacts/vivado_synth.log'
    synth_passed=bool(synth_log.exists() and re.search(r'^V3 SYNTHESIS PASSED\s*$',synth_log.read_text(encoding='utf-8',errors='replace'),re.M))
    for name in ['v3_utilization.rpt','v3_timing.rpt','v3_synth.dcp']:
        if not (ROOT/'artifacts'/name).exists():synth_passed=False
    if not synth_passed:errors.append('V3 synthesis evidence missing/failing')
    checkpoint=ROOT/'artifacts/v3_synth.dcp'
    if checkpoint.exists() and checkpoint.stat().st_mtime<max(p.stat().st_mtime for p in rtl):errors.append('Synthesis evidence older than RTL')
    summary=dict(date='2026-10-07',status='passed' if not errors else 'failed',rtl_files=len(rtl),testbench_files=len(tb),top='AFDX_top',unused_rtl=unused,regression=regression,xsim_passed=xsim_passed,protection_xsim_passed=protection_passed,synthesis_passed=synth_passed,documentation=inventory['summary'],source_hashes=hashes,errors=errors)
    (ROOT/'docs/verification.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(dict(status=summary['status'],rtl_files=len(rtl),tests=len(tb),errors=errors),ensure_ascii=False))
    return 0 if not errors else 1
if __name__=='__main__':raise SystemExit(main())
