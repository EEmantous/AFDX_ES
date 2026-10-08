"""Rebuild V3 local HDL variable/function/connection references from source."""
import hashlib,json,re
from pathlib import Path
import source_index as x
ROOT=x.ROOT

def cell(value):
    """Escape a value for one Markdown table cell."""
    return str(value).replace('|','\\|').replace('\n','<br>')

def link(path,line):
    """Return a clickable absolute source link at a verified declaration line."""
    return f'[{Path(path).name}:{line}]({Path(path).as_posix()}:{line})'

def role(owner,var,instances=()):
    """Resolve reviewed semantics, then child-port dependencies or local expressions."""
    name=var['name'];s=x.S
    if var['kind']=='function-result':return '函数隐式返回变量；给本函数名赋值形成返回值，见写入表达式。'
    if name in s['M'].get(owner,{}):return s['M'][owner][name]
    if var['kind']=='parameter':return s['PARAMETERS'].get(name,'编译期配置常量，默认表达式：'+var['initializer'])
    if name in s['PORTS']:return s['PORTS'][name]
    if owner.startswith('tb_') and name in s['TEST']:return s['TEST'][name]
    ends=[]
    for inst in instances:
        for port in inst['ports']:
            if re.search(r'\b'+re.escape(name)+r'\b',port['expression']):
                meaning=s['M'].get(inst['module'],{}).get(port['name'],s['PORTS'].get(port['name'],''))
                if meaning:ends.append(inst['name']+'.'+port['name']+'：'+meaning)
    if ends:return '连接 '+ '；'.join(dict.fromkeys(ends))
    if name in s['COMMON']:return s['COMMON'][name]
    if name.endswith(('_vl_id','_sequence_number')):return '随同前缀数据流全帧对齐的完整VLID/SN身份旁带，用于描述符和完整身份消重。'
    if name.endswith(('_data','_valid','_last','_ready')):return x.port_description(name)
    if var['kind']=='localparam':return '局部编译常量：'+var['initializer']+'；影响比较、寻址或状态编码，具体引用见源码。'
    raise ValueError('Missing semantic annotation: '+owner+'.'+name)

def variables_table(owner,variables,instances,path):
    """Render every declaration with role, exact assignments and source evidence."""
    out=['|变量|类型/位宽/数组|默认值|作用及传递原因|写入表达式|源码|','|---|---|---|---|---|---|']
    for v in variables:
        writes='；'.join(f"L{w['line']}: {w['expression']}" for w in v['writes']) or '输入/常量/实例驱动；见连接表'
        out.append('|'+ '|'.join(map(cell,[v['name'],f"{v['kind']} {v['type']} {v['width']} {v['array']}",v['initializer'],role(owner,v,instances),writes]))+'|'+link(path,v['line'])+'|')
    return out

def main():
    """Inventory active RTL and TB files; write Markdown and full JSON evidence."""
    paths=sorted((ROOT/'AFDX_v3.srcs/sources_1/new').glob('*.v'))+sorted((ROOT/'AFDX_v3.srcs/sim_1/new').glob('*.v'))
    catalog={};modules=[];functions=[]
    for p in paths:
        for m in x.extract_interfaces(p)[0]:catalog[(str(p.resolve()),m['name'])]=m
    for p in paths:
        m,f=x.extract_hdl(p,catalog);modules+=m;functions+=f
    index={m['name']:m for m in modules}
    guide=json.loads((ROOT/'docs/module_purpose.json').read_text(encoding='utf-8'))
    if set(guide)!=set(index):raise ValueError('Module purpose catalog does not match source modules')
    md=['# V3 模块、函数与变量明细','', '由 V3 本地源码生成。列出全部 RTL/testbench 声明、HDL function/task 的显式输入输出及隐式读写依赖；完整引用/条件和文件哈希见 source_inventory.json。词法提取不替代 HDL elaboration。valid/ready 模块并非软件顺序调用；组合连接与时钟状态机并行工作。','']
    rtl_count=sum(not m['name'].startswith('tb_') for m in modules)
    tb_count=len(modules)-rtl_count
    connections=['# V3 拓扑与逐端口连接','', f'本文件先解释每个模块做什么、为什么需要它、位于哪里，再列出真实源码的子模块参数与逐端口连接。覆盖 {rtl_count} 个主入口实际使用的 RTL 模块和 {tb_count} 个 testbench；未接入的四 VL 扩展已从 V3 删除，testbench 只用于仿真。','', '参数决定编译期配置；data/valid/last 沿数据方向传递，ready 反向反馈；上升沿 valid && ready 才推进一个字节。长度描述标识完整帧边界，VLID/SN 旁带维持帧身份，commit/abort 决定候选帧是否能交付。模块按时钟并行工作，箭头表示数据或控制连接。','', '## 主端系统拓扑','', '```mermaid', 'flowchart LR', '  APP_TX[APP TX 载荷] --> TX[afdx_es_tx 共享封装和SN]', '  TX --> FAN[afdx_redundant_tx_fanout]', '  FAN --> MAC_A[外部 MAC A]', '  FAN --> MAC_B[外部 MAC B]', '  MAC_A --> RX_A[afdx_es_rx A 入口保护和校验]', '  MAC_B --> RX_B[afdx_es_rx B 入口保护和校验]', '  RX_A --> MERGE[afdx_ab_frame_selector]', '  RX_B --> MERGE', '  MERGE --> APP_RX[APP RX 载荷及VLID/SN]', '  TX -. APP输入事件 .-> STATS[afdx_es_stats 内部计数]', '  FAN -. 发送完成和超长 .-> STATS', '  RX_A -. A路异常 .-> STATS', '  RX_B -. B路异常 .-> STATS', '  MERGE -. 副本丢弃 .-> STATS', '```','', '图中外部 MAC 不在当前综合顶层内。共享 TX 先产生一次完整核心帧再复制；两路 RX 各自先做有限完整帧捕获、超长/缺帧保护，再解析及提交，最后以完整 VLID/SN 合并交付。A/B仅共享全局reset，无独立开关或许可回显。接收选择最先完整通过检查并进入合并缓存的帧，同拍A优先；输出期间锁定整帧来源。发送每帧固定复制给A/B，两路ready分别推进，均完成才释放缓存。内部统计经 stats_addr/rdata/error 读出，stats_clear 同步清零，0x0C/0x10保留为零。','', '## 模块索引','', '|模块|主要功能|在项目中的位置|','|---|---|---|']
    for m in modules:
        g=guide[m['name']]
        connections.append('|'+ '|'.join(map(cell,[m['name'],g['function'],g['position']]))+'|')
    connections+=['']
    for m in modules:
        md += [f"## {m['name']}",'',m['description'], '',link(m['file'],m['line']),'']+variables_table(m['name'],m['variables'],m['instances'],m['file'])+['']
        g=guide[m['name']]
        connections += [f"## {m['name']}",'', '**主要功能：** '+g['function'],'','**为什么需要：** '+g['necessity'],'','**在项目中的位置：** '+g['position'],'','**连接与工作过程：** '+g['flow'],'',link(m['file'],m['line']),'']
        if not m['instances']:connections+=['本模块未例化 V3 子模块，内部状态/计算见变量明细。','']
        for inst in m['instances']:
            connections += [f"### {inst['name']} → {inst['module']}",'',link(m['file'],inst['line']),'','|子模块项|方向/种类|上层表达式|为何传递|','|---|---|---|---|']
            child=index[inst['module']]
            for port in inst['parameters']+inst['ports']:
                v=next((v for v in child['variables'] if v['name']==port['name']),None)
                reason=role(child['name'],v,child['instances']) if v else '位置连接，见对应模块声明'
                if not port['expression']:reason='显式悬空观察端口，不影响功能；'+reason
                connections.append('|'+ '|'.join(map(cell,[port['name'],v['kind'] if v else 'positional',port['expression'] or '(未连接)',reason]))+'|')
            connections+=['']
    for f in functions:
        owner=f['owner'];desc=x.S['LOCAL_FUNCTIONS'].get(owner+'.'+f['name'],f['description'])
        if not desc:raise ValueError('Missing function description '+owner+'.'+f['name'])
        inputs=', '.join(v['name'] for v in f['variables'] if v['kind'] in ('input','inout')) or '无显式输入'
        outputs=', '.join(v['name'] for v in f['variables'] if v['kind'] in ('output','inout')) or '无显式output/inout'
        md += [f"## {owner}.{f['name']} ({f['kind']})",'',desc,'',f"显式输入：{inputs}。显式输出：{outputs}。返回：{f['return_type']}。",'',link(f['file'],f['line']),'']+variables_table(owner,f['variables'],index[owner]['instances'],f['file'])+['']
        if f['implicit_variables']:
            md += ['### 隐式模块依赖','', '以下变量未作为参数传入，但该 callable 会读取或修改其模块作用域状态；重构时需要保留这些依赖。','']+variables_table(owner,f['implicit_variables'],index[owner]['instances'],f['file'])+['']
    sources=[dict(path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in paths]
    summary=dict(modules=len(modules),hdl_callables=len(functions),declarations=sum(len(m['variables']) for m in modules+functions),port_connections=sum(len(i['ports']) for m in modules for i in m['instances']))
    inventory=dict(summary=summary,modules=modules,callables=functions,sources=sources)
    for name,content in [('函数与变量明细.md',md),('拓扑与端口连接.md',connections)]:
        (ROOT/'docs'/name).write_text('\n'.join(content)+'\n',encoding='utf-8')
    (ROOT/'docs/source_inventory.json').write_text(json.dumps(inventory,ensure_ascii=False,indent=2),encoding='utf-8')
    # Relative paths make this file reusable by eLinx or another HDL tool.
    (ROOT/'tools/rtl_sources.f').write_text('\n'.join(p.relative_to(ROOT).as_posix() for p in paths if p.parent.name=='new' and 'sources_1' in p.parts)+'\n',encoding='utf-8')
    (ROOT/'tools/testbench_sources.f').write_text('\n'.join(p.relative_to(ROOT).as_posix() for p in paths if 'sim_1' in p.parts)+'\n',encoding='utf-8')
    print(json.dumps(summary))

if __name__=='__main__':main()
