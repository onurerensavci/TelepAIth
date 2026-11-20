# Homebrew ile kurulum:
#   brew tap onurerensavci/telepaith https://github.com/onurerensavci/TelepAIth
#   brew install --cask telepaith
# Uygulama kendini güncellediği için sürüm sabitlenmez (her zaman son sürüm indirilir).
cask "telepaith" do
  version :latest
  sha256 :no_check

  url "https://github.com/onurerensavci/TelepAIth/releases/latest/download/TelepAIth.zip"
  name "TelepAIth"
  desc "Desktop robot that tells you what Claude and GPT are doing"
  homepage "https://github.com/onurerensavci/TelepAIth"

  auto_updates true
  depends_on macos: ">= :ventura"

  app "TelepAIth.app"

  # Uygulama Apple'a onaylatılmadığı için ilk açılışta macOS'un engellemesini önler
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/TelepAIth.app"]
  end

  uninstall quit: "com.telepaith.app"

  zap trash: [
    "~/.telepaith",
    "~/Library/Preferences/com.telepaith.app.plist",
  ]
end
