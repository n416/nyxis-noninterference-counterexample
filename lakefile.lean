import Lake
open Lake DSL

-- 反例(PoC)用の独立したプロジェクト。nyxis の純粋部分(`import Nyxis`。接続コード `Nyxis.Internal.*` は含まない)と
-- 公式サンプル team-docs のアプリ本体を、元のソースのまま参照する。PostgreSQL・JWT・libpq は不要。
package nyxisPoc

require Cedar from git "https://github.com/cedar-policy/cedar-spec" @
  "6d7fb269d5eec6ce4ae1d4aff9794feba0c0d5a9" / "cedar-lean"

lean_lib Nyxis where
  srcDir := ".."
  roots := #[`Nyxis]
  globs := #[.one `Nyxis, .one `Nyxis.Db, .one `Nyxis.Materials, .one `Nyxis.Authz, .one `Nyxis.Handler,
    .one `Nyxis.Runtime, .one `Nyxis.Approved, .one `Nyxis.Http, .one `Nyxis.CedarLex, .one `Nyxis.CedarSchema,
    .one `Nyxis.CedarPolicy, .one `Nyxis.Build]

lean_lib TeamDocs where
  srcDir := "../examples/team-docs/backend"
  roots := #[`TeamDocs.App]
  globs := #[.one `TeamDocs.Approved, .one `TeamDocs.Handlers, .one `TeamDocs.Jobs, .one `TeamDocs.App]

@[default_target]
lean_lib Poc
