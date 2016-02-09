provide *
provide-types *

import ast as A
import string-dict as SD
import "compiler/list-aux.arr" as LA
import equality as E
import valueskeleton as VS

all2-strict  = LA.all2-strict
map2-strict  = LA.map2-strict
fold2-strict = LA.fold2-strict

type Name = A.Name

fun dict-to-string(dict :: SD.StringDict):
  items = for sets.fold(acc from empty, key from dict.keys()):
    if is-empty(acc):
      [list: VS.vs-value(key), VS.vs-str(" => "), VS.vs-value(dict.get-value(key))]
    else:
      link(VS.vs-value(key),
        link(VS.vs-str(" => "),
          link(VS.vs-value(dict.get-value(key)),
            link(VS.vs-str(", "),
              acc))))
    end
  end
  VS.vs-seq([list: VS.vs-str("{")] + items + [list: VS.vs-str("}")])
end

fun mut-dict-to-string(dict :: SD.MutableStringDict) -> VS.ValueSkeleton:
  items = for sets.fold(acc from empty, key from dict.keys-now()):
    if is-empty(acc):
      [list: VS.vs-value(key), VS.vs-str(" => "), VS.vs-value(dict.get-value-now(key))]
    else:
      link(VS.vs-value(key),
        link(VS.vs-str(" => "),
          link(VS.vs-value(dict.get-value-now(key)),
            link(VS.vs-str(", "),
              acc))))
    end
  end
  VS.vs-seq([list: VS.vs-str("{")] + items + [list: VS.vs-str("}")])
end

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

data Comparison:
  | less-than
  | equal
  | greater-than
sharing:
  _comp(self, other):
    cases(Comparison) other:
      | less-than    =>
        cases(Comparison) self:
          | less-than    => equal
          | equal        => greater-than
          | greater-than => greater-than
        end
      | equal       => self
      | greater-than =>
        cases(Comparison) self:
          | less-than    => less-than
          | equal        => less-than
          | greater-than => equal
        end
    end
  end
end

fun std-compare(a, b) -> Comparison:
  if a < b: less-than
  else if a > b: greater-than
  else: equal;
end

fun list-compare<T>(a :: List<T>, b :: List<T>) -> Comparison:
  cases(List<T>) a:
    | empty => cases(List<T>) b:
        | empty   => equal
        | link(_) => less-than
      end
    | link(a-f, a-r) => cases(List<T>) b:
        | empty          => greater-than
        | link(b-f, b-r) => cases (Comparison) a-f._comp(b-f):
            | less-than    => less-than
            | greater-than => greater-than
            | equal        => list-compare(a-r, b-r)
          end
      end
  end
end

fun fold-comparisons(l :: List<Comparison>) -> Comparison:
  cases (List<Comparison>) l:
    | empty      => equal
    | link(f, r) => cases (Comparison) f:
        | equal  => fold-comparisons(r)
        | else   => f
      end
  end
end

data Variance:
  | constant with:
    join(self, other :: Variance):
      other
    end,
    flip(self):
      constant
    end
  | bivariant with:
    join(self, other :: Variance):
      cases(Variance) other:
        | constant => bivariant
        | else => other
      end
    end,
    flip(self):
      bivariant
    end
  | covariant with:
    join(self, other :: Variance):
      cases(Variance) other:
        | constant      => covariant
        | bivariant     => covariant
        | covariant     => covariant
        | contravariant => invariant
        | invariant     => invariant
      end
    end,
    flip(self):
      contravariant
    end
  | contravariant with:
    join(self, other :: Variance):
      cases(Variance) other:
        | constant      => contravariant
        | bivariant     => contravariant
        | covariant     => invariant
        | contravariant => contravariant
        | invariant     => invariant
      end
    end,
    flip(self):
      covariant
    end
  | invariant with:
    join(self, other :: Variance):
      invariant
    end,
    flip(self):
      invariant
    end
end

data TypeMember:
  | t-member(field-name :: String, typ :: Type) with:
    _output(self):
      VS.vs-seq([list: VS.vs-str(self.field-name), VS.vs-str(" : "), VS.vs-value(self.typ)])
    end,
    key(self):
      self.field-name + " : " + self.typ.key()
    end,
    substitute(self, x :: Type, r :: Type):
      t-member(self.field-name, self.typ.substitute(x, r))
    end
sharing:
  _comp(a, b :: TypeMember) -> Comparison:
    fold-comparisons([list:
        std-compare(a.field-name, b.field-name),
        a.typ._comp(b.typ)
      ])
  end
end

type TypeMembers = List<TypeMember>
empty-type-members = empty

fun type-members-lookup(type-members :: TypeMembers, field-name :: String) -> Option<TypeMember>:
  fun same-field(tm):
    tm.field-name == field-name
  end
  type-members.find(same-field)
end

data TypeVariant:
  | t-variant(name        :: String,
              fields      :: TypeMembers,
              with-fields :: TypeMembers) with:
    substitute(self, x :: Type, r :: Type):
      substitute = _.substitute(x, r)
      t-variant(self.name, self.fields.map(substitute), self.with-fields.map(substitute))
    end
  | t-singleton-variant(name        :: String,
                        with-fields :: TypeMembers) with:
    fields: empty-type-members,
    substitute(self, x :: Type, r :: Type):
      substitute = _.substitute(x, r)
      t-singleton-variant(self.name, self.with-fields.map(substitute))
    end
end

fun type-variant-fields(tv :: TypeVariant) -> TypeMembers:
  cases(TypeVariant) tv:
    | t-variant(_, variant-fields, with-fields) => with-fields + variant-fields
    | t-singleton-variant(_, with-fields)       => with-fields
  end
end

data DataType:
  | t-datatype(name     :: String,
               params   :: List<Type>,
               variants :: List<TypeVariant>,
               fields   :: TypeMembers) with: # common (with-)fields, shared methods, etc
    lookup-variant(self, variant-name :: String) -> Option<TypeVariant>:
      fun same-name(tv):
        tv.name == variant-name
      end
      self.variants.find(same-name)
    end,
    introduce(self, args :: List<Type>) -> Option<DataType>:
      for fold2-strict(curr from self, arg from args, param from self.params):
        substitute = _.substitute(t-var(param.id), arg)
        t-datatype(curr.name, empty, curr.variants.map(substitute), curr.fields.map(substitute))
      end
    end
end

data ModuleType:
  | t-module(name :: String, provides :: Type, types :: SD.StringDict<DataType>, aliases :: SD.StringDict<Type>)
sharing:
  _output(self):
    VS.vs-constr("t-module",
      [list:
        VS.vs-value(torepr(self.name)),
        VS.vs-value(self.provides),
        VS.vs-value(dict-to-string(self.types)),
        VS.vs-value(dict-to-string(self.aliases))])
  end
end

fun interleave(lst, item):
  if is-empty(lst): lst
  else if is-empty(lst.rest): lst
  else: link(lst.first, link(item, interleave(lst.rest, item)))
  end
end

data Type:
  | t-name(module-name :: Option<String>, id :: Name)
  | t-var(id :: Name)
  | t-arrow(args :: List<Type>, ret :: Type)
  | t-app(onto :: Type % (is-t-name), args :: List<Type> % (is-link))
  | t-top
  | t-bot
  | t-record(fields :: TypeMembers)
  | t-forall(introduces :: List<Type>, onto :: Type)
  | t-ref(typ :: Type)
  | t-data(params :: List<Type>, variants :: List<TypeVariant>, fields :: TypeMembers, refine :: Option<String>) with:
    lookup-variant(self, variant-name :: String) -> Option<TypeVariant>:
      fun same-name(tv):
        tv.name == variant-name
      end
      self.variants.find(same-name)
    end,
  | t-data-construct(params :: List<Type>, args :: List<Type>, ret :: Type)
  | t-data-single-construct(params :: List<Type>, ret :: Type)
  | t-existential(id :: Name)
sharing:
  _output(self):
    cases(Type) self:
      | t-name(module-name, id) =>
        cases(Option<String>) module-name:
          | none    => VS.vs-value(id.toname())
          | some(m) => VS.vs-value(id.toname())
        end
      | t-var(id) => VS.vs-str(id.toname())
      | t-arrow(args, ret) =>
        VS.vs-seq([list: VS.vs-str("(")]
            + interleave(args.map(VS.vs-value), VS.vs-str(", "))
            + [list: VS.vs-str(" -> "), VS.vs-value(ret), VS.vs-str(")")])
      | t-app(onto, args) =>
        VS.vs-seq([list: VS.vs-value(onto), VS.vs-str("<")] + interleave(args.map(VS.vs-value), VS.vs-str(", "))
            + [list: VS.vs-str(">")])
      | t-top => VS.vs-str("Any")
      | t-bot => VS.vs-str("Bot")
      | t-record(fields) =>
        VS.vs-seq([list: VS.vs-str("{")]
            + interleave(fields.map(VS.vs-value), VS.vs-value(", "))
            + [list: VS.vs-str("}")])
      | t-forall(introduces, onto) =>
        VS.vs-value(onto)
      | t-ref(typ) =>
        VS.vs-seq([list: VS.vs-str("ref "), VS.vs-value(typ)])
      | t-data(params, variants, fields, refine) =>
        VS.vs-seq([list: VS.vs-str("(")]
            + interleave(variants.map(VS.vs-value), VS.vs-str(" + "))
            + [list: VS.vs-str(")")]
            + refine.and-then(lam(name):
              [list: VS.vs-str(": "), VS.vs-str(tostring(name))]
            end).or-else(empty))
      | t-data-construct(params, args, ret) =>
        VS.vs-seq([list: VS.vs-str("<")]
            + interleave(params.map(VS.vs-value), VS.vs-str(", "))
            + [list: VS.vs-str("> "), VS.vs-str("(")]
            + interleave(args.map(VS.vs-value), VS.vs-str(", "))
            + [list: VS.vs-str(")")]
            + [list: VS.vs-str(" -> "), VS.vs-value(ret)])
      | t-data-single-construct(params, ret) =>
        VS.vs-seq([list: VS.vs-str("<")]
            + interleave(params.map(VS.vs-value), VS.vs-str(", "))
            + [list: VS.vs-str("> ")]
            + [list: VS.vs-str(" -> "), VS.vs-value(ret)])
      | t-existential(id) => VS.vs-str(id.key())
    end
  end,
  key(self) -> String:
    cases(Type) self:
      | t-name(module-name, id) =>
        cases(Option<String>) module-name:
          | none    => id.key()
          | some(m) => m + "." + id.key()
        end
      | t-var(id) => id.key()
      | t-arrow(args, ret) =>
        "("
          + args.map(_.key()).join-str(", ")
          + " -> " + ret.key() + ")"
      | t-app(onto, args) =>
        onto.key() + "<" + args.map(_.key()).join-str(", ") + ">"
      | t-top => "Top"
      | t-bot => "Bot"
      | t-record(fields) =>
        "{"
          + for map(field from fields):
              field.key()
            end.join-str(", ")
          + "}"
      | t-forall(introduces, onto) =>
        "<" + introduces.map(_.key()).join-str(",") + ">"
          + onto.key()
      | t-ref(typ) =>
        "ref " + typ.key()
      | t-data(params, variants, fields, refine) =>
        "data" + "<" + params.map(_.key()).join-str(",") + ">"
          + variants.map(_.key()).join-str("+")
          + refine.and-then(lam(name):
              ": " + tostring(name)
            end).or-else("")
      | t-data-construct(params, args, ret) =>
        "constructor " + "<" + "<" + params.map(_.key()).join-str(",") + ">"
          + args.map(_.key()).join-str(", ")
          + " -> " + ret.key()
      | t-data-single-construct(params, ret) =>
        "constructor " + "<" + "<" + params.map(_.key()).join-str(",") + ">"
          + " -> " + ret.key()
      | t-existential(id) => id.key()
    end
  end,
  substitute(self, orig-typ :: Type, new-typ :: Type) -> Type:
    if self == orig-typ:
      new-typ
    else:
      cases(Type) self:
        | t-arrow(args, ret) =>
          new-args = args.map(_.substitute(orig-typ, new-typ))
          new-ret  = ret.substitute(orig-typ, new-typ)
          t-arrow(new-args, new-ret)
        | t-app(onto, args) =>
          new-onto = onto.substitute(orig-typ, new-typ)
          new-args = args.map(_.substitute(orig-typ, new-typ))
          t-app(new-onto, new-args)
        | t-forall(introduces, onto) =>
          new-onto = onto.substitute(orig-typ, new-typ)
          t-forall(introduces, new-onto)
        | t-ref(arg-typ) =>
          new-arg-typ = arg-typ.substitute(orig-typ, new-typ)
          t-ref(new-arg-typ)
        | t-data(params, variants, fields, refine) =>
          t-data(params,
                 variants.map(_.substitute(orig-typ, new-typ)),
                 fields.map(_.substitute(orig-typ, new-typ)),
                 refine)
        | t-data-construct(params, args, ret) =>
          t-data-construct(params,
                           args.map(_.substitute(orig-typ, new-typ)),
                           ret.substitute(orig-typ, new-typ))
        | t-data-single-construct(params, ret) =>
          t-data-construct(params, ret.substitute(orig-typ, new-typ))
        | else => self
      end
    end
  end,
  _lessthan(self, other :: Type) -> Boolean: self._comp(other) == less-than    end,
  _lessequal(self, other :: Type) -> Boolean: self._comp(other) <> greater-than end,
  _greaterthan(self, other :: Type) -> Boolean: self._comp(other) == greater-than end,
  _greaterequal(self, other :: Type) -> Boolean: self._comp(other) <> less-than    end,
  _equals(self, other :: Type, _) -> E.EqualityResult: E.from-boolean(self._comp(other) == equal) end,
  _comp(self, other :: Type) -> Comparison:
    cases(Type) self:
      | t-bot =>
        cases(Type) other:
          | t-bot => equal
          | else  => less-than
        end
      | t-name(a-module-name, a-id) =>
        cases(Type) other:
          | t-bot               => greater-than
          | t-name(b-module-name, b-id) =>
            fold-comparisons([list:
              std-compare(a-module-name.or-else(""), b-module-name.or-else("")),
              std-compare(a-id, b-id)
            ])
          | t-var(_)            => less-than
          | t-existential       => less-than
          | t-arrow(_, _)       => less-than
          | t-data-construct(_, _, _) => less-than
          | t-data-single-construct(_, _) => less-than
          | t-app(_, _)         => less-than
          | t-record(_)         => less-than
          | t-data(_, _, _, _)  => less-than
          | t-forall(_, _)      => less-than
          | t-ref(_)            => less-than
          | t-top               => less-than
        end
      | t-var(a-id) =>
        cases(Type) other:
          | t-bot               => greater-than
          | t-name(_, _)        => greater-than
          | t-existential(_)    => greater-than
          | t-var(b-id) =>
            if a-id < b-id: less-than
            else if a-id > b-id: greater-than
            else: equal;
          | t-arrow(_, _)       => less-than
          | t-data-construct(_, _, _) => less-than
          | t-data-single-construct(_, _) => less-than
          | t-app(_, _)         => less-than
          | t-record(_)         => less-than
          | t-data(_, _, _, _)  => less-than
          | t-forall(_, _)      => less-than
          | t-ref(_)            => less-than
          | t-top               => less-than
        end
      | t-arrow(a-args, a-ret) =>
        cases(Type) other:
          | t-bot               => greater-than
          | t-name(_, _)        => greater-than
          | t-var(_)            => greater-than
          | t-existential(_)    => greater-than
          | t-arrow(b-args, b-ret) =>
            fold-comparisons([list:
              list-compare(a-args, b-args),
              a-ret._comp(b-ret)
            ])
          | t-data-construct(_, _, _) => less-than
          | t-data-single-construct(_, _) => less-than
          | t-app(_, _)         => less-than
          | t-record(_)         => less-than
          | t-data(_, _, _, _)  => less-than
          | t-forall(_, _)      => less-than
          | t-ref(_)            => less-than
          | t-top               => less-than
        end
      | t-data-construct(a-params, a-args, a-ret) =>
        cases(Type) other:
          | t-bot               => greater-than
          | t-name(_, _)        => greater-than
          | t-var(_)            => greater-than
          | t-existential(_)    => greater-than
          | t-arrow(b-args, b-ret) => greater-than
          | t-data-construct(b-params, b-args, b-ret) =>
            fold-comparisons([list:
              list-compare(a-params, b-params),
              list-compare(a-args, b-args),
              a-ret._comp(b-ret)])
          | t-data-single-construct(_, _) => less-than
          | t-app(_, _)         => less-than
          | t-record(_)         => less-than
          | t-data(_, _, _, _)  => less-than
          | t-forall(_, _)      => less-than
          | t-ref(_)            => less-than
          | t-top               => less-than
        end
      | t-data-single-construct(a-params, a-ret) =>
        cases(Type) other:
          | t-bot               => greater-than
          | t-name(_, _)        => greater-than
          | t-var(_)            => greater-than
          | t-existential(_)    => greater-than
          | t-arrow(b-args, b-ret) => greater-than
          | t-data-construct(_, _, _) => greater-than
          | t-data-single-construct(b-params, b-ret) =>
            fold-comparisons([list:
              list-compare(a-params, b-params),
              a-ret._comp(b-ret)])
          | t-app(_, _)         => less-than
          | t-record(_)         => less-than
          | t-data(_, _, _, _)  => less-than
          | t-forall(_, _)      => less-than
          | t-ref(_)            => less-than
          | t-top               => less-than
        end
      | t-app(a-onto, a-args) =>
        cases(Type) other:
          | t-bot               => greater-than
          | t-name(_, _)        => greater-than
          | t-var(_)            => greater-than
          | t-existential(_)    => greater-than
          | t-arrow(_, _)       => greater-than
          | t-data-construct(_, _, _) => greater-than
          | t-data-single-construct(_, _) => greater-than
          | t-app(b-onto, b-args) =>
            fold-comparisons([list:
              list-compare(a-args, b-args),
              a-onto._comp(b-onto)
            ])
          | t-record(_)         => less-than
          | t-data(_, _, _, _)  => less-than
          | t-forall(_, _)      => less-than
          | t-ref(_)            => less-than
          | t-top               => less-than
        end
      | t-record(a-fields) =>
        cases(Type) other:
          | t-bot               => greater-than
          | t-name(_, _)        => greater-than
          | t-var(_)            => greater-than
          | t-existential(_)    => greater-than
          | t-arrow(_, _)       => greater-than
          | t-data-construct(_, _, _) => greater-than
          | t-data-single-construct(_, _) => greater-than
          | t-app(_, _)         => greater-than
          | t-record(b-fields)  =>
            list-compare(a-fields, b-fields)
          | t-data(_, _, _, _)  => less-than
          | t-forall(_, _)      => less-than
          | t-ref(_)            => less-than
          | t-top               => less-than
        end
      | t-data(a-params, a-variants, a-fields, _) =>
        cases(Type) other:
          | t-bot               => greater-than
          | t-name(_, _)        => greater-than
          | t-var(_)            => greater-than
          | t-existential(_)    => greater-than
          | t-arrow(_, _)       => greater-than
          | t-data-construct(_, _, _) => greater-than
          | t-data-single-construct(_, _) => greater-than
          | t-app(_, _)         => greater-than
          | t-record(b-fields)  => greater-than
          | t-data(_, _, b-fields, _) =>
            list-compare(a-fields, b-fields)
          | t-forall(_, _)      => less-than
          | t-ref(_)            => less-than
          | t-top               => less-than
        end
      | t-forall(a-introduces, a-onto) =>
        cases(Type) other:
          | t-bot               => greater-than
          | t-name(_, _)        => greater-than
          | t-var(_)            => greater-than
          | t-existential(_)    => greater-than
          | t-arrow(_, _)       => greater-than
          | t-data-construct(_, _, _) => greater-than
          | t-data-single-construct(_, _) => greater-than
          | t-app(_, _)         => greater-than
          | t-record(_)         => greater-than
          | t-data(_, _, _, _)  => greater-than
          | t-forall(b-introduces, b-onto) =>
            fold-comparisons([list:
              list-compare(a-introduces, b-introduces),
              a-onto._comp(b-onto)
            ])
          | t-ref(_)            => less-than
          | t-top               => less-than
        end
      | t-ref(a-typ) =>
        cases(Type) other:
          | t-bot               => greater-than
          | t-name(_, _)        => greater-than
          | t-var(_)            => greater-than
          | t-existential(_)    => greater-than
          | t-arrow(_, _)       => greater-than
          | t-data-construct(_, _, _) => greater-than
          | t-data-single-construct(_, _) => greater-than
          | t-app(_, _)         => greater-than
          | t-record(_)         => greater-than
          | t-data(_, _, _, _)  => greater-than
          | t-forall(_, _)      => greater-than
          | t-ref(b-typ)        =>
            a-typ._comp(b-typ)
          | t-top               => less-than
        end
      | t-existential(a-id) =>
        cases(Type) other:
          | t-bot               => greater-than
          | t-name(_, _)        => greater-than
          | t-var(_)            => less-than
          | t-existential(b-id) =>
            if a-id < b-id: less-than
            else if a-id > b-id: greater-than
            else: equal;
          | t-arrow(_, _)       => less-than
          | t-data-construct(_, _, _) => less-than
          | t-data-single-construct(_, _) => less-than
          | t-app(_, _)         => less-than
          | t-record(_)         => less-than
          | t-data(_, _, _, _)  => less-than
          | t-forall(_, _)      => less-than
          | t-ref(_)            => less-than
          | t-top               => less-than
        end
      | t-top =>
        cases(Type) other:
          | t-top => equal
          | else  => greater-than
        end
    end
  end
end

builtin-uri = some("builtin")

t-array-name = t-name(none, A.s-type-global("RawArray"))

t-number  = t-name(builtin-uri, A.s-type-global("Number"))
t-string  = t-name(builtin-uri, A.s-type-global("String"))
t-boolean = t-name(builtin-uri, A.s-type-global("Boolean"))
t-nothing = t-name(builtin-uri, A.s-type-global("Nothing"))
t-srcloc  = t-name(builtin-uri, A.s-global("Loc"))
t-array   = lam(v): t-app(t-array-name, [list: v]);
t-option  = lam(v): t-app(t-name(some("pyret-builtin://option"), A.s-global("Option")), [list: v]);
