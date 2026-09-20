# Search backup Blob upload

`index-backup-restore` でローカルに保存した Azure AI Search のバックアップ一式を、AzCopy で Azure Blob Storage のコンテナへ一括アップロードする補助ツールです。既存のバックアップ・復元ツールのコードや設定は変更しません。

## 必要なもの

- Windows / PowerShell 5.1 以降
- ローカルのバックアップフォルダ
- アップロード先コンテナへの書き込み・作成に必要な権限と有効期限を持つ Container SAS URL
- 初回ダウンロードと Blob Storage へのネットワーク接続

初回実行時に AzCopy がなければ、[Microsoft のダウンロード URL](https://aka.ms/downloadazcopy-v10-windows) から取得し、このツール内の `.tools/azcopy/` に展開します。次回以降は `.tools/azcopy/azcopy.exe` を再利用し、再ダウンロードしません。PATH への登録は不要です。

## 使用方法

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

## 動作

以下に相当する処理でサブフォルダを含めてアップロードします。

```text
azcopy.exe copy "<SourcePath>" "<Container SAS URL>" --recursive=true
```

コピー元フォルダ自体もアップロード対象です。例えば `D:\SearchBackup\index-products\index-products.schema` は、コンテナ内の `SearchBackup/index-products/index-products.schema` に保存されます。既存 Blob が同じパスにある場合は AzCopy の既定動作で上書きされます。ローカルの元ファイルは削除しません。

Source ディレクトリ、AzCopy の場所、開始・成功・失敗を表示します。SAS URL の露出を避けるため、AzCopy の標準出力・標準エラーを表示せず、`--output-level=quiet --log-level=NONE` を指定します。SAS URL は AzCopy に渡すため実行中のプロセス引数には含まれます。

成功時は終了コード `0`、AzCopy が失敗した場合はその終了コード、入力・ダウンロードなどの失敗時は `1` を返します。失敗時は保存先フォルダ、ネットワーク、SAS の権限・有効期限を確認してください。

`.tools/` はこのフォルダの `.gitignore` により Git の管理対象外です。

参考：[AzCopy によるアップロード](https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-blobs-upload)、[AzCopy copy オプション](https://github.com/Azure/azure-storage-azcopy/wiki/azcopy_copy)。
