# 配布前の確認

GitHub公開用のZIPはアドホック署名です。このMacにインストールする開発版は別途Apple Development証明書で署名しています。一般公開用のDeveloper ID署名とAppleの公証はまだ行っていません。

## 署名・公証

Xcode 26以降、Developer ID Application証明書、およびKeychainに保存したnotarytoolプロファイルを用意します。公開時に使用する固定のBundle IDを選び、その後は変更しないでください。開発版のIDは権限との互換性のため旧名を保持しています。

```sh
export ALTWINDOW_SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)'
export ALTWINDOW_NOTARY_PROFILE='YOUR_KEYCHAIN_PROFILE'
export ALTWINDOW_BUNDLE_ID='YOUR_PUBLISHER_BUNDLE_IDENTIFIER'
bash Tools/release.sh
```

このコマンドはAppleへビルドを送信します。Hardened Runtime付きの署名、公証、チケット添付、Gatekeeper検証後にZIPとSHA-256を生成します。秘密情報をソースや環境ファイルへコミットしないでください。手順は[Appleの公証ドキュメント](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)に沿っています。

## 検証状況と残作業

- 自動テストとメモリ実測は `PERFORMANCE.md` を参照。
- 現在のビルド・実機検証はApple Silicon／macOS 27.0.1で実施。
- 最小対応macOS 14/15のぼかし表示、macOS 26のLiquid Glass、Intel Mac、複数ディスプレイ、Spacesをまたぐ切り替えは配布前に各実機で確認が必要。
- 新しい署名のビルドで、アクセシビリティ・入力監視・画面収録の初回許可、取り消し、再許可を確認。
- Chromeの通常／最小化ウィンドウ、同一タイトルの複数ウィンドウ、終了直後のウィンドウ、フルスクリーンで切り替えを確認。
- 公証後のZIPを別のMacへダウンロードし、Gatekeeperの標準設定で起動することを確認。
- ライセンスはMIT、公開先はjiig6tyg1/AltWindow。問い合わせはGitHub Issues。

この確認が終わるまでは、未検証のOS・構成を「動作確認済み」として案内しないでください。
