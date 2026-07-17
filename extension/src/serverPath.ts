import * as fs from 'node:fs';
import * as path from 'node:path';

export type ServerPathSource = 'configured' | 'development' | 'packaged';

export interface ServerPathResolution {
  readonly executablePath: string;
  readonly source: ServerPathSource;
  readonly target: string;
}

type SupportedPlatform = 'darwin' | 'linux' | 'win32';
type SupportedArchitecture = 'arm64' | 'x64';

export function platformTarget(
  platform: NodeJS.Platform = process.platform,
  architecture: string = process.arch,
): string {
  if (!isSupportedPlatform(platform)) {
    throw new Error(`FPC XUI does not provide a language server for platform '${platform}'.`);
  }

  if (!isSupportedArchitecture(architecture)) {
    throw new Error(`FPC XUI does not provide a language server for architecture '${architecture}'.`);
  }

  return `${platform}-${architecture}`;
}

export function serverBinaryName(platform: NodeJS.Platform = process.platform): string {
  return platform === 'win32' ? 'fpcxui-ls.exe' : 'fpcxui-ls';
}

export function resolveServerPath(
  extensionPath: string,
  configuredPath: string,
  platform: NodeJS.Platform = process.platform,
  architecture: string = process.arch,
  isFile: (candidate: string) => boolean = isRegularFile,
): ServerPathResolution {
  const target = platformTarget(platform, architecture);
  const configured = configuredPath.trim();

  if (configured.length > 0) {
    if (!path.isAbsolute(configured)) {
      throw new Error('The fpcXui.server.path setting must be an absolute path.');
    }

    if (!isFile(configured)) {
      throw new Error('The configured FPC XUI language-server executable does not exist or is not a file.');
    }

    return {
      executablePath: configured,
      source: 'configured',
      target,
    };
  }

  const binaryName = serverBinaryName(platform);
  const developmentPath = path.resolve(
    extensionPath,
    '..',
    'server',
    'bin',
    target,
    binaryName,
  );

  if (isFile(developmentPath)) {
    return {
      executablePath: developmentPath,
      source: 'development',
      target,
    };
  }

  const packagedPath = path.resolve(
    extensionPath,
    'server',
    target,
    binaryName,
  );

  if (isFile(packagedPath)) {
    return {
      executablePath: packagedPath,
      source: 'packaged',
      target,
    };
  }

  throw new Error(
    `No FPC XUI language-server executable is available for '${target}'. `
      + 'Build the repository server or configure fpcXui.server.path.',
  );
}

function isRegularFile(candidate: string): boolean {
  try {
    return fs.statSync(candidate).isFile();
  } catch {
    return false;
  }
}

function isSupportedPlatform(platform: NodeJS.Platform): platform is SupportedPlatform {
  return platform === 'darwin' || platform === 'linux' || platform === 'win32';
}

function isSupportedArchitecture(architecture: string): architecture is SupportedArchitecture {
  return architecture === 'arm64' || architecture === 'x64';
}
