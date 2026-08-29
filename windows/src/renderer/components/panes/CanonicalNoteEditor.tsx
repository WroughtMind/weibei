import { useEffect, useRef } from "react";
import type { Preferences, SelectionContext } from "../../../shared/contracts";
import { editorProtocolVersion } from "../../../shared/editor-contracts";
import { WeiBeiEditorHost } from "../../editor/host";

interface Props {
  itemId: string;
  markdown: string;
  preferences: Preferences;
  onChange(markdown: string): void;
  onSelection(value: SelectionContext | null): void;
}

export function CanonicalNoteEditor(props: Props) {
  const frameRef = useRef<HTMLIFrameElement>(null);
  const hostRef = useRef<WeiBeiEditorHost | null>(null);
  const revisionRef = useRef(0);
  const snapshotPendingRef = useRef(false);
  const snapshotQueuedRef = useRef(false);
  const onChangeRef = useRef(props.onChange);
  const onSelectionRef = useRef(props.onSelection);
  onChangeRef.current = props.onChange;
  onSelectionRef.current = props.onSelection;

  useEffect(() => {
    const frame = frameRef.current;
    if (!frame) return;
    const host = new WeiBeiEditorHost(frame, {
      markdown: props.markdown,
      documentID: props.itemId,
      documentGeneration: 0,
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
    const requestSnapshot = () => {
      snapshotPendingRef.current = true;
      host.dispatchCommand({
        protocolVersion: editorProtocolVersion,
        commandID: crypto.randomUUID(),
        requestID: crypto.randomUUID(),
        documentID: props.itemId,
        documentGeneration: 0,
        minimumRevision: revisionRef.current,
        type: "requestSnapshot",
        payload: {},
      });
    };
    const unsubscribe = host.subscribe((event) => {
      if ("revision" in event.body && typeof event.body.revision === "number") revisionRef.current = event.body.revision;
      if (event.name === "dirtyChanged" && event.body.dirty) {
        if (snapshotPendingRef.current) snapshotQueuedRef.current = true;
        else requestSnapshot();
      }
      if (event.name === "snapshotReady") {
        snapshotPendingRef.current = false;
        onChangeRef.current(event.body.markdown);
        if (snapshotQueuedRef.current) {
          snapshotQueuedRef.current = false;
          requestSnapshot();
        }
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
      unsubscribe();
      host.destroy();
      hostRef.current = null;
      snapshotPendingRef.current = false;
      snapshotQueuedRef.current = false;
    };
    // A new item must create a new isolated editor session. Markdown is only
    // bootstrap input; live edits flow out through revisioned snapshots.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [props.itemId]);

  useEffect(() => { hostRef.current?.call({ method: "setTheme", args: [props.preferences.theme] }); }, [props.preferences.theme]);
  useEffect(() => { hostRef.current?.call({ method: "setInterfaceLanguage", args: [props.preferences.language] }); }, [props.preferences.language]);
  useEffect(() => { hostRef.current?.call({ method: "setReduceMotion", args: [props.preferences.reduceMotion] }); }, [props.preferences.reduceMotion]);
  useEffect(() => { hostRef.current?.call({ method: "setTextScale", args: [props.preferences.textScale] }); }, [props.preferences.textScale]);

  return <iframe ref={frameRef} className="canonical-note-editor" title={`编辑 ${props.itemId}`} sandbox="allow-scripts allow-same-origin" />;
}
