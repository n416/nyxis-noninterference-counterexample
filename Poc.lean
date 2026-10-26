import TeamDocs.App

/-!
# Poc — 「認可安全性」が成り立ったまま、読めない行の値が漏れる反例

対象は nyxis の公式サンプル team-docs(`TeamDocs.app`。正本 `schema.cedarschema` / `policies.cedar` とハンドラを
元のソースのまま使う)で、ランタイムの純粋モデル `Nyxis.Runtime.handleRequest` の上で動かす。

正本の宣言:
- `Org` は `@unique("name")`(組織名は一意)。
- 組織の行を読めるのは owner と所属する利用者だけ(`read-org-as-member`)。
- 組織の作成 `createOrg` は、自分だけを owner にするなら誰でも permit される(`create-org`)。

攻撃: 部外者 `outsider` が `POST /orgs {"name": "<推測した名前>"}` を送る。その名前の組織があれば 409(conflict)、
無ければ 201。部外者は対象の組織を読めない(403)が、応答の状態コードから組織名(読めない行の列の値)が推測どおりか
どうかを知る。推測を繰り返せば辞書攻撃になる。

主定理 `Nyxis.Runtime.authorization_safety` はこの実行についても成り立つ(下の `safety_still_holds`)。定理が述べるのは
「permit されない DB 操作は発行されない」ことで、「permit されない行の値が応答に影響しない」(非干渉)ではないため。
-/

namespace Poc

open Cedar.Spec
open Cedar.Data
open Nyxis
open Nyxis.Db
open Nyxis.Authz
open Nyxis.Runtime

def app : App := _root_.TeamDocs.app

def userT : EntityType := ⟨"User", []⟩
def orgT : EntityType := ⟨"Org", []⟩
def teamT : EntityType := ⟨"Team", []⟩
def user (id : String) : EntityUID := ⟨userT, id⟩
def org (id : String) : EntityUID := ⟨orgT, id⟩
def team (o role : String) : EntityUID := ⟨teamT, o ++ "/" ++ role ++ "s"⟩

def uidV (u : EntityUID) : Value := .prim (.entityUID u)
def strV (s : String) : Value := .prim (.string s)
def setV (vs : List Value) : Value := .set (Set.make vs)
def row (kvs : List (Attr × Value)) : Row := Map.make kvs

def gen : Generated := { now := ⟨1767225600000⟩, id := "generated-id" }

def owner : Principal := .user (user "owner")
def outsider : Principal := .user (user "outsider")

def orgRow (o name : String) (owners : List String) : Row :=
  row [ ("name", strV name), ("owners", setV (owners.map (uidV ∘ user)))
      , ("editors", uidV (team o "editor")), ("viewers", uidV (team o "viewer")) ]

def teamRow (o role : String) : Row := row [("org", uidV (org o)), ("role", strV role)]

/-- owner だけが属する組織 `falcon`。その名前 `name` だけを変えた DB の状態を作る。outsider はどの組にも属さない。 -/
def storeNamed (name : String) : Store := Map.make
  [ (user "owner", row [("name", strV "Owner")]), (user "outsider", row [("name", strV "Outsider")])
  , (org "falcon", orgRow "falcon" name ["owner"])
  , (team "falcon" "editor", teamRow "falcon" "editor"), (team "falcon" "viewer", teamRow "falcon" "viewer") ]

/-- 秘密の名前を持つ世界と、無害な名前を持つ世界。違いは outsider が読めない 1 行の 1 列だけ。 -/
def secretWorld : Store := storeNamed "Project-Falcon-Acquisition"
def harmlessWorld : Store := storeNamed "Bake-Sale"

def req (p : Principal) (method : Std.Http.Method) (path : String) (body : String := "") : AuthenticatedRequest :=
  { principal := p, generated := gen, request := { method := method, path := path, body := body, query := "" } }

def status (s : Store) (r : AuthenticatedRequest) : UInt16 := (handleRequest app s r).result.status.toCode
def body (s : Store) (r : AuthenticatedRequest) : String := (handleRequest app s r).result.body

/-- 組織名の推測を 1 回試す要求。 -/
def probe (guess : String) : AuthenticatedRequest :=
  req outsider .post "/orgs" ("{\"name\":\"" ++ guess ++ "\"}")

/-! ## 1. outsider は falcon を読めない(どちらの世界でも同じに見える) -/

/-- 直接の読み取りはどちらの世界でも 403 で、DB 操作は 1 つも発行されない。 -/
theorem outsider_cannot_read :
    status secretWorld (req outsider .get "/orgs/falcon") = 403
    ∧ status harmlessWorld (req outsider .get "/orgs/falcon") = 403
    ∧ (handleRequest app secretWorld (req outsider .get "/orgs/falcon")).issued = []
    ∧ (handleRequest app harmlessWorld (req outsider .get "/orgs/falcon")).issued = [] := by
  native_decide

/-- 一覧でも falcon は見えず、2 つの世界の応答は一字一句同じ。 -/
theorem outsider_list_identical :
    body secretWorld (req outsider .get "/orgs") = body harmlessWorld (req outsider .get "/orgs")
    ∧ body secretWorld (req outsider .get "/orgs") = "{\"rows\":[],\"total\":0}" := by
  native_decide

/-! ## 2. それでも 1 回の要求で 2 つの世界を区別できる -/

/-- 推測 "Project-Falcon-Acquisition" は、秘密の世界では 409、無害な世界では 201。 -/
theorem probe_distinguishes :
    status secretWorld (probe "Project-Falcon-Acquisition") = 409
    ∧ status harmlessWorld (probe "Project-Falcon-Acquisition") = 201 := by
  native_decide

/-- **非干渉の破れ**: outsider が読めない 1 行の 1 列の値だけが違う 2 つの状態について、同じ outsider の同じ要求への
    応答が異なる。すなわち、読めないはずの値が応答に流れている。 -/
theorem leak :
    ∃ s₁ s₂ : Store, ∃ r : AuthenticatedRequest,
      r.principal = outsider
      ∧ status s₁ (req outsider .get "/orgs/falcon") = 403
      ∧ status s₂ (req outsider .get "/orgs/falcon") = 403
      ∧ status s₁ r ≠ status s₂ r :=
  ⟨secretWorld, harmlessWorld, probe "Project-Falcon-Acquisition", rfl,
    outsider_cannot_read.1, outsider_cannot_read.2.1,
    by rw [probe_distinguishes.1, probe_distinguishes.2]; decide⟩

/-! ## 3. この実行でも主定理はそのまま成り立つ(定理は破れていない。主張が漏洩を捉えていない) -/

example := Nyxis.Runtime.authorization_safety app secretWorld [probe "Project-Falcon-Acquisition"]

/-! ## 4. 辞書攻撃: 候補を順に試すと、読めない組織名が当たる -/

def candidates : List String :=
  ["Project-Eagle", "Project-Hawk", "Project-Falcon", "Project-Falcon-Acquisition", "Project-Falcon-IPO"]

/-- 409 が返った候補 = 実在する(outsider が読めない)組織の名前。 -/
def guessed (s : Store) : List String := candidates.filter fun g => status s (probe g) == 409

#eval guessed secretWorld    -- ["Project-Falcon-Acquisition"]
#eval guessed harmlessWorld  -- []

theorem dictionary_attack : guessed secretWorld = ["Project-Falcon-Acquisition"] := by native_decide

end Poc

#print axioms Poc.leak
