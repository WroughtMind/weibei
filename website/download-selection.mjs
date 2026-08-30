export const downloadTargets = [
  {
    id: 'mac-arm64',
    label: { zh: 'Apple 芯片', en: 'Apple silicon' },
    menuLabel: { zh: 'macOS · Apple 芯片', en: 'macOS · Apple silicon' },
    matches: name => name.endsWith('.dmg') && /(arm64|aarch64|apple[-_. ]?silicon)/.test(name) && !/universal/.test(name)
  },
  {
    id: 'mac-intel',
    label: { zh: 'Intel 芯片', en: 'Intel' },
    menuLabel: { zh: 'macOS · Intel 芯片', en: 'macOS · Intel' },
    matches: name => name.endsWith('.dmg') && /(x86_64|x64|intel)/.test(name) && !/universal/.test(name)
  },
  {
    id: 'windows-x64',
    label: { zh: 'Windows', en: 'Windows' },
    menuLabel: { zh: 'Windows · x64', en: 'Windows · x64' },
    matches: name => /\.(exe|msi)$/.test(name) && /(windows|win)[-_. ]/.test(name) && /(x64|x86_64)/.test(name)
  }
];

export const matchDownloadAssets = assets => {
  const universalMac = assets.find(asset => {
    const name = String(asset.name || '').toLowerCase();
    return name.endsWith('.dmg') && /universal/.test(name);
  });
  return Object.fromEntries(downloadTargets.map(target => [
    target.id,
    assets.find(asset => target.matches(String(asset.name || '').toLowerCase())) ||
      (target.id.startsWith('mac-') ? universalMac : undefined)
  ]));
};

export const preferredDownloadIds = ({ platform = '', architecture = '' }) => {
  const normalizedPlatform = platform.toLowerCase();
  const normalizedArchitecture = architecture.toLowerCase();
  if (/windows|win32|win64/.test(normalizedPlatform)) return ['windows-x64', 'mac-arm64', 'mac-intel'];
  if (/mac|darwin/.test(normalizedPlatform)) {
    if (/arm|aarch64/.test(normalizedArchitecture)) return ['mac-arm64', 'mac-intel'];
    if (/x86|intel/.test(normalizedArchitecture)) return ['mac-intel', 'mac-arm64'];
    return ['mac-arm64', 'mac-intel'];
  }
  return ['mac-arm64', 'windows-x64', 'mac-intel'];
};

export const chooseDownloadId = (matchedAssets, preferredIds) =>
  preferredIds.find(id => matchedAssets[id]) || preferredIds[0];
