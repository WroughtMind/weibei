import { SlashProvider, slashFactory } from '@milkdown/kit/plugin/slash';
import { closeHistory } from '@milkdown/kit/prose/history';
import { Fragment } from '@milkdown/kit/prose/model';
import { Selection } from '@milkdown/kit/prose/state';

import {
  filteredSlashCommands,
  slashCommands,
  slashContextForView,
  slashGroups,
  slashReplacement,
} from './commands.js';

const weiBeiSlash = slashFactory('WEIBEI_BLOCK_COMMAND');

/**
 * Creates the Slash command menu and its Milkdown plugin.
 *
 * @param {object} dependencies - Editor services used by the Slash feature
 * @returns {object} Slash feature API
 */
export function createSlashFeature({
  post,
  editorLabel,
  isEditable,
  getDocumentID,
  clearSelectionRange,
}) {
  let pickerRequestID = 0;
  const pendingImagePickers = new Map();

  const slashMenuElement = document.createElement('div');
  slashMenuElement.className = 'weibei-slash-menu';
  slashMenuElement.dataset.show = 'false';
  slashMenuElement.setAttribute('role', 'listbox');
  slashMenuElement.setAttribute('aria-label', 'Slash commands');
  let slashTablePanelElement = null;
  const slashRuntime = {
    provider: null,
    view: null,
    context: null,
    commands: [],
    activeIndex: 0,
    dismissedContext: '',
    activationContext: '',
    tableOpen: false,
    tableFocus: 'rows',
    tableRows: 3,
    tableColumns: 3,
    pointerX: null,
    pointerY: null,
  };
  /**
   * Replaces the slash paragraph in one ProseMirror transaction and places the caret in the new block.
   *
   * @param {import('@milkdown/kit/prose/view').EditorView} view - Current ProseMirror view
   * @param {ReturnType<typeof slashContextForView>} context - Slash paragraph snapshot
   * @param {{ content: Fragment, selectionOffset: number }} replacement - Replacement block and caret offset
   * @returns {boolean}
   */
  const applySlashReplacement = (view, context, replacement) => {
    if (!context || !replacement) return false;
    const currentNode = view.state.doc.nodeAt(context.blockFrom);
    if (currentNode?.type.name !== 'paragraph' || currentNode.textContent !== context.source) return false;
    const tr = closeHistory(view.state.tr.replaceWith(context.blockFrom, context.blockTo, replacement.content));
    const requestedPosition = context.blockFrom + replacement.selectionOffset;
    const selection = Selection.findFrom(
      tr.doc.resolve(Math.min(requestedPosition, tr.doc.content.size)),
      1,
      true
    );
    if (selection) tr.setSelection(selection);
    view.dispatch(tr.scrollIntoView());
    clearSelectionRange();
    slashRuntime.dismissedContext = '';
    slashRuntime.provider?.hide();
    return true;
  };

  /**
   * Opens the native image picker while preserving the slash paragraph for a single undoable replacement.
   *
   * @param {import('@milkdown/kit/prose/view').EditorView} view - Current ProseMirror view
   * @param {ReturnType<typeof slashContextForView>} context - Slash paragraph snapshot
   */
  const requestSlashImage = (view, context) => {
    const id = `image-picker-${Date.now()}-${pickerRequestID += 1}`;
    pendingImagePickers.set(id, { view, context });
    slashRuntime.dismissedContext = context.key;
    slashRuntime.provider?.hide();
    post('imagePickerRequested', { id });
  };

  /**
   * Executes the highlighted command or opens its secondary control.
   *
   * @param {string} commandID - Slash command identifier
   */
  const executeSlashCommand = (commandID) => {
    const view = slashRuntime.view;
    if (!view) return;
    const context = slashContextForView(view, isEditable());
    if (!context) return;
    if (commandID === 'image') {
      requestSlashImage(view, context);
      return;
    }
    const replacement = slashReplacement(commandID, view.state.schema, {
      rows: slashRuntime.tableRows,
      columns: slashRuntime.tableColumns,
    });
    applySlashReplacement(view, context, replacement);
  };

  /**
   * Keeps the table size panel visible inside the viewport, preferring the right side.
   *
   * @param {HTMLElement} panel - Rendered table size panel
   * @param {HTMLElement} anchor - Table command button used as the positioning anchor
   */
  const positionTableSlashPanel = (panel, anchor) => {
    panel.style.visibility = 'hidden';
    window.requestAnimationFrame(() => {
      if (!panel.isConnected || !anchor.isConnected) return;
      const rowRect = anchor.getBoundingClientRect();
      const panelRect = panel.getBoundingClientRect();
      const opensLeft = rowRect.right + 6 + panelRect.width > window.innerWidth - 8;
      const left = opensLeft
        ? Math.max(8, rowRect.left - panelRect.width - 6)
        : Math.min(window.innerWidth - panelRect.width - 8, rowRect.right + 6);
      const top = Math.min(
        Math.max(8, rowRect.top),
        Math.max(8, window.innerHeight - panelRect.height - 8)
      );
      panel.classList.toggle('weibei-slash-table-panel-left', opensLeft);
      panel.style.left = `${left}px`;
      panel.style.top = `${top}px`;
      panel.style.visibility = 'visible';
    });
  };

  /**
   * Renders a compact row/column stepper for the table secondary panel.
   *
   * @param {'rows' | 'columns'} kind - Dimension being edited
   * @returns {HTMLElement}
   */
  const renderSlashTableStepper = (kind) => {
    const isRows = kind === 'rows';
    const minimum = 1;
    const maximum = isRows ? 20 : 12;
    const value = isRows ? slashRuntime.tableRows : slashRuntime.tableColumns;
    const stepper = document.createElement('div');
    stepper.className = `weibei-slash-stepper${slashRuntime.tableFocus === kind ? ' is-focused' : ''}`;
    stepper.setAttribute('role', 'group');
    stepper.setAttribute('aria-label', editorLabel(isRows ? 'slashRows' : 'slashColumns'));

    const label = document.createElement('span');
    label.className = 'weibei-slash-stepper-label';
    label.textContent = editorLabel(isRows ? 'slashRows' : 'slashColumns');

    const controls = document.createElement('div');
    controls.className = 'weibei-slash-stepper-controls';
    for (const [symbol, delta] of [['−', -1], ['+', 1]]) {
      if (delta > 0) {
        const number = document.createElement('output');
        number.textContent = String(value);
        number.setAttribute('aria-live', 'polite');
        controls.appendChild(number);
      }
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = symbol;
      button.disabled = delta < 0 ? value <= minimum : value >= maximum;
      button.setAttribute('aria-label', `${editorLabel(isRows ? 'slashRows' : 'slashColumns')} ${symbol}`);
      button.addEventListener('pointerdown', (event) => event.preventDefault());
      button.addEventListener('click', () => {
        const next = Math.min(maximum, Math.max(minimum, value + delta));
        if (isRows) slashRuntime.tableRows = next;
        else slashRuntime.tableColumns = next;
        slashRuntime.tableFocus = kind;
        renderSlashMenu();
      });
      controls.appendChild(button);
    }
    stepper.append(label, controls);
    return stepper;
  };

  /**
   * Renders the current command results and table secondary panel.
   */
  const renderSlashMenu = () => {
    slashTablePanelElement?.remove();
    slashTablePanelElement = null;
    const view = slashRuntime.view;
    if (!view) {
      slashRuntime.provider?.hide();
      return;
    }
    const context = slashContextForView(view, isEditable());
    if (!context || slashRuntime.dismissedContext === context.key) {
      slashRuntime.provider?.hide();
      return;
    }
    if (slashRuntime.activationContext !== `${context.blockFrom}:${getDocumentID()}`) {
      slashRuntime.activationContext = `${context.blockFrom}:${getDocumentID()}`;
      slashRuntime.activeIndex = 0;
      slashRuntime.tableOpen = false;
      slashRuntime.tableFocus = 'rows';
      slashRuntime.tableRows = 3;
      slashRuntime.tableColumns = 3;
      slashRuntime.pointerX = null;
      slashRuntime.pointerY = null;
    }
    slashRuntime.context = context;
    slashRuntime.commands = filteredSlashCommands(context.query, context, view.state.schema);
    slashRuntime.activeIndex = Math.min(
      Math.max(0, slashRuntime.activeIndex),
      Math.max(0, slashRuntime.commands.length - 1)
    );

    slashMenuElement.replaceChildren();
    slashMenuElement.setAttribute(
      'aria-activedescendant',
      slashRuntime.commands[slashRuntime.activeIndex]
        ? `weibei-slash-command-${slashRuntime.commands[slashRuntime.activeIndex].id}`
        : ''
    );

    if (slashRuntime.commands.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'weibei-slash-empty';
      empty.textContent = editorLabel('slashNoResults');
      slashMenuElement.appendChild(empty);
      return;
    }

    for (const group of slashGroups) {
      const commands = slashRuntime.commands.filter((command) => command.group === group.id);
      if (commands.length === 0) continue;
      const section = document.createElement('section');
      section.className = 'weibei-slash-section';
      const heading = document.createElement('div');
      heading.className = 'weibei-slash-group';
      heading.textContent = editorLabel(group.label);
      section.appendChild(heading);

      for (const command of commands) {
        const commandIndex = slashRuntime.commands.findIndex((candidate) => candidate.id === command.id);
        const row = document.createElement('div');
        row.id = `weibei-slash-command-${command.id}`;
        row.className = `weibei-slash-command${commandIndex === slashRuntime.activeIndex ? ' is-active' : ''}`;
        row.setAttribute('role', 'option');
        row.setAttribute('aria-selected', commandIndex === slashRuntime.activeIndex ? 'true' : 'false');

        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'weibei-slash-command-button';
        button.textContent = editorLabel(command.label);
        button.tabIndex = -1;
        if (command.id === 'table') {
          const arrow = document.createElement('span');
          arrow.className = 'weibei-slash-command-arrow';
          arrow.textContent = '›';
          button.appendChild(arrow);
        }
        button.addEventListener('pointerdown', (event) => event.preventDefault());
        button.addEventListener('pointermove', (event) => {
          if (slashRuntime.pointerX === event.clientX && slashRuntime.pointerY === event.clientY) return;
          slashRuntime.pointerX = event.clientX;
          slashRuntime.pointerY = event.clientY;
          const nextTableOpen = command.id === 'table';
          if (slashRuntime.activeIndex === commandIndex && slashRuntime.tableOpen === nextTableOpen) return;
          slashRuntime.activeIndex = commandIndex;
          slashRuntime.tableOpen = nextTableOpen;
          renderSlashMenu();
        });
        button.addEventListener('click', () => {
          if (command.id === 'table') {
            slashRuntime.tableOpen = true;
            slashRuntime.tableFocus = 'rows';
            renderSlashMenu();
            return;
          }
          executeSlashCommand(command.id);
        });
        row.appendChild(button);

        if (command.id === 'table' && slashRuntime.tableOpen) {
          const panel = document.createElement('div');
          panel.className = 'weibei-slash-table-panel';
          panel.setAttribute('role', 'group');
          panel.setAttribute('aria-label', editorLabel('slashTable'));
          panel.addEventListener('pointerdown', (event) => event.preventDefault());
          panel.append(renderSlashTableStepper('rows'), renderSlashTableStepper('columns'));
          const insertButton = document.createElement('button');
          insertButton.type = 'button';
          insertButton.className = 'weibei-slash-table-insert';
          insertButton.textContent = editorLabel('slashInsertTable');
          insertButton.addEventListener('pointerdown', (event) => event.preventDefault());
          insertButton.addEventListener('click', () => executeSlashCommand('table'));
          panel.appendChild(insertButton);
          slashTablePanelElement = panel;
          document.body.appendChild(panel);
          positionTableSlashPanel(panel, button);
        }
        section.appendChild(row);
      }
      slashMenuElement.appendChild(section);
    }

    const active = slashMenuElement.querySelector('.weibei-slash-command.is-active');
    active?.scrollIntoView({ block: 'nearest' });
  };

  /**
   * Handles keyboard navigation while the slash menu remains focused in ProseMirror.
   *
   * @param {import('@milkdown/kit/prose/view').EditorView} view - Current ProseMirror view
   * @param {KeyboardEvent} event - Key event from the editor
   * @returns {boolean}
   */
  const handleSlashMenuKeyDown = (view, event) => {
    const context = slashContextForView(view, isEditable());
    const visible = slashMenuElement.dataset.show === 'true'
      && context
      && slashRuntime.dismissedContext !== context.key;
    if (!visible || event.isComposing || event.keyCode === 229) return false;

    if (event.key === 'Escape') {
      slashRuntime.dismissedContext = context.key;
      slashRuntime.provider?.hide();
      event.preventDefault();
      return true;
    }
    if (slashRuntime.tableOpen) {
      if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
        const delta = event.key === 'ArrowLeft' ? -1 : 1;
        if (slashRuntime.tableFocus === 'rows') {
          slashRuntime.tableRows = Math.min(20, Math.max(1, slashRuntime.tableRows + delta));
        } else {
          slashRuntime.tableColumns = Math.min(12, Math.max(1, slashRuntime.tableColumns + delta));
        }
        renderSlashMenu();
        event.preventDefault();
        return true;
      }
      if (event.key === 'Tab' || event.key === 'ArrowUp' || event.key === 'ArrowDown') {
        slashRuntime.tableFocus = slashRuntime.tableFocus === 'rows' ? 'columns' : 'rows';
        renderSlashMenu();
        event.preventDefault();
        return true;
      }
      if (event.key === 'Enter') {
        executeSlashCommand('table');
        event.preventDefault();
        return true;
      }
    }

    if (event.key === 'ArrowUp' || event.key === 'ArrowDown') {
      if (slashRuntime.commands.length === 0) return true;
      const delta = event.key === 'ArrowUp' ? -1 : 1;
      slashRuntime.activeIndex = (
        slashRuntime.activeIndex + delta + slashRuntime.commands.length
      ) % slashRuntime.commands.length;
      slashRuntime.tableOpen = false;
      renderSlashMenu();
      event.preventDefault();
      return true;
    }

    const activeCommand = slashRuntime.commands[slashRuntime.activeIndex];
    if (event.key === 'ArrowRight' && activeCommand?.id === 'table') {
      slashRuntime.tableOpen = true;
      slashRuntime.tableFocus = 'rows';
      renderSlashMenu();
      event.preventDefault();
      return true;
    }
    if ((event.key === 'Enter' || event.key === 'Tab') && activeCommand) {
      if (activeCommand.id === 'table') {
        slashRuntime.tableOpen = true;
        slashRuntime.tableFocus = 'rows';
        renderSlashMenu();
      } else {
        executeSlashCommand(activeCommand.id);
      }
      event.preventDefault();
      return true;
    }
    return false;
  };

  /**
   * Configures the Milkdown Slash provider.
   *
   * @param {import('@milkdown/kit/core').Ctx} ctx - Milkdown context
   */
  const configure = (ctx) => {
    ctx.set(weiBeiSlash.key, {
      view(view) {
        const provider = new SlashProvider({
          content: slashMenuElement,
          debounce: 0,
          offset: 6,
          root: document.body,
          shouldShow(updatedView) {
            const context = slashContextForView(updatedView, isEditable());
            return Boolean(context && slashRuntime.dismissedContext !== context.key);
          },
        });
        slashRuntime.provider = provider;
        slashRuntime.view = view;
        provider.onShow = () => {
          slashRuntime.view = view;
          renderSlashMenu();
        };
        provider.onHide = () => {
          slashRuntime.context = null;
          slashRuntime.activationContext = '';
          slashRuntime.tableOpen = false;
          slashRuntime.pointerX = null;
          slashRuntime.pointerY = null;
          slashTablePanelElement?.remove();
          slashTablePanelElement = null;
        };
        const dismissOutside = (event) => {
          if (slashMenuElement.dataset.show !== 'true'
              || slashMenuElement.contains(event.target)
              || slashTablePanelElement?.contains(event.target)
              || view.dom.contains(event.target)) {
            return;
          }
          const context = slashContextForView(view, isEditable());
          if (context) slashRuntime.dismissedContext = context.key;
          provider.hide();
        };
        const dismissOnWindowBlur = () => {
          const context = slashContextForView(view, isEditable());
          if (context) slashRuntime.dismissedContext = context.key;
          provider.hide();
        };
        document.addEventListener('pointerdown', dismissOutside, true);
        window.addEventListener('blur', dismissOnWindowBlur);
        provider.update(view);
        return {
          update(updatedView, previousState) {
            slashRuntime.view = updatedView;
            const context = slashContextForView(updatedView, isEditable());
            if (slashRuntime.dismissedContext && context?.key !== slashRuntime.dismissedContext) {
              slashRuntime.dismissedContext = '';
            }
            provider.update(updatedView, previousState);
          },
          destroy() {
            document.removeEventListener('pointerdown', dismissOutside, true);
            window.removeEventListener('blur', dismissOnWindowBlur);
            provider.destroy();
            slashMenuElement.remove();
            slashTablePanelElement?.remove();
            slashTablePanelElement = null;
            slashRuntime.provider = null;
            slashRuntime.view = null;
          },
        };
      },
    });
  };

  /**
   * Resolves a pending native image picker request.
   */
  const resolveImagePicker = (id, src, alt) => {
    const pending = pendingImagePickers.get(id);
    if (!pending) return false;
    pendingImagePickers.delete(id);
    const replacement = slashReplacement('image', pending.view.state.schema, { src, alt });
    return applySlashReplacement(pending.view, pending.context, replacement);
  };

  /**
   * Cancels a pending native image picker request.
   */
  const cancelImagePicker = (id) => {
    const pending = pendingImagePickers.get(id);
    if (!pending) return false;
    pendingImagePickers.delete(id);
    const paragraph = pending.view.state.schema.nodes.paragraph;
    if (!paragraph) return false;
    return applySlashReplacement(pending.view, pending.context, {
      content: Fragment.from(paragraph.create()),
      selectionOffset: 1,
    });
  };

  /**
   * Returns the Slash-only API exposed in editor check mode.
   */
  const checkAPI = () => ({
    openSlashMenuForCheck: () => {
      const view = slashRuntime.view;
      if (!view || !slashContextForView(view, isEditable())) return false;
      slashRuntime.dismissedContext = '';
      slashRuntime.provider?.show();
      renderSlashMenu();
      return slashMenuElement.dataset.show === 'true';
    },
    slashStateForCheck: () => ({
      show: slashMenuElement.dataset.show === 'true',
      commands: Array.from(slashMenuElement.querySelectorAll('.weibei-slash-command-button'))
        .map((button) => button.firstChild?.textContent || button.textContent || ''),
      groups: Array.from(slashMenuElement.querySelectorAll('.weibei-slash-group'))
        .map((group) => group.textContent || ''),
      icons: slashMenuElement.querySelectorAll('svg, img, [class*="icon"]').length,
      descriptions: slashMenuElement.querySelectorAll('[class*="description"]').length,
      tableOpen: Boolean(slashTablePanelElement?.isConnected),
      rows: slashRuntime.tableRows,
      columns: slashRuntime.tableColumns,
    }),
    openSlashTableForCheck: () => {
      const index = slashRuntime.commands.findIndex((command) => command.id === 'table');
      if (index < 0) return false;
      slashRuntime.activeIndex = index;
      slashRuntime.tableOpen = true;
      slashRuntime.tableFocus = 'rows';
      renderSlashMenu();
      return true;
    },
    setSlashTableSizeForCheck: (rows, columns) => {
      slashRuntime.tableRows = Math.min(20, Math.max(1, Number(rows) || 3));
      slashRuntime.tableColumns = Math.min(12, Math.max(1, Number(columns) || 3));
      renderSlashMenu();
      return true;
    },
    executeSlashCommandForCheck: (commandID) => {
      executeSlashCommand(commandID);
      return true;
    },
    pendingImagePickerIDsForCheck: () => Array.from(pendingImagePickers.keys()),
  });

  return {
    plugin: weiBeiSlash,
    configure,
    handleKeyDown: handleSlashMenuKeyDown,
    resolveImagePicker,
    cancelImagePicker,
    checkAPI,
    refresh: renderSlashMenu,
    isVisible: () => slashMenuElement.dataset.show === 'true',
  };
}
