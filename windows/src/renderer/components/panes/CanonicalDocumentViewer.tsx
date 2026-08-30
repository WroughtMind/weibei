import { useEffect, useRef } from "react";
import type { Preferences, SelectionContext } from "../../../shared/contracts";
import { WeiBeiEditorHost } from "../../editor/host";

interface Props {
  itemId: string;
  markdown: string;
  preferences: Preferences;
  onSelection(value: SelectionContext | null): void;
}

/** Uses the same generated Markdown runtime as macOS and the note editor. */
export function CanonicalDocumentViewer(props: Props) {
  const frameRef = useRef<HTMLIFrameElement>(null);
  const hostRef = useRef<WeiBeiEditorHost | null>(null);
  const onSelectionRef = useRef(props.onSelection);
  onSelectionRef.current = props.onSelection;

  useEffect(() => {
    const frame = frameRef.current;
    if (!frame) return;
    const host = new WeiBeiEditorHost(frame, {
      markdown: props.markdown,
      documentID: props.itemId,
      documentGeneration: 0,
      editable: false,
      theme: props.preferences.theme,
      interfaceLanguage: props.preferences.language,
      reduceMotion: props.preferences.reduceMotion,
      textScale: props.preferences.textScale,
    }, {
      frameURL: import.meta.env.DEV
        ? new URL("/Editor/windows-host.html", window.location.origin)
        : "weibei-editor://app/Editor/windows-host.html",
    });
    hostRef.current = host;
    const unsubscribe = host.subscribe((event) => {
      if (event.name !== "selectionChanged") return;
      const text = event.body.text.trim();
      if (!text) return;
      onSelectionRef.current({
        itemId: props.itemId,
        text,
        pageIndex: null,
        sectionTitle: null,
        sectionLocationId: null,
      });
    });
    host.mount();
    return () => {
      unsubscribe();
      host.destroy();
      hostRef.current = null;
    };
  }, [props.itemId, props.markdown]);

  useEffect(() => { hostRef.current?.call({ method: "setTheme", args: [props.preferences.theme] }); }, [props.preferences.theme]);
  useEffect(() => { hostRef.current?.call({ method: "setInterfaceLanguage", args: [props.preferences.language] }); }, [props.preferences.language]);
  useEffect(() => { hostRef.current?.call({ method: "setReduceMotion", args: [props.preferences.reduceMotion] }); }, [props.preferences.reduceMotion]);
  useEffect(() => { hostRef.current?.call({ method: "setTextScale", args: [props.preferences.textScale] }); }, [props.preferences.textScale]);

  return (
    <iframe
      ref={frameRef}
      className="canonical-document-viewer"
      title={props.itemId}
      sandbox="allow-scripts allow-same-origin"
    />
  );
}
