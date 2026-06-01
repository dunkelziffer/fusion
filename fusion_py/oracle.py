#!/usr/bin/env python3
"""Verification oracle: a faithful port of fusion.rb's logic to test the algorithm.
Same lexer/parser/evaluator structure so passing tests here validate the Ruby design."""

import sys, json, os

class ErrorVal:  # the !payload value: always wraps a payload (any JSON value)
    __slots__ = ("payload",)
    def __init__(self, payload): self.payload = payload
    def __repr__(self): return f"!{self.payload!r}"
def is_error(v): return isinstance(v, ErrorVal)
def mkerr(payload=None): return ErrorVal(payload)
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
class ErrLit(Node): pass    # ! or !expr -- if payload is None, defaults to null
class ArrLit(Node): pass
class ObjLit(Node): pass
class FuncLit(Node): pass
class Ident(Node): pass
class FileRef(Node): pass
class Pipe(Node): pass
class Member(Node): pass
class Index(Node): pass
class PLit(Node): pass
class PErr(Node): pass      # !pat -- if pat is None, matches any error; payload is unbound
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
        left=self.prefix()
        while self.at("pipe"):
            self.adv(); left=Pipe(left=left,right=self.prefix())
        return left
    # "!" is a prefix that constructs an error from its operand.
    # Bare "!" (no operand follows) is shorthand for "!null".
    # Binds tighter than "|" so "!x | f" is "(!x) | f"; binds looser than postfix
    # so "!x.foo" is "!(x.foo)".
    PRIMARY_STARTERS = {"number","string","true_kw","false_kw","null_kw",
                        "bang","lbracket","lbrace","lparen","ident","at"}
    def prefix(self):
        if self.at("bang"):
            self.adv()
            if self.peek().type in Parser.PRIMARY_STARTERS:
                payload = self.prefix()   # allow !!x to nest
                return ErrLit(payload=payload)
            return ErrLit(payload=None)   # bare "!" -> !null
        return self.postfix()
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
    # ---- Pattern grammar (mirrors reference.md §2.5 EBNF) ------------------
    #   pattern    = errpat | guardedpat
    #   errpat     = "!" | "!" guardedpat
    #   guardedpat = corepat [ "?" predicate ]
    #   corepat    = literalpat | bindpat | wildcard | arraypat | objectpat
    # Note: `corepat` does NOT include errpat. The "no nested !pat" property
    # falls out of the grammar shape — `errpat` is only reachable from `pattern`
    # (a clause's top level), never from inside arrays, objects, or another
    # error's payload. No `allow_err` flag is needed.
    def pattern(self):
        if self.at("bang"):
            return self.errpat()
        return self.guardedpat()

    # Tokens that can begin a `guardedpat` (used to detect whether `!` is
    # followed by a payload pattern or stands alone).
    GUARDEDPAT_STARTERS = {"number","string","true_kw","false_kw","null_kw",
                           "lbracket","lbrace","ident"}

    def errpat(self):
        self.expect("bang")
        if self.peek().type in Parser.GUARDEDPAT_STARTERS:
            return PErr(inner=self.guardedpat())     # "!" guardedpat
        return PErr(inner=None)                       # bare "!" — matches any error, binds nothing

    def guardedpat(self):
        inner = self.corepat()
        if self.at("question"):
            self.adv(); pred = self.prefix()
            return PGuard(inner=inner, pred=pred)
        return inner

    def corepat(self):
        t = self.peek()
        if t.type in ("number","string"): self.adv(); return PLit(value=t.value)
        if t.type in ("true_kw","false_kw","null_kw"): self.adv(); return PLit(value=t.value)
        if t.type == "lbracket": return self.arraypat()
        if t.type == "lbrace": return self.objectpat()
        if t.type == "ident":
            self.adv(); return PWild() if t.value == "_" else PBind(name=t.value)
        # An unexpected `bang` here means `!pat` was attempted in a context that
        # only admits `guardedpat` (array element, object member, error payload).
        if t.type == "bang":
            raise SyntaxError(
                f"`!pat` may only appear as a clause's top-level pattern (at {t.pos})")
        raise SyntaxError(f"Unexpected pattern tok {t.type} at {t.pos}")

    def arraypat(self):
        # Array elements are `guardedpat`s — they cannot be error patterns.
        self.expect("lbracket"); elems=[]
        while not self.at("rbracket"):
            if self.at("spread"):
                self.adv(); name=self.adv().value if self.at("ident") else None; elems.append(("rest",name))
            else: elems.append(("pat", self.guardedpat()))
            if not self.at("comma"): break
            self.adv()
        self.expect("rbracket"); return PArr(elems=elems)

    def objectpat(self):
        # Object members are `guardedpat`s — they cannot be error patterns.
        self.expect("lbrace"); members=[]
        while not self.at("rbrace"):
            if self.at("spread"):
                self.adv(); name=self.adv().value if self.at("ident") else None; members.append(("rest",name))
            else:
                k=self.expect("string").value; self.expect("colon")
                members.append(("kv", k, self.guardedpat()))
            if not self.at("comma"): break
            self.adv()
        self.expect("rbrace"); return PObj(members=members)

# ---------------- Runtime values ----------------
class Func:
    def __init__(self,clauses,env): self.clauses=clauses; self.env=env
class NativeFunc:
    def __init__(self,name,fn):
        self.name=name; self.fn=fn
class FileThunk:
    def __init__(self,loader,path): self.loader=loader; self.path=path; self.state="unforced"; self.value=None
    def force(self):
        if self.state=="done": return self.value
        if self.state=="forcing":
            return mkerr({"kind":"data_cycle","path":self.path})  # non-productive cycle
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
        except FileNotFoundError:
            return mkerr({"kind":"file_not_found","path":path})
        except SyntaxError as ex:
            return mkerr({"kind":"parse_error","path":path,"message":str(ex)})
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
                if not isinstance(v, str):
                    return mkerr({"kind":"load_bad_arg","got":type(v).__name__})
                target = os.path.abspath(os.path.join(dirn, v))
                if not os.path.exists(target):
                    return mkerr({"kind":"file_not_found","path":target})
                return interp.load_file(target).force()
            return NativeFunc("load", _load)
        if name in self.builtins:
            return self.builtins[name]
        if self.stdlib_dir:
            std = os.path.join(self.stdlib_dir, name + ".fsn")
            if os.path.exists(std):
                return self.load_file(std).force()
        return mkerr({"kind":"unresolved_ref","name":name})

    # Resolve a pure path "@dir/a" or "@../a": file only, never builtin/stdlib.
    def resolve_path(self, relpath, dirn):
        return self.load_file(os.path.abspath(os.path.join(dirn, relpath + ".fsn"))).force()

    def eval(self,node,env):
        k=node.kind
        if k=="Lit": return node.value
        if k=="ErrLit":
            if node.payload is None:
                return mkerr(NULL)            # bare "!" == "!null"
            p = self.eval(node.payload, env)
            # If the payload expression itself errored, propagate THAT error rather
            # than wrapping it -- prevents accidental error-burying.
            if is_error(p): return p
            return mkerr(p)
        if k=="Ident":
            v=env.lookup(node.name)
            return mkerr({"kind":"unbound","name":node.name}) if v=="__unbound__" else v
        if k=="FileRef":
            dirn=env.lookup("__dir__")
            if dirn=="__unbound__": dirn=os.getcwd()
            if node.kind2=="self":
                f=env.lookup("__file__")
                return mkerr({"kind":"no_current_file"}) if f=="__unbound__" else self.load_file(f).force()
            if node.kind2=="name":
                return self.resolve_name(node.path, dirn)
            # "path"
            return self.resolve_path(node.path, dirn)
        if k=="ArrLit":
            out=[]
            for kind,expr in node.elems:
                v=self.eval(expr,env)
                # Errors are not first-class: an error during construction
                # propagates out of the whole literal.
                if is_error(v): return v
                if kind=="spread":
                    if not isinstance(v,list):
                        return mkerr({"kind":"spread_non_array","got":type(v).__name__})
                    out.extend(v)
                else:
                    out.append(v)
            return out
        if k=="ObjLit":
            out={}
            for m in node.members:
                if m[0]=="spread":
                    v=self.eval(m[1],env)
                    if is_error(v): return v
                    if not isinstance(v,dict):
                        return mkerr({"kind":"spread_non_object","got":type(v).__name__})
                    out.update(v)
                else:
                    v=self.eval(m[2],env)
                    if is_error(v): return v
                    out[m[1]]=v
            return out
        if k=="FuncLit": return Func(node.clauses,env)
        if k=="Pipe":
            v=self.eval(node.left,env); f=self.eval(node.right,env); return self.apply(f,v)
        if k=="Member":
            obj=self.eval(node.obj,env)
            if is_error(obj): return obj
            if not isinstance(obj,dict):
                return mkerr({"kind":"member_on_non_object","key":node.key})
            if node.key not in obj:
                return mkerr({"kind":"missing_key","key":node.key})
            return obj[node.key]
        if k=="Index":
            obj=self.eval(node.obj,env)
            if is_error(obj): return obj
            idx=self.eval(node.idx,env)
            if is_error(idx): return idx
            if isinstance(obj,list) and isinstance(idx,int) and not isinstance(idx,bool):
                i=idx if idx>=0 else len(obj)+idx
                if 0<=i<len(obj): return obj[i]
                return mkerr({"kind":"index_out_of_range","index":idx,"length":len(obj)})
            if isinstance(obj,dict) and isinstance(idx,str):
                if idx in obj: return obj[idx]
                return mkerr({"kind":"missing_key","key":idx})
            return mkerr({"kind":"bad_index","obj":type(obj).__name__,"idx":type(idx).__name__})
        raise RuntimeError(f"cannot eval {k}")

    def apply(self,f,v):
        if is_error(f):                       # piping into an errored function value
            return f                          # propagate that error unchanged
        if isinstance(f,NativeFunc):
            if is_error(v): return v          # uniform propagation; errors are never inputs
            return f.fn(v)
        if isinstance(f,Func):
            for pat,body in f.clauses:
                b={}
                m = self.match(pat,v,b,f.env)
                if is_error(m):
                    # A `?` predicate raised an error during this clause's matching.
                    # The error bubbles up as the function's return value (no
                    # further clauses are tried).
                    return m
                if m:
                    return self.eval(body, f.env.child(b))
            # No clause matched. If the input was an error, it keeps propagating
            # (an unmatched error must never be silently swallowed). Otherwise
            # the lenient default is `null`.
            return v if is_error(v) else NULL
        return mkerr({"kind":"apply_non_function","got":type(f).__name__})

    def match(self,pat,value,b,env):
        """Returns True (match), False (no match), or an ErrorVal (predicate errored)."""
        k=pat.kind
        if k=="PLit": return deep_equal(pat.value,value)
        if k=="PErr":
            if not is_error(value): return False
            if pat.inner is None:               # bare "!" matches any error
                return True
            return self.match(pat.inner, value.payload, b, env)
        if k=="PWild":  return not is_error(value)
        if k=="PBind":
            if is_error(value): return False
            b[pat.name]=value; return True
        if k=="PArr":   return self.match_array(pat,value,b,env)
        if k=="PObj":   return self.match_object(pat,value,b,env)
        if k=="PGuard":
            inner_res = self.match(pat.inner, value, b, env)
            if is_error(inner_res): return inner_res    # error from a nested ? predicate
            if not inner_res: return False
            pred = self.eval(pat.pred, env)
            if is_error(pred): return pred              # predicate name/expr itself errored
            # The predicate sees the same value the inner pattern matched against.
            # (For `!pat ? pred`, the grammar puts the guard INSIDE the PErr, so by
            # the time we get here `value` is already the payload — no special case.)
            r = self.apply(pred, value)
            if is_error(r): return r                    # predicate-error bubbles up
            return r is True
        raise RuntimeError(f"unknown pattern {k}")
    def match_array(self,pat,value,b,env):
        if not isinstance(value,list): return False
        elems=pat.elems
        rest_i=next((i for i,e in enumerate(elems) if e[0]=="rest"),None)
        if rest_i is None:
            if len(value)!=len(elems): return False
            for i,(_,p) in enumerate(elems):
                r = self.match(p,value[i],b,env)
                if is_error(r): return r
                if not r: return False
            return True
        before=elems[:rest_i]; after=elems[rest_i+1:]
        if len(value)<len(before)+len(after): return False
        for i,(_,p) in enumerate(before):
            r = self.match(p,value[i],b,env)
            if is_error(r): return r
            if not r: return False
        for kk,(_,p) in enumerate(after):
            vi=len(value)-len(after)+kk
            r = self.match(p,value[vi],b,env)
            if is_error(r): return r
            if not r: return False
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
                r = self.match(p,value[key],b,env)
                if is_error(r): return r
                if not r: return False
                matched.append(key)
        if rest_name not in ("__none__",None):
            b[rest_name]={k:v for k,v in value.items() if k not in matched}
        return True

def install_builtins(table,interp):
    def E(fn, msg): return mkerr(f"{fn}: {msg}")
    def d(name,fn): table[name]=NativeFunc(name,fn)
    def pair_num(v):
        if isinstance(v,list) and len(v)==2:
            a,bb=v
            if isinstance(a,(int,float)) and not isinstance(a,bool) and isinstance(bb,(int,float)) and not isinstance(bb,bool):
                return (a,bb)
        return None
    def isnum(x): return isinstance(x,(int,float)) and not isinstance(x,bool)
    def _add(v):
        p=pair_num(v); return (p[0]+p[1]) if p else E("add","expected a pair of numbers")
    def _sub(v):
        p=pair_num(v); return (p[0]-p[1]) if p else E("subtract","expected a pair of numbers")
    def _mul(v):
        p=pair_num(v); return (p[0]*p[1]) if p else E("multiply","expected a pair of numbers")
    d("add",_add); d("subtract",_sub); d("multiply",_mul)
    def _div(v):
        p=pair_num(v)
        if not p: return E("divide","expected a pair of numbers")
        if p[1]==0: return E("divide","division by zero")
        if isinstance(p[0],int) and isinstance(p[1],int) and p[0]%p[1]==0: return p[0]//p[1]
        return p[0]/p[1]
    d("divide",_div)
    def _mod(v):
        p=pair_num(v)
        if not p: return E("mod","expected a pair of numbers")
        if p[1]==0: return E("mod","modulo by zero")
        return p[0]%p[1]
    d("mod",_mod)
    d("negate",lambda v:(-v) if isnum(v) else E("negate","expected a number"))
    import math
    d("floor",lambda v:math.floor(v) if isnum(v) else E("floor","expected a number"))
    def _eq(v):
        if isinstance(v,list) and len(v)==2: return deep_equal(v[0],v[1])
        return E("equals","expected a pair")
    d("equals",_eq)
    def _lt(v):
        if isinstance(v,list) and len(v)==2:
            a,bb=v
            if isnum(a) and isnum(bb): return a<bb
            if isinstance(a,str) and isinstance(bb,str): return a<bb
        return E("lessThan","expected two numbers or two strings")
    d("lessThan",_lt)
    def _and(v):
        if isinstance(v,list) and len(v)==2 and all(x in (True,False) for x in v): return v[0] and v[1]
        return E("and","expected a pair of booleans")
    def _or(v):
        if isinstance(v,list) and len(v)==2 and all(x in (True,False) for x in v): return v[0] or v[1]
        return E("or","expected a pair of booleans")
    d("and",_and); d("or",_or)
    d("not",lambda v:(not v) if v in (True,False) else E("not","expected a boolean"))
    def _len(v):
        if isinstance(v,(str,list,dict)): return len(v)
        return E("length","expected a string, array, or object")
    d("length",_len)
    def _concat(v):
        if isinstance(v,list) and len(v)==2 and all(isinstance(x,str) for x in v): return v[0]+v[1]
        return E("concat","expected a pair of strings")
    d("concat",_concat)
    d("chars",lambda v:list(v) if isinstance(v,str) else E("chars","expected a string"))
    def _join(v):
        if isinstance(v,list) and len(v)==2:
            arr,sep=v
            if isinstance(arr,list) and isinstance(sep,str) and all(isinstance(x,str) for x in arr): return sep.join(arr)
        return E("join","expected [array-of-strings, separator-string]")
    d("join",_join)
    def _ts(v):
        if v is NULL: return "null"
        if v is True: return "true"
        if v is False: return "false"
        if isinstance(v,str): return v
        if isnum(v): return str(v)
        return E("toString","cannot stringify this value type")
    d("toString",_ts)
    def _pn(v):
        if not isinstance(v,str): return E("parseNumber","expected a string")
        try:
            if "." in v or "e" in v or "E" in v: return float(v)
            return int(v)
        except ValueError:
            return E("parseNumber","not a numeric string")
    d("parseNumber",_pn)
    d("keys",lambda v:list(v.keys()) if isinstance(v,dict) else E("keys","expected an object"))
    d("values",lambda v:list(v.values()) if isinstance(v,dict) else E("values","expected an object"))
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
    if isinstance(v, ErrorVal):
        # Render errors as the syntactic form "!<payload-json>" so tests can compare
        # straightforwardly. Note: this is NOT valid JSON; the CLI sends an error's
        # payload to stderr (as JSON) and prints nothing to stdout on error.
        return "!" + to_json(v.payload)
    return json.dumps(str(v))

def from_json(text):
    try: raw=json.loads(text)
    except json.JSONDecodeError:
        return mkerr({"kind":"stdin_not_json"})
    def conv(x):
        if x is None: return NULL
        if isinstance(x,list): return [conv(e) for e in x]
        if isinstance(x,dict): return {k:conv(v) for k,v in x.items()}
        return x
    return conv(raw)
