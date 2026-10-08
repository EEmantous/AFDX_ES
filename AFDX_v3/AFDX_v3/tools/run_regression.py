"""Standalone V3 ModelSim runner: no V2, switch, HTTP or vendor IP dependency."""
import argparse,hashlib,json,os,re,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
RTL=ROOT/'AFDX_v3.srcs/sources_1/new'
TB=ROOT/'AFDX_v3.srcs/sim_1/new'
MODELSIM=Path(os.environ.get('AFDX_MODELSIM',r'C:\Develop\Modelsim\win64'))
TESTS={
 'tb_afdx_sync_fifo':'PORTABLE FIFO PASSED',
 'tb_afdx_core_controls':'CORE CONTROLS PASSED',
 'tb_afdx_sequence_table':'SEQUENCE TABLE PASSED',
 'tb_afdx_rx_protection_stats':'RX PROTECTION STATS PASSED',
 'tb_afdx_ab_selector':'AB SELECTOR PASSED',
 'tb_afdx_ab_delayed_copy':'AB DELAYED COPY PASSED',
 'tb_afdx_redundant_tx_fanout':'REDUNDANT TX FANOUT PASSED',
 'tb_afdx_app_to_switch':'ALL APP-TO-SWITCH TESTS PASSED',
 'tb_afdx_switch_to_app':'ALL SWITCH-TO-APP TESTS PASSED',
 'tb_afdx_end_system':'V3 END SYSTEM PASSED'}

def execute(argv,folder,log,timeout=300):
    result=subprocess.run(argv,cwd=folder,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=timeout,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    with log.open('a',encoding='utf-8') as stream:stream.write('> '+subprocess.list2cmdline(argv)+'\n'+result.stdout+result.stderr)
    return result

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--tests',nargs='+',choices=list(TESTS));args=parser.parse_args()
    folder=ROOT/'artifacts/regression'/time.strftime('%Y%m%d_%H%M%S');folder.mkdir(parents=True,exist_ok=False)
    sources=sorted(RTL.glob('*.v'))+sorted(TB.glob('*.v'))
    (folder/'sources.sha256').write_text('\n'.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+str(p) for p in sources),encoding='utf-8')
    results=[]
    try:
        commands=[['vmap','-c'],['vlib','work'],['vmap','work','work'],['vlog','-64','-sv','-work','work']+list(map(str,sources))]
        for command in commands:
            result=execute([str(MODELSIM/(command[0]+'.exe'))]+command[1:],folder,folder/'compile.log')
            if result.returncode:raise RuntimeError('V3 compile failed; see compile.log')
        for top in args.tests or TESTS:
            start=time.monotonic();log=folder/(top+'.log')
            result=execute([str(MODELSIM/'vsim.exe'),'-c','-64','work.'+top,'-do','onbreak {quit -code 1 -f}; onerror {quit -code 1 -f}; run -all; quit -code 0 -f'],folder,log,600)
            output=result.stdout+result.stderr
            passed=result.returncode==0 and TESTS[top] in output and not re.search(r'\b(ERROR|FATAL|TIMEOUT|FAILED)\b',output,re.I)
            results.append(dict(test=top,passed=passed,returncode=result.returncode,seconds=round(time.monotonic()-start,2),log=str(log)))
            print(top,'PASS' if passed else 'FAIL',flush=True)
    except Exception as exc:results.append(dict(test='platform',passed=False,error=str(exc)))
    summary=dict(project='AFDX V3 standalone ES',date='2026-10-07',simulator='ModelSim',passed=bool(results) and all(r['passed'] for r in results),folder=str(folder),results=results)
    (folder/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    (folder.parent/'latest.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    print('Report:',folder/'summary.json',flush=True)
    return 0 if summary['passed'] else 1
if __name__=='__main__':raise SystemExit(main())
