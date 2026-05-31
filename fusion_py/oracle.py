#!/usr/bin/env python3
"""Verification oracle: a faithful port of fusion.rb's logic to test the algorithm.
Same lexer/parser/evaluator structure so passing tests here validate the Ruby design."""

import sys, json, os

class Error:  # the ! value
    _inst = None
    def __new__(cls):
        if cls._inst is None: cls._inst = super().__new__(cls)
        return cls._inst
    def __repr__(self): return "!"
ERROR = Error()
NULL = ("__null__",)  # sentinel distinct from python None

# ---------------- Lexer ----------------
class Tok:
    def __init__(self, t, v, p): self.type=t; self.value=v; self.pos=p
    def __repr__(self): return f"{self.type}:{self.value!r}"

PUNCT = {"(":"lparen",")":"rparen","[":"lbracket","]":"rbracket","{":"lbrace","}":"rbrace",
         ",":"comma",":":"colon","|":"pipe","?":"question",".":"dot","@":"at","/":"slash"}

def lex(src):
    i=0; n=len(src); out=[]
    def peek(o=0): return src[i+o] if i+o<n else None
    while True:
        # skip trivia
        while i<n:
            c=src[i]
            if c in " \t\n\r": i+=1
            elif c=="/" and i+1<n and src[i+1]=="/":
                i+=2
                while i<n and src[i]!="\n": i+=1
            elif c=="/" and i+1<n and src[i+1]=="*":
                i+=2
                while i<n and not (src[i]=="*" and i+1<n and src[i+1]=="/"): i+=1
                i+=2
            else: break
        if i>=n: out.append(Tok("eof",None,i)); break
        start=i; c=src[i]
        if c=="=" and i+1<n and src[i+1]==">": i+=2; out.append(Tok("arrow","=>",start)); continue
        if c=="." and src[i:i+3]=="...": i+=3; out.append(Tok("spread","...",start)); continue
        if c=="!": i+=1; out.append(Tok("bang","!",start)); continue
        if c=='"':
            i+=1; buf=[]
            while i<n and src[i]!='"':
                if src[i]=="\\":
                    i+=1; e=src[i]
                    buf.append({'"':'"',"\\":"\\","/":"/","n":"\n","t":"\t","r":"\r","b":"\b","f":"\f"}.get(e,e))
                    i+=1
                else: buf.append(src[i]); i+=1
            i+=1; out.append(Tok("string","".join(buf),start)); continue
        if c.isdigit() or (c=="-" and i+1<n and src[i+1].isdigit()):
            j=i
            if src[j]=="-": j+=1
            while j<n and src[j].isdigit(): j+=1
            isf=False
            if j<n and src[j]=="." and j+1<n and src[j+1].isdigit():
                isf=True; j+=1
                while j<n and src[j].isdigit(): j+=1
            if j<n and src[j] in "eE":
                isf=True; j+=1
                if j<n and src[j] in "+-": j+=1
                while j<n and src[j].isdigit(): j+=1
            text=src[i:j]; i=j
            out.append(Tok("number", float(text) if isf else int(text), start)); continue
        if c.isalpha() or c=="_":
            j=i
            while j<n and (src[j].isalnum() or src[j]=="_"): j+=1
            text=src[i:j]; i=j
            if text=="true": out.append(Tok("true_kw",True,start))
            elif text=="false": out.append(Tok("false_kw",False,start))
            elif text=="null": out.append(Tok("null_kw",NULL,start))
            else: out.append(Tok("ident",text,start))
            continue
        if c in PUNCT: i+=1; out.append(Tok(PUNCT[c],c,start)); continue
        raise SyntaxError(f"Unexpected {c!r} at {start}")
    return out

# ---------------- AST ----------------
class Node:
    def __init__(self,**kw): self.__dict__.update(kw); self.kind=type(self).__name__
class Lit(Node): pass
class ArrLit(Node): pass
class ObjLit(Node): pass
class FuncLit(Node): pass
class Ident(Node): pass
class FileRef(Node): pass
class Pipe(Node): pass
class Member(Node): pass
class Index(Node): pass
class PLit(Node): pass
class PBind(Node): pass
class PWild(Node): pass
class PArr(Node): pass
class PObj(Node): pass
class PGuard(Node): pass

# ---------------- Parser ----------------
class Parser:
    def __init__(self, toks): self.toks=toks; self.i=0
    def peek(self,o=0): return self.toks[self.i+o]
    def at(self,t): return self.peek().type==t
    def adv(self): t=self.toks[self.i]; self.i+=1; return t
    def expect(self,t):
        tok=self.peek()
        if tok.type!=t: raise SyntaxError(f"Expected {t} got {tok.type} at {tok.pos}")
        return self.adv()
    @staticmethod
    def parse_file(src):
        p=Parser(lex(src)); e=p.expr(); p.expect("eof"); return e
    def expr(self): return self.pipe()
    def pipe(self):
        left=self.postfix()
        while self.at("pipe"):
            self.adv(); left=Pipe(left=left,right=self.postfix())
        return left
    def postfix(self):
        node=self.primary()
        while True:
            if self.at("dot"):
                self.adv(); node=Member(obj=node,key=self.expect("ident").value)
            elif self.at("lbracket"):
                self.adv(); idx=self.expr(); self.expect("rbracket"); node=Index(obj=node,idx=idx)
            else: break
        return node
    def primary(self):
        t=self.peek()
        if t.type in ("number","string"): self.adv(); return Lit(value=t.value)
        if t.type in ("true_kw","false_kw","null_kw"): self.adv(); return Lit(value=t.value)
        if t.type=="bang": self.adv(); return Lit(value=ERROR)
        if t.type=="lbracket": return self.array()
        if t.type=="lbrace": return self.obj()
        if t.type=="lparen": return self.func_or_group()
        if t.type=="ident": self.adv(); return Ident(name=t.value)
        if t.type=="at": return self.fileref()
        raise SyntaxError(f"Unexpected {t.type} at {t.pos}")
    def fileref(self):
        self.expect("at")
        nxt = self.peek().type
        starts_path = (nxt == "ident") or (nxt == "dot" and self.peek(1).type == "dot")
        if not starts_path:
            return FileRef(kind2="self", path=None, segments=None)
        parts=[]; has_dotdot=False
        while self.at("dot") and self.peek(1).type=="dot":
            self.adv(); self.adv(); parts.append(".."); self.expect("slash"); has_dotdot=True
        parts.append(self.expect("ident").value)
        while self.at("slash"):
            self.adv(); parts.append(self.expect("ident").value)
        # A reference is eligible for builtin/stdlib fallback ("name") iff it does
        # NOT contain "../". Downward paths like "dir/a" are still eligible; only
        # "../" (escaping upward) forces pure file-path resolution.
        bare_name = (not has_dotdot)
        return FileRef(kind2="name" if bare_name else "path",
                       path="/".join(parts), segments=parts)
    def array(self):
        self.expect("lbracket"); elems=[]
        while not self.at("rbracket"):
            if self.at("spread"): self.adv(); elems.append(("spread",self.expr()))
            else: elems.append(("item",self.expr()))
            if not self.at("comma"): break
            self.adv()
        self.expect("rbracket"); return ArrLit(elems=elems)
    def obj(self):
        self.expect("lbrace"); members=[]
        while not self.at("rbrace"):
            if self.at("spread"): self.adv(); members.append(("spread",self.expr()))
            else:
                k=self.expect("string").value; self.expect("colon"); members.append(("kv",k,self.expr()))
            if not self.at("comma"): break
            self.adv()
        self.expect("rbrace"); return ObjLit(members=members)
    def looks_like_function(self):
        depth=0; j=self.i
        while j<len(self.toks):
            t=self.toks[j].type
            if t in ("lparen","lbracket","lbrace"): depth+=1
            elif t in ("rparen","rbracket","rbrace"):
                if depth==0: return False
                depth-=1
            elif t=="arrow":
                if depth==0: return True
            elif t=="eof": return False
            j+=1
        return False
    def func_or_group(self):
        self.expect("lparen")
        if self.looks_like_function():
            clauses=[]
            while True:
                pat=self.pattern(); self.expect("arrow"); body=self.expr()
                clauses.append((pat,body))
                if self.at("comma"):
                    self.adv()
                    if self.at("rparen"): break
                else: break
            self.expect("rparen"); return FuncLit(clauses=clauses)
        else:
            e=self.expr(); self.expect("rparen"); return e
    def pattern(self):
        inner=self.corepat()
        if self.at("question"):
            self.adv(); pred=self.postfix(); return PGuard(inner=inner,pred=pred)
        return inner
    def corepat(self):
        t=self.peek()
        if t.type in ("number","string"): self.adv(); return PLit(value=t.value)
        if t.type in ("true_kw","false_kw","null_kw"): self.adv(); return PLit(value=t.value)
        if t.type=="bang": self.adv(); return PLit(value=ERROR)
        if t.type=="lbracket": return self.arraypat()
        if t.type=="lbrace": return self.objectpat()
        if t.type=="ident":
            self.adv(); return PWild() if t.value=="_" else PBind(name=t.value)
        raise SyntaxError(f"Unexpected pattern tok {t.type} at {t.pos}")
    def arraypat(self):
        self.expect("lbracket"); elems=[]
        while not self.at("rbracket"):
            if self.at("spread"):
                self.adv(); name=self.adv().value if self.at("ident") else None; elems.append(("rest",name))
            else: elems.append(("pat",self.pattern()))
            if not self.at("comma"): break
            self.adv()
        self.expect("rbracket"); return PArr(elems=elems)
    def objectpat(self):
        self.expect("lbrace"); members=[]
        while not self.at("rbrace"):
            if self.at("spread"):
                self.adv(); name=self.adv().value if self.at("ident") else None; members.append(("rest",name))
            else:
                k=self.expect("string").value; self.expect("colon"); members.append(("kv",k,self.pattern()))
            if not self.at("comma"): break
            self.adv()
        self.expect("rbrace"); return PObj(members=members)

# ---------------- Runtime values ----------------
class Func:
    def __init__(self,clauses,env): self.clauses=clauses; self.env=env
class NativeFunc:
    def __init__(self,name,fn): self.name=name; self.fn=fn
class FileThunk:
    def __init__(self,loader,path): self.loader=loader; self.path=path; self.state="unforced"; self.value=None
    def force(self):
        if self.state=="done": return self.value
        if self.state=="forcing": return ERROR  # data cycle
        self.state="forcing"; self.value=self.loader.evaluate_file(self.path); self.state="done"
        return self.value
class Env:
    def __init__(self,parent=None): self.vars={}; self.parent=parent
    def define(self,k,v): self.vars[k]=v; return self
    def lookup(self,k):
        if k in self.vars: return self.vars[k]
        if self.parent: return self.parent.lookup(k)
        return "__unbound__"
    def child(self,bindings=None):
        e=Env(self)
        if bindings:
            for k,v in bindings.items(): e.define(k,v)
        return e

def is_error(v): return v is ERROR

def deep_equal(a,b):
    if a is b: return True
    if type(a)!=type(b): 
        # treat int/float distinctly like Ruby; but allow bool not == int
        return False
    if isinstance(a,list):
        return len(a)==len(b) and all(deep_equal(x,y) for x,y in zip(a,b))
    if isinstance(a,dict):
        return len(a)==len(b) and all(k in b and deep_equal(v,b[k]) for k,v in a.items())
    return a==b

# ---------------- Interpreter ----------------
class Interp:
    def __init__(self, stdlib_dir=None, env_vars=None):
        self.stdlib_dir=stdlib_dir; self.file_cache={}; self.ast_cache={}
        self.env_vars = env_vars if env_vars is not None else dict(os.environ)
        self.builtins={}; install_builtins(self.builtins, self)
        self.root=Env()   # root no longer holds builtins; bare idents are holes only
    def load_file(self,path):
        if path not in self.file_cache: self.file_cache[path]=FileThunk(self,path)
        return self.file_cache[path]
    def evaluate_file(self,path):
        try:
            if path not in self.ast_cache:
                with open(path, encoding="utf-8") as f: self.ast_cache[path]=Parser.parse_file(f.read())
        except (FileNotFoundError, SyntaxError):
            return ERROR
        ast=self.ast_cache[path]
        env=self.root.child()
        env.define("__dir__", os.path.dirname(path))
        env.define("__file__", path)
        return self.eval(ast,env)

    # Resolve a bare "@name": sibling file > builtin (incl. load, ENV) > stdlib > !.
    def resolve_name(self, name, dirn):
        sib = os.path.abspath(os.path.join(dirn, name + ".fsn"))
        if os.path.exists(sib):
            return self.load_file(sib).force()
        if name == "ENV":
            return {kk: vv for kk, vv in self.env_vars.items()}
        if name == "load":
            # @load is a builtin that must know the calling file's directory, so
            # it resolves to a closure capturing dirn. It loads a VERBATIM filename
            # (no .fsn appended), enabling arbitrary names like "data.json".
            interp = self
            def _load(v):
                if not isinstance(v, str): return ERROR
                target = os.path.abspath(os.path.join(dirn, v))
                if not os.path.exists(target): return ERROR
                return interp.load_file(target).force()
            return NativeFunc("load", _load)
        if name in self.builtins:
            return self.builtins[name]
        if self.stdlib_dir:
            std = os.path.join(self.stdlib_dir, name + ".fsn")
            if os.path.exists(std):
                return self.load_file(std).force()
        return ERROR

    # Resolve a pure path "@dir/a" or "@../a": file only, never builtin/stdlib.
    def resolve_path(self, relpath, dirn):
        return self.load_file(os.path.abspath(os.path.join(dirn, relpath + ".fsn"))).force()

    def eval(self,node,env):
        k=node.kind
        if k=="Lit": return node.value
        if k=="Ident":
            v=env.lookup(node.name); return ERROR if v=="__unbound__" else v
        if k=="FileRef":
            dirn=env.lookup("__dir__")
            if dirn=="__unbound__": dirn=os.getcwd()
            if node.kind2=="self":
                f=env.lookup("__file__")
                return ERROR if f=="__unbound__" else self.load_file(f).force()
            if node.kind2=="name":
                return self.resolve_name(node.path, dirn)
            # "path"
            return self.resolve_path(node.path, dirn)
        if k=="ArrLit":
            out=[]
            for kind,expr in node.elems:
                v=self.eval(expr,env)
                if kind=="spread":
                    if not isinstance(v,list): return ERROR
                    out.extend(v)
                else: out.append(v)
            return out
        if k=="ObjLit":
            out={}
            for m in node.members:
                if m[0]=="spread":
                    v=self.eval(m[1],env)
                    if not isinstance(v,dict): return ERROR
                    out.update(v)
                else: out[m[1]]=self.eval(m[2],env)
            return out
        if k=="FuncLit": return Func(node.clauses,env)
        if k=="Pipe":
            v=self.eval(node.left,env); f=self.eval(node.right,env); return self.apply(f,v)
        if k=="Member":
            obj=self.eval(node.obj,env)
            if not isinstance(obj,dict): return ERROR
            return obj[node.key] if node.key in obj else ERROR
        if k=="Index":
            obj=self.eval(node.obj,env); idx=self.eval(node.idx,env)
            if isinstance(obj,list) and isinstance(idx,int) and not isinstance(idx,bool):
                i=idx if idx>=0 else len(obj)+idx
                return obj[i] if 0<=i<len(obj) else ERROR
            if isinstance(obj,dict) and isinstance(idx,str):
                return obj[idx] if idx in obj else ERROR
            return ERROR
        raise RuntimeError(f"cannot eval {k}")
    def apply(self,f,v):
        if isinstance(f,NativeFunc):
            if v is ERROR: return ERROR
            return f.fn(v)
        if isinstance(f,Func):
            # Error propagation: if the input is `!`, it propagates automatically
            # UNLESS some clause explicitly matches `!` (an `! => ...` handler).
            if v is ERROR and not any(p.kind=="PLit" and p.value is ERROR for p,_ in f.clauses):
                return ERROR
            for pat,body in f.clauses:
                b={}
                if self.match(pat,v,b,f.env):
                    return self.eval(body, f.env.child(b))
            return NULL
        return ERROR
    def match(self,pat,value,b,env):
        k=pat.kind
        if k=="PLit": return deep_equal(pat.value,value)
        if k=="PWild": return not is_error(value)
        if k=="PBind":
            if is_error(value): return False
            b[pat.name]=value; return True
        if k=="PArr": return self.match_array(pat,value,b,env)
        if k=="PObj": return self.match_object(pat,value,b,env)
        if k=="PGuard":
            if not self.match(pat.inner,value,b,env): return False
            pred=self.eval(pat.pred,env)
            return self.apply(pred,value) is True
        raise RuntimeError(f"unknown pattern {k}")
    def match_array(self,pat,value,b,env):
        if not isinstance(value,list): return False
        elems=pat.elems
        rest_i=next((i for i,e in enumerate(elems) if e[0]=="rest"),None)
        if rest_i is None:
            if len(value)!=len(elems): return False
            for i,(_,p) in enumerate(elems):
                if not self.match(p,value[i],b,env): return False
            return True
        before=elems[:rest_i]; after=elems[rest_i+1:]
        if len(value)<len(before)+len(after): return False
        for i,(_,p) in enumerate(before):
            if not self.match(p,value[i],b,env): return False
        for kk,(_,p) in enumerate(after):
            vi=len(value)-len(after)+kk
            if not self.match(p,value[vi],b,env): return False
        name=elems[rest_i][1]
        if name: b[name]=value[len(before):len(value)-len(after)]
        return True
    def match_object(self,pat,value,b,env):
        if not isinstance(value,dict): return False
        matched=[]; rest_name="__none__"
        for m in pat.members:
            if m[0]=="rest": rest_name=m[1]
            else:
                _,key,p=m
                if key not in value: return False
                if not self.match(p,value[key],b,env): return False
                matched.append(key)
        if rest_name not in ("__none__",None):
            b[rest_name]={k:v for k,v in value.items() if k not in matched}
        return True

def install_builtins(table,interp):
    bad=ERROR
    def d(name,fn): table[name]=NativeFunc(name,fn)
    def pair_num(v):
        if isinstance(v,list) and len(v)==2:
            a,bb=v
            if isinstance(a,(int,float)) and not isinstance(a,bool) and isinstance(bb,(int,float)) and not isinstance(bb,bool):
                return (a,bb)
        return None
    def isnum(x): return isinstance(x,(int,float)) and not isinstance(x,bool)
    d("add",lambda v:(lambda p:(p[0]+p[1]) if p else bad)(pair_num(v)))
    d("subtract",lambda v:(lambda p:(p[0]-p[1]) if p else bad)(pair_num(v)))
    d("multiply",lambda v:(lambda p:(p[0]*p[1]) if p else bad)(pair_num(v)))
    def _div(v):
        p=pair_num(v)
        if not p or p[1]==0: return bad
        if isinstance(p[0],int) and isinstance(p[1],int) and p[0]%p[1]==0: return p[0]//p[1]
        return p[0]/p[1]
    d("divide",_div)
    def _mod(v):
        p=pair_num(v)
        if not p or p[1]==0: return bad
        return p[0]%p[1]
    d("mod",_mod)
    d("negate",lambda v:(-v) if isnum(v) else bad)
    import math
    d("floor",lambda v:math.floor(v) if isnum(v) else bad)
    def _eq(v):
        if isinstance(v,list) and len(v)==2: return deep_equal(v[0],v[1])
        return bad
    d("equals",_eq)
    def _lt(v):
        if isinstance(v,list) and len(v)==2:
            a,bb=v
            if isnum(a) and isnum(bb): return a<bb
            if isinstance(a,str) and isinstance(bb,str): return a<bb
        return bad
    d("lessThan",_lt)
    def _and(v):
        if isinstance(v,list) and len(v)==2 and all(x in (True,False) for x in v): return v[0] and v[1]
        return bad
    def _or(v):
        if isinstance(v,list) and len(v)==2 and all(x in (True,False) for x in v): return v[0] or v[1]
        return bad
    d("and",_and); d("or",_or)
    d("not",lambda v:(not v) if v in (True,False) else bad)
    def _len(v):
        if isinstance(v,(str,list,dict)): return len(v)
        return bad
    d("length",_len)
    def _concat(v):
        if isinstance(v,list) and len(v)==2 and all(isinstance(x,str) for x in v): return v[0]+v[1]
        return bad
    d("concat",_concat)
    d("chars",lambda v:list(v) if isinstance(v,str) else bad)
    def _join(v):
        if isinstance(v,list) and len(v)==2:
            arr,sep=v
            if isinstance(arr,list) and isinstance(sep,str) and all(isinstance(x,str) for x in arr): return sep.join(arr)
        return bad
    d("join",_join)
    d("keys",lambda v:list(v.keys()) if isinstance(v,dict) else bad)
    d("values",lambda v:list(v.values()) if isinstance(v,dict) else bad)
    d("Integer",lambda v:isinstance(v,int) and not isinstance(v,bool))
    d("Float",lambda v:isinstance(v,float))
    d("Number",lambda v:isnum(v))
    d("String",lambda v:isinstance(v,str))
    d("Boolean",lambda v:v in (True,False))
    d("Array",lambda v:isinstance(v,list))
    d("Object",lambda v:isinstance(v,dict))
    d("Null",lambda v:v is NULL)

def to_json(v):
    if v is NULL: return "null"
    if v is True: return "true"
    if v is False: return "false"
    if isinstance(v,int): return str(v)
    if isinstance(v,float): return repr(v)
    if isinstance(v,str): return json.dumps(v)
    if isinstance(v,list): return "["+",".join(to_json(x) for x in v)+"]"
    if isinstance(v,dict): return "{"+",".join(json.dumps(k)+":"+to_json(x) for k,x in v.items())+"}"
    if isinstance(v,(Func,NativeFunc)): return '"<function>"'
    if v is ERROR: return '"!"'
    return json.dumps(str(v))

def from_json(text):
    try: raw=json.loads(text)
    except json.JSONDecodeError: return ERROR
    def conv(x):
        if x is None: return NULL
        if isinstance(x,list): return [conv(e) for e in x]
        if isinstance(x,dict): return {k:conv(v) for k,v in x.items()}
        return x
    return conv(raw)
