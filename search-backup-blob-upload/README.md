# Search backup Blob upload / download

`index-backup-restore` でローカルに保存した Azure AI Search のバックアップ一式を、AzCopy で Azure Blob Storage のコンテナへ一括アップロードする補助ツールです。既存のバックアップ・復元ツールのコードや設定は変更しません。

`download.ps1` では、コンテナ内のファイル一式をローカルへ一括ダウンロードできます。

## 必要なもの

- Windows / PowerShell 5.1 以降
- アップロード時：ローカルのバックアップフォルダと、コンテナへの書き込み・作成に必要な権限と有効期限を持つ Container SAS URL
- ダウンロード時：コンテナへの読み取り・一覧取得（Read / List）権限と有効期限を持つ Container SAS URL
- 初回ダウンロードと Blob Storage へのネットワーク接続

初回実行時に AzCopy がなければ、[Microsoft のダウンロード URL](https://aka.ms/downloadazcopy-v10-windows) から取得し、このツール内の `.tools/azcopy/` に展開します。次回以降は `.tools/azcopy/azcopy.exe` を再利用し、再ダウンロードしません。PATH への登録は不要です。

## アップロード方法

PowerShell でこのフォルダに移動して実行します。

```powershell
cd .\search-backup-blob-upload
.\upload.ps1
```

デフォルトのアップロード元は `$env:USERPROFILE\Desktop\SearchBackup` です。変更する場合：

```powershell
.\upload.ps1 -SourcePath "D:\SearchBackup"
```

実行中に Container SAS URL の入力を求めます。`Read-Host -AsSecureString` を使用するため、入力内容は画面に表示されません。SAS URL はソースコードや設定ファイルへ保存しません。**SAS URL を Git へコミットしないでください。**

必要な場合は `-SasUrl` 引数でも渡せますが、直接記述すると PowerShell のコマンド履歴に残る可能性があるため、通常は非表示の対話入力を使用してください。

## アップロードの動作

以下に相当する処理でサブフォルダを含めてアップロードします。

```text
azcopy.exe copy "<SourcePath>" "<Container SAS URL>" --recursive=true
```

コピー元フォルダ自体もアップロード対象です。例えば `D:\SearchBackup\index-products\index-products.schema` は、コンテナ内の `SearchBackup/index-products/index-products.schema` に保存されます。既存 Blob が同じパスにある場合は AzCopy の既定動作で上書きされます。ローカルの元ファイルは削除しません。

Source ディレクトリ、AzCopy の場所、開始・成功・失敗を表示します。SAS URL の露出を避けるため、AzCopy の標準出力・標準エラーを表示せず、`--output-level=quiet --log-level=NONE` を指定します。SAS URL は AzCopy に渡すため実行中のプロセス引数には含まれます。

成功時は終了コード `0`、AzCopy が失敗した場合はその終了コード、入力・ダウンロードなどの失敗時は `1` を返します。失敗時は保存先フォルダ、ネットワーク、SAS の権限・有効期限を確認してください。

`.tools/` はこのフォルダの `.gitignore` により Git の管理対象外です。

## ダウンロード方法

このフォルダで実行します。

```powershell
.\download.ps1
```

保存先の既定値は `$env:USERPROFILE\Desktop\SearchBackupDownload` です。存在しない保存先フォルダは自動作成します。変更する場合：

```powershell
.\download.ps1 -DestinationPath "D:\SearchBackupDownload"
```

取得元の Storage アカウント・コンテナは、実行時に入力する Container SAS URL で決まります。upload と同様に非表示で入力し、ソースコードや設定ファイルに保存しません。`-SasUrl` 引数でも指定できますが、通常はコマンド履歴に残らない対話入力を使用してください。SAS URL を Git へコミットしないでください。

AzCopy は upload と同じ `.tools/azcopy/azcopy.exe` を再利用します。ダウンロードから使い始めた場合も、AzCopy がなければ自動取得します。

以下に相当する処理で、コンテナ内の全ファイルを階層ごとダウンロードします。

```text
azcopy.exe copy "<Container SAS URL>" "<DestinationPath>" --recursive=true --as-subdir=false
```

`--as-subdir=false` によりコンテナ名のフォルダは追加せず、コンテナ内の階層を保存先直下に維持します。例えば upload で保存したファイルは次の場所に入ります。

```text
D:\SearchBackupDownload\
└── SearchBackup\
    ├── index-products\
    │   ├── index-products.schema
    │   └── index-products1.json
    └── index-orders\
        ├── index-orders.schema
        └── index-orders1.json
```

この例を `index-backup-restore` で復元するときは、`BackupDirectory` に `D:\SearchBackupDownload\SearchBackup` を指定します。コンテナに別のファイルがあれば、それらも取得します。ダウンロードだけでは Azure AI Search への復元は実行しません。

同じパスのローカルファイルは AzCopy の既定動作で上書きされます。Blob Storage 側のファイルや、転送対象にないローカルファイルは削除しません。

保存先、AzCopy の場所、Download 開始・成功・失敗を表示します。upload と同様に AzCopy の標準出力・標準エラーを非表示にし、ログ出力も無効にします。SAS URL は実行中のプロセス引数には含まれます。成功時は終了コード `0`、AzCopy の失敗時はその終了コード、入力・自動取得などの失敗時は `1` です。

参考：[AzCopy によるアップロード](https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-blobs-upload)、[AzCopy によるダウンロード](https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-blobs-download)、[AzCopy copy オプション](https://github.com/Azure/azure-storage-azcopy/wiki/azcopy_copy)。
