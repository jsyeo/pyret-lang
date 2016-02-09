provide *
provide-types *

import ast as A
import string-dict as SD
import equality as EQ
import valueskeleton as VS
import "compiler/type-structs.arr" as TS
import "compiler/type-defaults.arr" as TD
import "compiler/compile-structs.arr" as C

type Name                 = A.Name

dict-to-string            = TS.dict-to-string
mut-dict-to-string        = TS.mut-dict-to-string

type Type                 = TS.Type
t-name                    = TS.t-name
t-var                     = TS.t-var
t-arrow                   = TS.t-arrow
t-top                     = TS.t-top
t-bot                     = TS.t-bot
t-app                     = TS.t-app
t-record                  = TS.t-record
t-forall                  = TS.t-forall
t-ref                     = TS.t-ref
t-existential             = TS.t-existential

data Pair<L,R>:
  | pair(left :: L, right :: R)
sharing:
  on-left(self, f :: (L -> L)) -> Pair<L,R>:
    pair(f(self.left), self.right)
  end,
  on-right(self, f :: (R -> R)) -> Pair<L,R>:
    pair(self.left, f(self.right))
  end
end

type TypeMember           = TS.TypeMember
type TypeVariant          = TS.TypeVariant
type DataType             = TS.DataType
type ModuleType           = TS.ModuleType

t-module                  = TS.t-module

type Bindings              = SD.StringDict<TS.Type>
empty-bindings :: Bindings = SD.make-string-dict()

type LocalContext = List<ContextItem>

# TODO(MATT): add refinements and fix types
data ContextItem:
  | term-var(variable :: String, typ :: Type)
  | existential-assign(variable :: Type, typ :: Type)
  | data-type-var(variable :: String, typ :: Type)
end

data Context:
  | typing-context(local-context :: LocalContext, info :: TCInfo)
with:
  has-var-key(self, id-key):
    cases(Option) find(lam(item): is-term-var(item) and (item.variable == id-key) end,
                       self.local-context):
      | some(_) => true
      | none => self.info.typs.has-key-now(id-key)
    end
  end,
  get-var-type(self, id-key):
    cases(Option) find(lam(item): is-term-var(item) and (item.variable == id-key) end,
                       self.local-context):
      | some(item) => item.typ
      | none => self.info.typs.get-value-now(id-key)
    end
  end,
  get-data-type-var(self, id-key):
    cases(Option) find(lam(item): is-data-type-var(item) and (item.variable == id-key) end,
                       self.local-context):
      | some(item) => some(item.typ)
      | none => raise("couldn't find datatype locally")
    end
  end,
  get-data-type(self, typ):
    cases(Type) typ:
      | t-name(module-name, name) =>
        cases(Option<String>) module-name:
          | some(mod) =>
            raise("other modules not handled yet")
          | none =>
            key = typ.key()
            cases(Option<Type>) self.get-data-type-var(key):
              | some(shadow typ) => some(typ)
              | none => raise("I haven't figured out what to put here")
            end
        end
      | else => raise("get-data-type doesn't handle " + tostring(typ) + " yet")
    end
  end,
  add-term-var(self, var-name, typ :: Type):
    typing-context(link(term-var(var-name, typ), self.local-context), self.info)
  end,
  add-data-type(self, type-name, typ):
    typing-context(link(data-type-var(type-name, typ), self.local-context), self.info)
  end,
  # TODO(MATT): this should raise an error when the existential has already been assigned?
  assign-existential(self, existential, assigned-typ):
    typing-context(link(existential-assign(existential, assigned-typ),
      self.local-context.map(lam(item):
        cases(ContextItem) item:
          | term-var(variable, typ) =>
            term-var(variable, typ.substitute(existential, assigned-typ))
          | existential-assign(variable, typ) =>
            existential-assign(variable, typ.substitute(existential, assigned-typ))
          | data-type-var(variable, typ) =>
            data-type-var(variable, typ.substitute(existential, assigned-typ))
        end
      end)), self.info)
  end,
  apply(self, typ :: Type) -> Type:
    self.local-context.foldl(lam(item, curr-typ):
      cases(ContextItem) item:
        | existential-assign(variable, assigned-typ) => curr-typ.substitute(variable, assigned-typ)
        | else => curr-typ
      end
    end, typ)
  end,
  _output(self):
    VS.vs-constr("typing-context",
      [list: VS.vs-value(self.local-context)])
  end
end

data Typed:
  | typed(ast :: A.Program, info :: TCInfo)
end

data TCInfo:
  | tc-info(typs       :: SD.MutableStringDict<TS.Type>,
            aliases    :: SD.MutableStringDict<TS.Type>,
            data-exprs :: SD.MutableStringDict<TS.DataType>,
            branders   :: SD.MutableStringDict<TS.Type>,
            modules    :: SD.MutableStringDict<TS.ModuleType>,
            mod-names  :: SD.MutableStringDict<String>,
            binds      :: Bindings,
            ref modul  :: TS.ModuleType,
            errors     :: { insert :: (C.CompileError -> List<C.CompileError>),
                            get    :: (-> List<C.CompileError>)})
sharing:
  _output(self):
    VS.vs-constr("tc-info",
      [list:
        VS.vs-value(mut-dict-to-string(self.typs)),
        VS.vs-value(mut-dict-to-string(self.aliases)),
        VS.vs-value(mut-dict-to-string(self.data-exprs)),
        VS.vs-value(mut-dict-to-string(self.branders)),
        VS.vs-value(mut-dict-to-string(self.modules)),
        VS.vs-value(self.binds),
        VS.vs-value(self.errors.get())])
  end
end

fun empty-tc-info(mod-name :: String) -> TCInfo:
  curr-module = t-module(mod-name, t-top, SD.make-string-dict(), SD.make-string-dict())
  errors = block:
    var err-list = empty
    {
      insert: lam(err :: C.CompileError):
        err-list := link(err, err-list)
      end,
      get: lam():
        err-list
      end
    }
  end
  tc-info(TD.make-default-typs(), TD.make-default-aliases(), TD.make-default-data-exprs(), SD.make-mutable-string-dict(), TD.make-default-modules(), SD.make-mutable-string-dict(), empty-bindings, curr-module, errors)
end

fun add-binding-string(id :: String, bound :: Type, info :: TCInfo) -> TCInfo:
  new-binds = info.binds.set(id, bound)
  tc-info(info.typs, info.aliases, info.data-exprs, info.branders, info.modules, info.mod-names, new-binds, info!modul, info.errors)
end

fun add-binding(id :: Name, bound :: Type, info :: TCInfo) -> TCInfo:
  add-binding-string(id.key(), bound, info)
end

fun add-type-variable(tv :: TS.TypeVariable, info :: TCInfo) -> TCInfo:
  add-binding(tv.id, tv.upper-bound, info)
end

fun get-data-type(typ :: Type, info :: TCInfo) -> Option<DataType>:
  cases(Type) typ:
    | t-name(module-name, name) =>
      cases(Option<String>) module-name:
        | some(mod) =>
          cases(Option<ModuleType>) info.modules.get-now(mod):
            | some(t-mod) =>
              cases(Option<DataType>) t-mod.types.get(name.toname()):
                | some(shadow typ) => some(typ)
                | none =>
                  cases(Option<Type>) t-mod.aliases.get(name.toname()):
                    | some(shadow typ) => get-data-type(typ, info)
                    | none =>
                      raise("No type " + torepr(typ) + " available on `" + torepr(t-mod) + "'")
                  end
              end
            | none =>
              if mod == "builtin":
                info.data-exprs.get-now(name.toname())
              else:
                raise("No module available with the name `" + mod + "'")
              end
          end
        | none =>
          key = typ.key()
          cases(Option<DataType>) info.data-exprs.get-now(key):
            | some(shadow typ) => some(typ)
            | none =>
              cases(Option<Type>) info.aliases.get-now(name.tosourcestring()):
                | some(shadow typ) => get-data-type(typ, info)
                | none =>
                  raise("No type " + torepr(typ) + " available in this module")
              end
          end
      end
    | t-app(base-typ, args) =>
      cases(Option<DataType>) get-data-type(base-typ, info):
        | some(new-base-typ) =>
          data-type = new-base-typ.introduce(args)
          cases(Option<DataType>) data-type:
            | some(dt) => data-type
            | none => raise("Internal type-checking error: This shouldn't happen, since the length of type arguments should have already been compared against the length of parameters")
          end
        | none => none
      end
    | else =>
      none
  end
end

fun bind(f, a): a.bind(f);
fun map-bind(f, a): a.map-bind(f);
fun check-bind(f, a): a.check-bind(f);
fun synth-bind(f, a): a.synth-bind(f);
fun fold-bind(f, a): a.fold-bind(f);

# TODO(MATT): fix bind
data SynthesisResult:
  | synthesis-result(ast :: A.Expr, loc :: A.Loc, typ :: Type, out-context :: Context) with:
    bind(self, f) -> SynthesisResult:
      f(self.ast, self.loc, self.typ, self.out-context)
    end,
    map-expr(self, f) -> SynthesisResult:
      synthesis-result(f(self.ast), self.loc, self.typ, self.out-context)
    end,
    map-typ(self, f) -> SynthesisResult:
      synthesis-result(self.ast, self.loc, f(self.typ), self.out-context)
    end,
    synth-bind(self, f) -> SynthesisResult:
      f(self.ast, self.loc, self.typ, self.out-context)
    end,
    check-bind(self, f) -> CheckingResult:
      f(self.ast, self.loc, self.typ, self.out-context)
    end,
    fold-bind(self, f) -> FoldResult:
      f(self.ast, self.loc, self.typ, self.out-context)
    end
  | synthesis-binding-result(let-bind, typ :: Type, out-context :: Context) with:
    bind(self, f) -> SynthesisResult:
      f(self.let-bind, self.typ, self.out-context)
    end,
    map-expr(self, f) -> SynthesisResult:
      raise("Cannot map expr on synthesis-binding-result!")
    end,
    map-typ(self, f) -> SynthesisResult:
      synthesis-binding-result(self.let-bind, f(self.typ))
    end,
    check-bind(self, f) -> CheckingResult:
      f(self.let-bind, self.typ, self.out-context)
    end
  | synthesis-err(errors :: List<C.CompileError>) with:
    bind(self, f) -> SynthesisResult:
      self
    end,
    map-expr(self, f) -> SynthesisResult:
      self
    end,
    map-typ(self, f) -> SynthesisResult:
      self
    end,
    synth-bind(self, f) -> SynthesisResult:
      self
    end,
    check-bind(self, f) -> CheckingResult:
      checking-err(self.errors)
    end,
    fold-bind(self, f) -> FoldResult:
      fold-errors(self.errors)
    end
sharing:
  # TODO(MATT): delete
  _output(self):
    cases(SynthesisResult) self:
      | synthesis-result(ast, loc, typ, out-context) =>
        VS.vs-constr("tc-synthesis-result",
          [list:
            VS.vs-value(tostring(ast)),
            VS.vs-value(tostring(typ)),
            VS.vs-value(tostring(out-context))])
      | synthesis-binding-result(let-bind, typ, out-context) =>
        VS.vs-constr("tc-synthesis-binding-result",
          [list:
            VS.vs-value(tostring(let-bind)),
            VS.vs-value(tostring(typ)),
            VS.vs-value(tostring(out-context))])
      | synthesis-err(errors) =>
        VS.vs-constr("tc-synthesis-err",
          [list:
            VS.vs-value(tostring(errors))])
    end
  end
end

fun fold-synthesis<B>(f :: (B, Context -> SynthesisResult), context :: Context, lst :: List<B>) -> FoldResult<Pair<Context, List>>:
  cases(List<B>) lst:
    | empty => fold-result(pair(context, empty))
    | link(first, rest) =>
      cases(SynthesisResult) f(first, context):
        | synthesis-result(ast, loc, typ, out-context) =>
          fold-synthesis(f, out-context, rest).bind(lam(result-pair):
            fold-result(pair(result-pair.left, link(ast, result-pair.right)))
          end)
        | synthesis-binding-result(binding, typ, out-context) =>
          new-context = out-context.add-term-var(binding.b.id.key(), typ)
          fold-synthesis(f, new-context, rest).bind(lam(result-pair):
            fold-result(pair(result-pair.left, link(binding, result-pair.right)))
          end)
        | synthesis-err(errors) => fold-errors(errors)
      end
  end
end

fun fold-checking<B>(f :: (B, Context -> CheckingResult), context :: Context, lst :: List<B>) -> FoldResult<Pair<Context, List>>:
  cases(List<B>) lst:
    | empty => fold-result(pair(context, empty))
    | link(first, rest) =>
      cases(CheckingResult) f(first, context):
        | checking-result(ast, out-context) =>
          fold-checking(f, out-context, rest).bind(lam(result-pair):
            fold-result(pair(result-pair.left, link(ast, result-pair.right)))
          end)
        | checking-err(errors) => fold-errors(errors)
      end
  end
end

fun collapse-fold-list<B>(results :: List<FoldResult<B>>) -> FoldResult<List<B>>:
  cases(List<FoldResult<B>>) results:
    | empty => fold-result(empty)
    | link(first, rest) =>
      for bind(result from first):
        for bind(rest-results from collapse-fold-list(rest)):
          fold-result(link(result, rest-results))
        end
      end
  end
end

fun map-result<X, Y>(f :: (X -> FoldResult<C>), lst :: List<Y>) -> FoldResult<List<Y>>:
  collapse-fold-list(map(f, lst))
end

data CheckingResult:
  | checking-result(ast :: A.Expr, out-context :: Context) with:
    bind(self, f) -> CheckingResult:
      f(self.ast, self.out-context)
    end,
    map(self, f) -> CheckingResult:
      checking-result(f(self.ast), self.out-context)
    end,
    check-bind(self, f) -> CheckingResult:
      f(self.ast, self.out-context)
    end,
    synth-bind(self, f) -> SynthesisResult:
      f(self.ast, self.out-context)
    end,
    fold-bind(self, f) -> FoldResult:
      f(self.ast, self.out-context)
    end,
  | checking-err(errors :: List<C.CompileError>) with:
    bind(self, f) -> CheckingResult:
      self
    end,
    check-bind(self, f) -> CheckingResult:
      self
    end,
    map(self, f) -> CheckingResult:
      self
    end,
    synth-bind(self, f) -> SynthesisResult:
      synthesis-err(self.errors)
    end,
    fold-bind(self, f) -> FoldResult:
      fold-errors(self.errors)
    end
end

data FoldResult<V>:
  | fold-result(v :: V) with:
    _output(self):
      VS.vs-constr("fold-result", [list: VS.vs-value(self.v)])
    end,
    bind(self, f) -> FoldResult<V>:
      f(self.v)
    end,
    map(self, f) -> FoldResult:
      fold-result(f(self.v))
    end,
    check-bind(self, f) -> CheckingResult:
      f(self.v)
    end,
    synth-bind(self, f) -> SynthesisResult:
      f(self.v)
    end
  | fold-errors(errors :: List<C.CompileError>) with:
    _output(self):
      VS.vs-constr("fold-errors", [list: VS.vs-value(self.errors)])
    end,
    bind(self, f) -> FoldResult<V>:
      self
    end,
    map(self, f) -> FoldResult:
      self
    end,
    check-bind(self, f) -> CheckingResult:
      checking-err(self.errors)
    end,
    synth-bind(self, f) -> SynthesisResult:
      synthesis-err(self.errors)
    end
end

