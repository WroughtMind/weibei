import assert from 'node:assert/strict';
import test from 'node:test';
import {
  acceptsEditorCommand,
  createEditorEvent,
  type EditorCommand,
  parseEditorCommand,
  reduceRevision,
} from '../src/bridge/protocol';

const requestSnapshot: EditorCommand = {
  protocolVersion: 2,
  commandID: 'command-1',
  requestID: 'request-1',
  documentID: 'note-a',
  documentGeneration: 3,
  minimumRevision: 7,
  type: 'requestSnapshot',
  payload: {},
};

test('bridge command parser accepts the V2 envelope and rejects incomplete commands', () => {
  assert.deepEqual(parseEditorCommand(requestSnapshot), requestSnapshot);
  assert.equal(parseEditorCommand({ ...requestSnapshot, protocolVersion: 1 }), null);
  assert.equal(parseEditorCommand({ ...requestSnapshot, commandID: '' }), null);
  assert.equal(parseEditorCommand({ ...requestSnapshot, requestID: undefined }), null);
  assert.equal(parseEditorCommand({ ...requestSnapshot, documentGeneration: -1 }), null);
});

test('bridge routes only the current document generation and a satisfiable revision', () => {
  const current = { documentID: 'note-a', documentGeneration: 3, revision: 7 };
  assert.equal(acceptsEditorCommand(requestSnapshot, current), true);
  assert.equal(acceptsEditorCommand({ ...requestSnapshot, documentID: 'note-b' }, current), false);
  assert.equal(acceptsEditorCommand({ ...requestSnapshot, documentGeneration: 2 }, current), false);
  assert.equal(acceptsEditorCommand({ ...requestSnapshot, minimumRevision: 8 }, current), false);

  const newerLoad: EditorCommand = { ...requestSnapshot, type: 'loadDocument', requestID: undefined, minimumRevision: undefined, documentID: 'note-b', documentGeneration: 4 };
  assert.equal(acceptsEditorCommand(newerLoad, current), true);
  assert.equal(acceptsEditorCommand({ ...newerLoad, documentGeneration: 2 }, current), false);
});

test('revision advances only for document-changing transactions', () => {
  assert.deepEqual(reduceRevision({ revision: 4, dirty: false }, false), { revision: 4, dirty: false, changed: false });
  assert.deepEqual(reduceRevision({ revision: 4, dirty: false }, true), { revision: 5, dirty: true, changed: true });
  assert.deepEqual(reduceRevision({ revision: 5, dirty: true }, true), { revision: 6, dirty: true, changed: true });
});

test('editor events carry the current document envelope', () => {
  assert.deepEqual(
    createEditorEvent(
      { documentID: 'note-a', documentGeneration: 3, revision: 7 },
      { requestID: 'request-1', markdown: '# Note\n' },
    ),
    {
      protocolVersion: 2,
      documentID: 'note-a',
      documentGeneration: 3,
      revision: 7,
      requestID: 'request-1',
      markdown: '# Note\n',
    },
  );
});
