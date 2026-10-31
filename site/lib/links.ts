export const REPO_URL = "https://github.com/intuito-studio/nosleep";
// `latest/download` always points at the newest release's asset, so no version
// is baked into the page. The asset name is the one Updater reads too.
export const DMG_URL = `${REPO_URL}/releases/latest/download/NoSleep.dmg`;
export const INSTALL_LINE = "curl -fsSL https://raw.githubusercontent.com/intuito-studio/nosleep/main/install.sh | bash";
export const BREW_LINES = [
  "brew tap intuito-studio/tap",
  "brew trust --cask intuito-studio/tap/nosleep",
  "brew install --cask intuito-studio/tap/nosleep",
];
export const INSOMNIA_URL = "https://github.com/krishhgg/Insomnia";
