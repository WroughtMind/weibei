import { useEffect, useRef, useState } from "react";
import { Icon } from "./Icon";

interface Props {
  title: string;
  initialValue: string;
  onCancel(): void;
  onConfirm(value: string): void | Promise<void>;
}

export function NamePromptSheet(props: Props) {
  const [value, setValue] = useState(props.initialValue);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
    inputRef.current?.select();
  }, []);

  return (
    <div className="name-prompt-scrim" role="presentation">
      <section
        className="name-prompt-sheet"
        role="dialog"
        aria-modal="true"
        aria-labelledby="name-prompt-title"
        onKeyDown={(event) => {
          if (event.key === "Escape") {
            event.preventDefault();
            props.onCancel();
          }
        }}
      >
        <header className="name-prompt-header">
          <div><span className="overline">WEI BEI</span><h2 id="name-prompt-title">{props.title}</h2></div>
          <button className="icon-action" type="button" onClick={props.onCancel} aria-label="取消">
            <Icon name="close" size={19} />
          </button>
        </header>
        <form
          className="name-prompt-form"
          onSubmit={(event) => {
            event.preventDefault();
            const trimmed = value.trim();
            if (trimmed) void props.onConfirm(trimmed);
          }}
        >
          <label className="name-prompt-field" htmlFor="name-prompt-input">
            <span>名称</span>
            <input
              ref={inputRef}
              id="name-prompt-input"
              data-testid="name-prompt-input"
              value={value}
              onChange={(event) => setValue(event.target.value)}
              autoComplete="off"
            />
          </label>
          <footer className="name-prompt-actions">
            <button type="button" onClick={props.onCancel}>取消</button>
            <button className="primary-paper-button" type="submit" disabled={!value.trim()}>确定</button>
          </footer>
        </form>
      </section>
    </div>
  );
}
