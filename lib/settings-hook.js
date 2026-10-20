// Adds, removes or checks the claude-no-sleep UserPromptSubmit hook in a Claude Code settings.json; every other key stays as it was.
// Run: osascript -l JavaScript settings-hook.js add|remove|check <settings.json> [hook command]
ObjC.import('Foundation');

const MARK = 'claude-no-sleep';

function readText(path) {
  const text = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
  return text.isNil() ? null : ObjC.unwrap(text);
}

function writeText(path, text) {
  if (!$(text).writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null)) throw new Error('cannot write ' + path);
}

function withoutOurHook(groups) {
  return (groups || [])
    .map((group) => ({ ...group, hooks: (group.hooks || []).filter((hook) => !String(hook.command || '').includes(MARK)) }))
    .filter((group) => group.hooks.length > 0);
}

function run(argv) {
  const [action, path, command] = argv;
  const text = readText(path);
  const settings = text === null ? {} : JSON.parse(text);
  if (action === 'check') return;
  if (action !== 'add' && action !== 'remove') throw new Error('unknown action ' + action);
  const hooks = settings.hooks || {};
  const groups = withoutOurHook(hooks.UserPromptSubmit);
  if (action === 'add') groups.push({ hooks: [{ type: 'command', command: command, timeout: 10 }] });
  if (groups.length > 0) hooks.UserPromptSubmit = groups;
  else delete hooks.UserPromptSubmit;
  if (Object.keys(hooks).length > 0) settings.hooks = hooks;
  else delete settings.hooks;
  writeText(path, JSON.stringify(settings, null, 2) + '\n');
}
