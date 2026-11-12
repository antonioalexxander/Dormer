# Homebrew cask for a personal tap (e.g. github.com/<owner>/homebrew-dormer, file Casks/dormer.rb).
# Replace OWNER and the sha256 with the values printed by Tools/make-dmg.sh for the release you publish.
cask "dormer" do
  version "0.1.0"
  sha256 "REPLACE_WITH_THE_SHA256_OF_THE_DMG"

  url "https://github.com/OWNER/Dormer/releases/download/v#{version}/Dormer-#{version}.dmg"
  name "Dormer"
  desc "Run Windows apps on your Mac with Wine, no terminal required"
  homepage "https://github.com/OWNER/Dormer"

  depends_on macos: ">= :sonoma"

  app "Dormer.app"

  zap trash: [
    "~/Library/Application Support/Dormer",
    "~/Library/Preferences/io.github.dormer-app.Dormer.plist",
  ]

  caveats <<~EOS
    Dormer is free software and is not signed with a paid Apple Developer ID, so macOS Gatekeeper will
    block the first launch. Open System Settings > Privacy & Security, scroll to the message about Dormer
    and choose "Open Anyway". Bottles, Wine and downloads live in ~/Library/Application Support/Dormer.
  EOS
end
