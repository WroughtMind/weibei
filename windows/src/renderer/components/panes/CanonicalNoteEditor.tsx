import { forwardRef, useEffect, useImperativeHandle, useRef } from "react";
import type { Preferences, SelectionContext } from "../../../shared/contracts";
import { editorProtocolVersion } from "../../../shared/editor-contracts";
import { WeiBeiEditorHost } from "../../editor/host";
import {
  NoteEditorFreezeGate,
  NoteSnapshotFlushCoordinator,
  type NoteEditorSnapshot,
} from "../../note-snapshot-flush";

interface Props {
  itemId: string;
  markdown: string;
  documentGeneration: number;
  preferences: Preferences;
  onChange(markdown: string, itemId: string, documentGeneration: number): void;
  onSelection(value: SelectionContext | null): void;
}

export interface CanonicalNoteEditorHandle {
  beginSnapshotFlush(): {
    snapshot: Promise<NoteEditorSnapshot>;
    release(): void;
  };
}

export const CanonicalNoteEditor = forwardRef<CanonicalNoteEditorHandle, Props>(
function CanonicalNoteEditor(props, ref) {
  const frameRef = useRef<HTMLIFrameElement>(null);
  const hostRef = useRef<WeiBeiEditorHost | null>(null);
  const flushCoordinatorRef = useRef<NoteSnapshotFlushCoordinator | null>(null);
  const freezeGateRef = useRef<NoteEditorFreezeGate | null>(null);
  const freezeCommandIDRef = useRef<string | null>(null);
  const revisionRef = useRef(0);
  const onChangeRef = useRef(props.onChange);
  const onSelectionRef = useRef(props.onSelection);
  onChangeRef.current = props.onChange;
  onSelectionRef.current = props.onSelection;

  useImperativeHandle(ref, () => ({
    beginSnapshotFlush() {
      const host = hostRef.current;
      const coordinator = flushCoordinatorRef.current;
      const freezeGate = freezeGateRef.current;
      if (!host || !coordinator || !freezeGate) throw new Error("笔记编辑器尚未准备好");
      const releaseFreeze = freezeGate.acquire();
      let released = false;
      return {
        snapshot: coordinator.flush(),
        release() {
          if (released) return;
          released = true;
          releaseFreeze();
        },
      };
    },
  }), []);

  useEffect(() => {
    const frame = frameRef.current;
    if (!frame) return;
    revisionRef.current = 0;
    freezeCommandIDRef.current = null;
    const host = new WeiBeiEditorHost(frame, {
      markdown: props.markdown,
      documentID: props.itemId,
      documentGeneration: props.documentGeneration,
      editable: true,
      theme: props.preferences.theme,
      interfaceLanguage: props.preferences.language,
      reduceMotion: props.preferences.reduceMotion,
      textScale: props.preferences.textScale,
    }, {
      // Production keeps the canonical editor on its own privileged origin.
      // During Vite development the generated bridge is served by the dev
      // server, so use the current origin instead of proxying Vite internals
      // through the packaged-protocol whitelist.
      frameURL: import.meta.env.DEV
        ? new URL("/Editor/windows-host.html", window.location.origin)
        : "weibei-editor://app/Editor/windows-host.html",
    });
    hostRef.current = host;
    const freezeGate = new NoteEditorFreezeGate((editable) => {
      if (!editable && hostRef.current === host) {
        const commandID = crypto.randomUUID();
        freezeCommandIDRef.current = commandID;
        host.dispatchCommand({
          protocolVersion: editorProtocolVersion,
          commandID,
          documentID: props.itemId,
          documentGeneration: props.documentGeneration,
          minimumRevision: revisionRef.current,
          type: "setEditable",
          payload: { editable },
        });
        return;
      }
      if (hostRef.current !== host) return;
      try {
        host.dispatchCommand({
          protocolVersion: editorProtocolVersion,
          commandID: crypto.randomUUID(),
          documentID: props.itemId,
          documentGeneration: props.documentGeneration,
          minimumRevision: revisionRef.current,
          type: "setEditable",
          payload: { editable },
        });
      } catch {
        // The old frame may already be gone after a successful navigation.
      }
    });
    freezeGateRef.current = freezeGate;
    const coordinator = new NoteSnapshotFlushCoordinator({
      createRequestID: () => crypto.randomUUID(),
      requestSnapshot: (requestID) => {
        const commandID = crypto.randomUUID();
        const minimumRevision = revisionRef.current;
        host.dispatchCommand({
          protocolVersion: editorProtocolVersion,
          commandID,
          requestID,
          documentID: props.itemId,
          documentGeneration: props.documentGeneration,
          minimumRevision,
          type: "requestSnapshot",
          payload: {},
        });
        return {
          commandID,
          documentID: props.itemId,
          documentGeneration: props.documentGeneration,
          minimumRevision,
        };
      },
      onSnapshot: (snapshot) => onChangeRef.current(
        snapshot.markdown,
        snapshot.documentID,
        snapshot.documentGeneration,
      ),
    });
    flushCoordinatorRef.current = coordinator;
    const unsubscribe = host.subscribe((event) => {
      if ("revision" in event.body && typeof event.body.revision === "number") revisionRef.current = event.body.revision;
      if (event.name === "dirtyChanged" && event.body.dirty) {
        coordinator.markDirty();
      }
      if (event.name === "snapshotReady") {
        coordinator.accept({
          requestID: event.body.requestID,
          documentID: event.body.documentID,
          documentGeneration: event.body.documentGeneration,
          revision: event.body.revision,
          markdown: event.body.markdown,
        });
      }
      if (event.name === "commandRejected") {
        const error = new Error(`笔记命令被编辑器拒绝：${event.body.reason}`);
        if (event.body.commandID === freezeCommandIDRef.current) {
          freezeCommandIDRef.current = null;
          coordinator.rejectPending(error);
        } else {
          coordinator.rejectCommand(event.body.commandID, error);
        }
      }
      if (event.name === "commandApplied"
          && event.body.commandID === freezeCommandIDRef.current) {
        freezeCommandIDRef.current = null;
      }
      if (event.name === "editorFailure") {
        coordinator.rejectPending(new Error(event.body.message));
      }
      if (event.name === "selectionChanged") {
        const text = event.body.text.trim();
        if (!text) return;
        onSelectionRef.current({
          itemId: props.itemId,
          text,
          pageIndex: null,
          sectionTitle: null,
          sectionLocationId: null,
        });
      }
    });
    host.mount();
    return () => {
      coordinator.rejectPending(new Error("笔记编辑器已关闭"));
      if (flushCoordinatorRef.current === coordinator) flushCoordinatorRef.current = null;
      freezeGate.dispose();
      if (freezeGateRef.current === freezeGate) freezeGateRef.current = null;
      freezeCommandIDRef.current = null;
      unsubscribe();
      host.destroy();
      hostRef.current = null;
    };
    // A new item must create a new isolated editor session. Markdown is only
    // bootstrap input; live edits flow out through revisioned snapshots.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [props.documentGeneration, props.itemId]);

  useEffect(() => { hostRef.current?.call({ method: "setTheme", args: [props.preferences.theme] }); }, [props.preferences.theme]);
  useEffect(() => { hostRef.current?.call({ method: "setInterfaceLanguage", args: [props.preferences.language] }); }, [props.preferences.language]);
  useEffect(() => { hostRef.current?.call({ method: "setReduceMotion", args: [props.preferences.reduceMotion] }); }, [props.preferences.reduceMotion]);
  useEffect(() => { hostRef.current?.call({ method: "setTextScale", args: [props.preferences.textScale] }); }, [props.preferences.textScale]);

  return <iframe ref={frameRef} className="canonical-note-editor" title={`编辑 ${props.itemId}`} sandbox="allow-scripts allow-same-origin" />;
});
