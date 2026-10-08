"""Local lexical HDL inventory. Source-backed evidence, not a Verilog elaborator.
Extraction helpers adapted from V2; no V2 runtime dependency.
"""
import json,re,hashlib
from pathlib import Path
from types import SimpleNamespace
ROOT=Path(__file__).resolve().parents[1]
S=json.loads((ROOT/'docs/source_semantics.json').read_text(encoding='utf-8'))
MODULES=S['MODULES'];PORTS=S['PORTS'];HDL=S['HDL']
def no_comments(text):
    return re.sub(r'/\*.*?\*/|//[^\n]*',lambda m:'\n'*m.group().count('\n'),text,flags=re.S)

def balanced(text,start):
    depth=0
    for i in range(start,len(text)):
        if text[i]=='(':depth+=1
        if text[i]==')':
            depth-=1
            if depth==0:return text[start+1:i],i+1
    raise ValueError('unbalanced header')

def declarations(text,splitter=','):
    result=[];direction=None;width='1';dtype='wire'
    for part in text.split(splitter):
        part=part.strip()
        m=re.match(r'(input|output|inout)\b\s*(.*)',part,flags=re.S)
        if m:
            direction=m[1];part=m[2];width='1';dtype='wire'
            typ=re.match(r'(wire|reg|integer)\b\s*',part)
            if typ:dtype=typ[1];part=part[typ.end():]
            w=re.match(r'(\[[^]]+\])\s*',part)
            if w:width=w[1];part=part[w.end():]
            elif dtype=='integer':width='32 (signed integer)'
        if direction:
            name=part.strip().split('=')[0].strip()
            if re.fullmatch(r'\w+',name):result.append(dict(name=name,direction=direction,width=width,type=dtype))
    return result

def port_description(name):
    if name in PORTS:return PORTS[name]
    if name.startswith('debug_'):return 'A平面真实层次信号观察：'+port_description(name.removeprefix('debug_').replace('es_tx_','tx_').replace('sw1_out_','out_').replace('sw2_out_','out_'))
    if name.startswith(('a_','b_')):return ('A' if name.startswith('a_') else 'B')+'平面副本输入/反馈：'+port_description(name[2:] if name[2:] in PORTS else 'in_'+name[2:])
    prefix,suffix=name.rsplit('_',1) if '_' in name else ('',name)
    semantic={'data':'8位字节/打包流数据，只在valid时有意义。','valid':'流数据有效指示。','last':'该流当前帧末字节指示。','ready':'该流下游可接收，与valid共同决定上升沿握手。'}
    if suffix in semantic:return prefix+'接口：'+semantic[suffix]
    raise ValueError('Missing port description: '+name)

def extract_interfaces(path,vendor=False):
    raw=path.read_text(encoding='utf-8',errors='replace');text=no_comments(raw)
    modules=[];functions=[]
    for m in re.finditer(r'\bmodule\s+(\w+)\b(.*?)\bendmodule',text,flags=re.S):
        name=m[1];tail=m[2];i=0;params=''
        pm=re.match(r'\s*#\s*\(',tail)
        if pm:params,i=balanced(tail,pm.end()-1)
        remainder=tail[i:].lstrip()
        begin=tail.find('(',i) if remainder.startswith('(') else -1
        ports=[]
        if begin>=0:
            header,_=balanced(tail,begin)
            ports=declarations(header)
            if not ports:
                # Non-ANSI vendor wrapper declares ports after the header.
                for d in re.finditer(r'\b(?:input|output|inout)\b[^;]*;',tail):ports+=declarations(d.group()[:-1])
        if not vendor or name=='fifo_tx':
            param_rows=[]
            for p in re.finditer(r'\bparameter\s+(?:(integer|\[[^]]+\])\s+)?(\w+)\s*=\s*([^,]+)',params):
                param_rows.append(dict(name=p[2],type=p[1] or 'implicit',default=' '.join(p[3].split())))
            description=MODULES.get(name)
            if name=='tb_network' and path.name=='network_simulation.py':description='Python动态生成固定路线XSim测试：六源并发注入、默认路线核心字节/SN与APP载荷比较、20点计数、反压保持和超时；不提供动态交换机CSR改路由。'
            modules.append(dict(name=name,file=str(path.resolve()),line=text[:m.start()].count('\n')+1,description=description,parameters=param_rows,ports=ports))
    for m in re.finditer(r'\b(function|task)\s+([^;]+);(.*?)\bend(?:function|task)\b',text,flags=re.S):
        spec=m[2].strip()
        header_start=spec.find('(')
        prefix=spec[:header_start].strip() if header_start>=0 else spec
        name=prefix.split()[-1]
        if not re.fullmatch(r'\w+',name):continue
        args=declarations(spec[header_start+1:spec.rfind(')')]) if header_start>=0 else []
        for d in re.finditer(r'\b(?:input|output|inout)\b[^;]*;',m[3]):args+=declarations(d.group()[:-1])
        result_type=prefix.removesuffix(name).replace('automatic','').strip() or ('implicit 1 bit' if m[1]=='function' else 'no return')
        functions.append(dict(name=name,kind=m[1],file=str(path.resolve()),line=text[:m.start()].count('\n')+1,return_type=result_type,args=args,description=HDL.get(name),vendor=vendor))
    return modules,functions


base=SimpleNamespace(no_comments=no_comments,balanced=balanced,declarations=declarations,HDL=HDL)

def split_top(text,sep=','):
    """Separate only outside nested expressions; Verilog literal apostrophes are not quotes."""
    result=[];start=0;depth=0;quote=False
    for i,c in enumerate(text):
        if c=='"' and (i==0 or text[i-1]!='\\'):quote=not quote
        if quote:continue
        if c in '([{':depth+=1
        elif c in ')]}':depth-=1
        elif c==sep and depth==0:result.append(text[start:i].strip());start=i+1
    result.append(text[start:].strip())
    return result
def callable_spans(text):
    result=[]
    for m in re.finditer(r'\b(function|task)\s+([^;]+);(.*?)\bend(?:function|task)\b',text,re.S):
        spec=m[2].strip();ix=spec.find('(');prefix=spec[:ix].strip() if ix>=0 else spec
        name=prefix.split()[-1]
        if re.fullmatch(r'\w+',name):result.append(dict(name=name,kind=m[1],start=m.start(),end=m.end(),spec=spec,body=m[3],body_start=m.start(3)))
    return result

def decls(text,offset=0):
    rows=[]
    pattern=r'\b(input|output|inout|wire|reg|integer|genvar|parameter|localparam|real|time|event)\b\s*([^;]+);'
    for m in re.finditer(pattern,text,re.S):
        kind=m[1];tail=m[2].strip();dtype=kind;width='1'
        t=re.match(r'(wire|reg|integer|real|time|signed|unsigned)\b\s*',tail)
        if t:dtype=t[1];tail=tail[t.end():]
        if kind in ('integer','genvar') or dtype=='integer':width='32 signed'
        if kind in ('real','time'):width=kind
        if kind in ('parameter','localparam') and dtype not in ('integer','real','time'):width='由常量表达式推导（无显式位宽）'
        w=re.match(r'(\[[^]]+\])\s*',tail)
        if w:width=w[1];tail=tail[w.end():]
        for part in split_top(tail):
            n=re.match(r'(\w+)\s*((?:\[[^]]+\]\s*)*)(?:=\s*(.*))?$',part,re.S)
            if not n:continue
            rows.append(dict(name=n[1],kind=kind,type=dtype,width=width,array=n[2].strip(),initializer=(n[3] or '').strip(),offset=offset+m.start()))
    return rows

def usage(text,name,start_line):
    reads=[];writes=[];conditions=[]
    lines=text.splitlines()
    rx=re.compile(r'\b'+re.escape(name)+r'\b')
    lhs=re.compile(r'\b'+re.escape(name)+r'(?:\s*\[[^]]+\])*\s*(?:<=|=(?!=))\s*([^;]+);',re.S)
    for m in lhs.finditer(text):
        prefix=text[:m.start()];operator=text[m.start():m.start(1)]
        plain=re.sub(r'"(?:\\.|[^"\\])*"','""',prefix)
        if '<=' in operator and plain.count('(')>plain.count(')'):continue # relational comparison inside a condition
        statement=re.split(r';|\bbegin\b|\bend\b',plain)[-1]
        if re.search(r'(?<![<>=!])=(?!=)',statement) and 'for' not in statement:continue # same name occurring inside another RHS
        expression=m[1];depth=0;end=len(expression)
        for idx,char in enumerate(expression):
            if char in '([{':depth+=1
            elif char in ')]}':
                if depth==0:end=idx;break # end of a for-update expression
                depth-=1
        writes.append(dict(line=start_line+text[:m.start()].count('\n'),expression=' '.join(expression[:end].split())))
    for i,line in enumerate(lines):
        if rx.search(line):
            reads.append(dict(line=start_line+i,text=line.strip()))
            if re.search(r'\b(if|case|while|for)\s*\(',line):conditions.append(dict(line=start_line+i,text=line.strip()))
    return dict(uses=reads,writes=writes,conditions=conditions)

def instances(body,names,start_line):
    found=[]
    for m in re.finditer(r'\b('+'|'.join(sorted(names,key=len,reverse=True))+r')\b\s*',body):
        pos=m.end();params=[]
        if pos<len(body) and body[pos]=='#':
            pm=re.match(r'#\s*\(',body[pos:])
            if not pm:continue
            content,end=base.balanced(body,pos+pm.end()-1);pos=end
            for item in split_top(content):
                x=re.match(r'\.(\w+)\s*\((.*)\)\s*$',item,re.S)
                if x:params.append(dict(name=x[1],expression=' '.join(x[2].split())))
        im=re.match(r'\s*(\w+)\s*\(',body[pos:])
        if not im:continue
        content,end=base.balanced(body,pos+im.end()-1)
        if not re.match(r'\s*;',body[end:]):continue
        ports=[]
        for idx,item in enumerate(split_top(content)):
            x=re.match(r'\.(\w+)\s*\((.*)\)\s*$',item,re.S)
            ports.append(dict(name=x[1] if x else str(idx),expression=' '.join((x[2] if x else item).split()),positional=not bool(x)))
        found.append(dict(module=m[1],name=im[1],line=start_line+body[:m.start()].count('\n'),parameters=params,ports=ports))
    return found

def extract_hdl(path,module_catalog):
    raw=path.read_text(encoding='utf-8',errors='replace');text=base.no_comments(raw);result=[];funcs=[]
    for m in re.finditer(r'\bmodule\s+(\w+)\b(.*?)\bendmodule',text,re.S):
        name=m[1];tail=m[2];i=0
        pm=re.match(r'\s*#\s*\(',tail)
        if pm:_,i=base.balanced(tail,pm.end()-1)
        header_start=tail.find('(',i)
        if header_start>=0 and tail[i:].lstrip().startswith('('):_,body_start=base.balanced(tail,header_start)
        else:body_start=i
        body=tail[body_start:];start_line=text[:m.start(2)+body_start].count('\n')+1
        scope_body=body
        for f in reversed(callable_spans(body)):scope_body=scope_body[:f['start']]+re.sub(r'[^\n]',' ',scope_body[f['start']:f['end']])+scope_body[f['end']:]
        meta=module_catalog.get((str(path.resolve()),name))
        rows=[]
        if not meta:
            for pm in re.finditer(r'\bparameter\s+(?:(integer|\[[^]]+\])\s+)?(\w+)\s*=\s*([^,\n]+)',tail[:body_start]):
                rows.append(dict(name=pm[2],kind='parameter',type=pm[1] or 'implicit',width=pm[1] or 'implicit',array='',initializer=pm[3].strip(),line=text[:m.start(2)+pm.start()].count('\n')+1))
        if meta:
            for p in meta['ports']:
                hit=re.search(r'\b'+re.escape(p['name'])+r'\b',tail[:body_start])
                line=text[:m.start(2)+(hit.start() if hit else 0)].count('\n')+1
                rows.append(dict(p,kind=p['direction'],array='',initializer='',line=line))
            for p in meta['parameters']:
                hit=re.search(r'\b'+re.escape(p['name'])+r'\b',tail[:body_start])
                line=text[:m.start(2)+(hit.start() if hit else 0)].count('\n')+1
                rows.append(dict(p,kind='parameter',width=p['type'],array='',initializer=p['default'],line=line))
        for d in decls(scope_body):
            d['line']=start_line+scope_body[:d.pop('offset')].count('\n')
            previous=next((x for x in rows if x['name']==d['name']),None)
            if previous and d['kind'] in ('input','output','inout'):
                previous.update(d)
            else:rows.append(d)
        for d in rows:d.update(usage(scope_body,d['name'],start_line))
        if meta:result.append(dict(name=name,file=str(path.resolve()),line=meta['line'],body_line=start_line,description=meta['description'],variables=rows,instances=instances(scope_body,{x[1] for x in module_catalog},start_line),body=scope_body))
        for f in callable_spans(body):
            variables=[];ix=f['spec'].find('(')
            if ix>=0:
                for p in base.declarations(f['spec'][ix+1:f['spec'].rfind(')')]):variables.append(dict(p,kind=p['direction'],array='',initializer='',line=start_line+body[:f['start']].count('\n')))
            for d in decls(f['body']):d['line']=start_line+body[:f['body_start']+d.pop('offset')].count('\n');variables.append(d)
            for d in variables:d.update(usage(f['body'],d['name'],start_line+body[:f['body_start']].count('\n')))
            fline=start_line+body[:f['start']].count('\n')
            result_type=f['spec'].split('(')[0].removesuffix(f['name']).replace('automatic','').strip() or 'implicit 1 bit'
            if f['kind']=='function':
                r=dict(name=f['name'],kind='function-result',type=result_type,width=result_type,array='',initializer='',line=fline)
                r.update(usage(f['body'],f['name'],start_line+body[:f['body_start']].count('\n')));variables.append(r)
            implicit=[]
            for d in rows:
                if d['name'] not in {x['name'] for x in variables} and re.search(r'\b'+re.escape(d['name'])+r'\b',f['body']):
                    copied=dict(d);copied.update(usage(f['body'],d['name'],start_line+body[:f['body_start']].count('\n')));implicit.append(copied)
            funcs.append(dict(name=f['name'],owner=name,kind=f['kind'],file=str(path.resolve()),line=fline,body_line=start_line+body[:f['body_start']].count('\n'),return_type=result_type if f['kind']=='function' else 'void',variables=variables,implicit_variables=implicit,body=f['body'],description=base.HDL.get(f['name'],'')))
    return result,funcs


