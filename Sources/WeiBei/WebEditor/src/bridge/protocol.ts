export const editorProtocolVersion = 2 as const;

export const editorCommandTypes = [
  'loadDocument',
  'requestSnapshot',
  'setTheme',
  'setLanguage',
  'setWritingFont',
  'setEditable',
  'focus',
  'scrollToHeading',
  'applyMarkdownFragment',
  'replaceSelection',
  'executeSelectionCommand',
  'insertStructuredBlock',
  'restoreCheckpoint',
] as const;

export type EditorCommandType = typeof editorCommandTypes[number];

export type EditorCommand = {
  protocolVersion: typeof editorProtocolVersion;
  commandID: string;
  requestID?: string;
  documentID: string;
  documentGeneration: number;
  minimumRevision?: number;
  type: EditorCommandType;
  payload: Record<string, unknown>;
};

export type EditorSession = {
  documentID: string;
  documentGeneration: number;
  revision: number;
};

export type RevisionState = { revision: number; dirty: boolean };

const isNonNegativeInteger = (value: unknown): value is number => Number.isInteger(value) && Number(value) >= 0;
const isNonEmptyString = (value: unknown): value is string => typeof value === 'string' && value.length > 0;

export const parseEditorCommand = (value: unknown): EditorCommand | null => {
  if (!value || typeof value !== 'object') return null;
  const command = value as Record<string, unknown>;
  if (command.protocolVersion !== editorProtocolVersion
      || !isNonEmptyString(command.commandID)
      || typeof command.documentID !== 'string'
      || !isNonNegativeInteger(command.documentGeneration)
      || !editorCommandTypes.includes(command.type as EditorCommandType)
      || !command.payload
      || typeof command.payload !== 'object'
      || Array.isArray(command.payload)
      || (command.minimumRevision !== undefined && !isNonNegativeInteger(command.minimumRevision))
      || (command.requestID !== undefined && !isNonEmptyString(command.requestID))
      || (command.type === 'requestSnapshot' && !isNonEmptyString(command.requestID))) return null;
  return command as EditorCommand;
};

export const acceptsEditorCommand = (
  command: Pick<EditorCommand, 'type' | 'documentID' | 'documentGeneration' | 'minimumRevision'>,
  current: EditorSession,
) => {
  if (command.type === 'loadDocument') {
    return command.documentGeneration > current.documentGeneration
      || (command.documentGeneration === current.documentGeneration
        && (!current.documentID || command.documentID === current.documentID));
  }
  return command.documentID === current.documentID
    && command.documentGeneration === current.documentGeneration
    && (command.minimumRevision === undefined || command.minimumRevision <= current.revision);
};

export const reduceRevision = (state: RevisionState, docChanged: boolean) => docChanged
  ? { revision: state.revision + 1, dirty: true, changed: true }
  : { ...state, changed: false };

export const createEditorEvent = <Body extends Record<string, unknown>>(
  session: EditorSession,
  body: Body,
) => ({
  ...body,
  protocolVersion: editorProtocolVersion,
  documentID: session.documentID,
  documentGeneration: session.documentGeneration,
  revision: session.revision,
});
