cask "altwindow" do
  version "1.00"
  sha256 "cb7389c815a0beada200b84154adf9fffb7ddfe0076dc95966537dc7541337c9"

  url "https://github.com/jiig6tyg1/AltWindow/releases/download/v#{version}/AltWindow-#{version}-macOS-arm64.zip"
  name "AltWindow"
  desc "Windows-style per-window switcher for macOS"
  homepage "https://github.com/jiig6tyg1/AltWindow"

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  app "AltWindow.app"

  caveats <<~EOS
    This build is ad-hoc signed and not notarized by Apple.
    macOS may block it from opening. Accessibility and Input Monitoring
    permissions are required for switching; Screen Recording is optional
    for previews. Updates may require re-granting permissions.
  EOS
end
