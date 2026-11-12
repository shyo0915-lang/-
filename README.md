# 顧客マップ（営業向け MVP）

外回りの営業が、地図上のピンで担当顧客を見て、契約書を撮ると顧客を登録できる社内アプリです。顧客DBは外部CRMではなく、Supabase（Postgres）上の自社データです。管理画面は同じデータベースと RLS を使う Web CRM です。画面の文言は日本語です。

## できること

- 地図に顧客ピンを表示する。色と形が契約ステータス、大きさが単価（1回）の帯。近いピンはクラスタになる
- ピンをタップするとボトムシート（ピーク / ハーフ / 全画面）が開く。名前、電話、住所、メモの抜粋、契約日、単価（1回）、電話とナビ
- 全画面で顧客名・住所・電話・契約日・単価・ステータス・メモを検証して保存する。住所が変わると再ジオコーディングしてピンを動かす
- 右下のカメラから契約書を撮影または選択し、端末内 OCR（ML Kit 日本語）で5項目を埋める。信頼度が低い項目は確認するまで保存できない
- 定型書式（見出し、または `FMT:CONTRACT-V1`）は端末内。手書きはオンラインならクラウド OCR（差し替え可能なインターフェース）、オフラインなら端末内の結果を使い、復帰後にクラウドへ回す前提
- ステータス（初期4つ＋追加、最大10、色と形の重複禁止）と単価帯（2〜5段階）を設定できる
- 顧客は担当者だけが見える。招待（閲覧者 / 編集者）と管理者は会社全体を見られる
- オフラインでは、スマホアプリは端末の SQLite、ブラウザ版は IndexedDB に入力・ピン・写真を置き、復帰後に同期する。同じ項目の競合は比較画面に出す
- Web CRM で一覧（検索、ステータス、単価帯、担当）、詳細編集、メモ、契約書画像、共有、ステータス、単価帯、CSV 入出力

## オフライン同期に PowerSync を使っていない理由

仕様の推奨は PowerSync です。MVP では入れていません。PowerSync は別サービス（無料枠でもプロジェクト作成、同期ルール、1週間未使用で停止）が必要で、鍵が無い状態では動かせないためです。代わりに次の構成にしています。

- 端末: `sqflite` に顧客・ステータス・送信キューを保存
- 契約書画像: カメラロールには残さず、アプリ専用領域に AES で保存（鍵は端末内の共有設定。本番ではハードウェア鍵に置き換える）
- 通信復帰: キューを Supabase に書き、`version` が食い違ったら項目ごとにマージし、同じ項目は `sync_conflicts` に残す
- 手動で置いたピン（`location_source = manual`）は、後から住所変換が成功しても自動では上書きしない

本番で同時接続が増えたら、同じテーブルのまま PowerSync に載せ替えられます。

## ディレクトリ

| 場所 | 内容 |
| --- | --- |
| `app/` | Flutter（iOS / Android） |
| `web-admin/` | 管理用の静的 Web CRM |
| `supabase/migrations/` | テーブル、RLS、Storage |
| `supabase/seed.sql` | ローカル開発用の架空データ |
| `supabase/functions/` | ジオコーディング、OCR、共有、担当替え |
| `supabase/tests/` | RLS の SQL テスト |

## iPhoneのSafariだけで使う

公開ページは次のアドレスです。鍵が無くても、架空の顧客が入ったサンプルで開きます。

`https://shyo0915-lang.github.io/-/`

管理画面は `https://shyo0915-lang.github.io/-/admin/` です。

ホーム画面に置くときは、Safariの共有ボタンから「ホーム画面に追加」を選びます。地図の右上の一覧ボタンから管理画面へ移れます。

GitHubの公開設定は、リポジトリの Settings → Pages です。Source を **GitHub Actions** にすると、`main` に入った更新が公式の Pages として出ます。この作業ブランチの更新をマージ前に見るには、同じ画面で Source を **Deploy from a branch**、Branch を **gh-pages**、フォルダを **/ (root)** にして Save します。ワークフローはこのブランチへ push するたびに `gh-pages` を更新します。

## 鍵が無くても動く範囲

`SUPABASE_URL` と `SUPABASE_ANON_KEY` が空のときは、アプリは架空のサンプル顧客で起動します。地図キーが空のときは Google マップの代わりに簡易地図を出します。ジオコーディングキーが空のときは、住所から座標を得られず、地図の長押しでピンを置きます。

Web CRM も `web-admin/config.js` が空、または無いときはブラウザ内のサンプルデータで一覧・編集・CSV・共有を試せます。

## Supabase

1. [Supabase](https://supabase.com) で無料プロジェクトを作る
2. SQL Editor で `supabase/migrations/20261110120000_init.sql` を実行する
3. ローカル CLI を使う場合は `supabase start` のあと `supabase db reset`（`supabase/config.toml` と `seed.sql`）
4. Authentication でメール登録を有効にする。開発中は「Confirm email」を切るとすぐログインできる
5. アプリまたは管理画面からサインアップする。会社名が同じ最初のユーザーが管理者、次のユーザーは担当者になる
6. ローカル seed が成功した場合のデモアカウント（本番では使わない）
   - 管理者 `taro@example.com` / `password123`
   - 担当者 `hanako@example.com` / `password123`

`seed.sql` は Supabase の `auth.users` の列に依存します。失敗した場合はアプリの登録画面を使ってください。顧客は架空の住所です。

### データと RLS

主なテーブルは `organizations`、`profiles`、`statuses`、`price_tiers`、`customers`（`memo` は nullable の text）、`contracts`、`contract_images`、`customer_shares`、`sync_conflicts`、`audit_log` です。

- 担当者は自分の顧客だけを閲覧・編集できる
- 期限内の共有に入っている閲覧者は読める。編集者は更新できるが、共有の作成とアーカイブはできない
- 管理者は同じ会社の顧客を閲覧・編集でき、`reassign_customer` で担当を付け替えられる
- 物理削除はできない。担当者だけが `deleted_at` を入れる
- 初期ステータスの名前・色・形の変更は管理者。追加ステータスは担当者も作れる
- 会社の単価帯は管理者、個人の単価帯は本人

仕様書では管理者は顧客の中身を見ずに担当だけ付け替える想定でした。依頼された管理画面（一覧・検索・編集・CSV）が成立するよう、管理者は同一会社の顧客を閲覧・編集できます。この点は仕様より広いです。

契約書画像のバケットは非公開の `contract-images` です。パスは `{組織ID}/{顧客ID}/{契約ID}/{ページ}`。読み取りは `can_view`、書き込みは `can_edit`、1ファイル 10MB、JPEG / PNG / PDF です。

Edge Functions（`geocode` / `ocr` / `share` / `reassign`）は任意です。ジオコーディングとクラウド OCR の鍵はサーバー側のシークレットに置きます。未設定なら 501 を返し、アプリは手動ピンと端末内 OCR に落ちます。クラウド OCR は `CLOUD_OCR_URL` へ画像を渡すだけなので、Document AI などに差し替えられます。

## Google Maps

地図の表示キーと、ジオコーディング用のキーを分けられます。両方空でもアプリは起動します。

1. Google Cloud で Maps SDK for Android、Maps SDK for iOS、Geocoding API、必要なら Places API を有効にする
2. キーはアプリに埋め込まず、次のどちらかで渡す

```bash
cd app
flutter run \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=xxxx \
  --dart-define=MAPS_API_KEY=xxxx \
  --dart-define=GEOCODING_API_KEY=xxxx
```

または `config/dart_defines.example.json` を `config/dart_defines.json` にコピーして値を入れ、`flutter run --dart-define-from-file=../config/dart_defines.json`。

Android の地図キーは、加えて `app/android/local.properties` に `MAPS_API_KEY=xxxx` を書きます（gitignore 済み）。iOS は `app/ios/Runner/AppDelegate.swift` で、キーがあるときだけ次を呼びます。

```swift
import GoogleMaps
GMSServices.provideAPIKey("キー")
```

空のままなら簡易地図を使います。`Info.plist` の `GMSApiKey` はプレースホルダです。

## アプリの起動

```bash
cd app
flutter pub get
flutter analyze
flutter test
flutter run
```

対象は iOS と Android です。Linux デスクトップは対象外です。`flutter test` は OCR の項目抽出（電話、和暦を含む日付、金額、住所）、入力検証、同期マージ、CSV、クラスタを実行します。

RLS のテストは Postgres があれば次で実行できます。

```bash
bash supabase/tests/run_local.sh
```

## Web CRM

```bash
cd web-admin
cp config.example.js config.js   # URL と anon key を入れる。空ならサンプルモード
python3 -m http.server 8080
```

ブラウザで `http://localhost:8080` を開きます。顧客の検索（メモを含む）、ステータス・単価帯・担当の絞り込み、詳細編集、画像、招待、CSV 入出力が使えます。

## まだ手作業や鍵が要るもの

- Supabase プロジェクトの作成とマイグレーションの適用
- Google Maps / Geocoding / Places の API キーと、Android のアプリ制限・iOS のバンドル ID 制限
- クラウド OCR のプロバイダ URL と鍵（未設定でも定型の端末内 OCR は動く）
- 実機のカメラ、位置情報、電話、ナビは OS の権限ダイアログが出る
- 書類の自動エッジ検出・台形補正は未実装（撮影と写真選択、品質が小さすぎるときの注意まで）
- 招待のプッシュ通知、生体認証ロック、SQLCipher、地図の事前ダウンロードは未実装
- 管理画面は Flutter Web ではなく、同じ Supabase を叩く静的ページ

## テスト

```bash
cd app && flutter analyze && flutter test
bash supabase/tests/run_local.sh
```
