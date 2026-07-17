import * as path from 'node:path';

import * as vscode from 'vscode';
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  State,
  TransportKind,
} from 'vscode-languageclient/node';

import { resolveServerPath } from './serverPath';

let client: LanguageClient | undefined;
let outputChannel: vscode.OutputChannel | undefined;

export async function activate(context: vscode.ExtensionContext): Promise<void> {
  outputChannel = vscode.window.createOutputChannel('FPC XUI');
  context.subscriptions.push(outputChannel);
  outputChannel.appendLine('Activating the FPC XUI language client.');

  try {
    const configuredPath = vscode.workspace
      .getConfiguration('fpcXui')
      .get<string>('server.path', '');

    if (configuredPath.trim().length > 0 && !vscode.workspace.isTrusted) {
      throw new Error(
        'A custom FPC XUI language-server path cannot run in an untrusted workspace.',
      );
    }

    const resolution = resolveServerPath(context.extensionPath, configuredPath);
    outputChannel.appendLine(
      `Selected the ${resolution.source} language server for ${resolution.target}.`,
    );

    const workingDirectory = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath
      ?? path.dirname(resolution.executablePath);

    const serverOptions: ServerOptions = {
      command: resolution.executablePath,
      transport: TransportKind.stdio,
      options: {
        cwd: workingDirectory,
      },
    };

    const clientOptions: LanguageClientOptions = {
      documentSelector: [
        { language: 'freepascal', scheme: 'file' },
        { language: 'freepascal', scheme: 'untitled' },
      ],
      synchronize: {
        configurationSection: 'fpcXui',
      },
      outputChannel,
    };

    client = new LanguageClient(
      'fpcXui',
      'FPC XUI Language Server',
      serverOptions,
      clientOptions,
    );

    context.subscriptions.push(
      client.onDidChangeState(({ newState }) => {
        outputChannel?.appendLine(`Language-server state: ${stateName(newState)}.`);
      }),
    );

    await client.start();
    outputChannel.appendLine('FPC XUI language client started.');
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Unknown activation error.';
    outputChannel.appendLine(`Activation failed: ${message}`);
    void vscode.window.showErrorMessage(
      'FPC XUI could not start its language server. See the FPC XUI output channel.',
    );
    throw error;
  }
}

export async function deactivate(): Promise<void> {
  const activeClient = client;
  client = undefined;

  if (activeClient === undefined) {
    return;
  }

  outputChannel?.appendLine('Stopping the FPC XUI language client.');
  await activeClient.stop();
}

function stateName(state: State): string {
  switch (state) {
    case State.Starting:
      return 'starting';
    case State.Running:
      return 'running';
    case State.Stopped:
      return 'stopped';
  }
}
