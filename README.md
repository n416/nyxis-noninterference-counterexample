# Nyxis: 認可安全性が成り立ったまま、読めない値が漏れる反例

Nyxis の公式サンプル team-docs(元のソースのまま)を、ランタイムの純粋モデル上で動かす Lean の PoC。

- `Org.name` は `@unique`、組織を読めるのはメンバーだけ、組織の作成は誰でも可。
- 部外者が `POST /orgs {"name": "<推測>"}` を送ると、その名前の組織があれば 409、無ければ 201。
- 違いが「部外者が読めない 1 行の 1 列」だけの 2 つの DB で、同じ要求への応答が異なることを証明する(`Poc.leak`)。
- 主定理 `Nyxis.Runtime.authorization_safety` はこの実行でも成り立つ。定理は「permit されない DB 操作が発行されない」
  ことを述べるが、非干渉(読めない値が応答に影響しないこと)は述べないため。

## 実行

Nyxis のチェックアウトの直下に `poc/` として置き、Lean(elan)を入れて:

```
cd poc
lake update
lake build
```

PostgreSQL・JWT・libpq は不要(`import Nyxis` は接続コード `Nyxis.Internal.*` を含まない)。
定理は `native_decide` で検査する(リポジトリ自身の `#guard` のテストと同じく、コンパイラを信頼する)。
