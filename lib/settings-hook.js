// Adds or removes the claude-no-sleep UserPromptSubmit hook in a Claude Code settings.json; check only validates the JSON. Every other key stays as it was.
// Run: osascript -l JavaScript settings-hook.js add|remove|check <settings.json> [hook command]
ObjC.import('Foundation');

const MARK = 'claude-no-sleep';

function readText(path) {
  const text = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
  if (!text.isNil()) return ObjC.unwrap(text);
  if (!$.NSFileManager.defaultManager.fileExistsAtPath(path)) return null;
  throw new Error('cannot read ' + path);
}

function writeText(path, text) {
  if (!$(text).writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null)) throw new Error('cannot write ' + path);
}

function isOurHook(hook) {
  return String(hook.command || '').includes(MARK);
}

function hasOurHook(groups) {
  return (groups || []).some((group) => (group.hooks || []).some(isOurHook));
}

function withoutOurHook(groups) {
  return (groups || [])
    .map((group) => ({ ...group, hooks: (group.hooks || []).filter((hook) => !isOurHook(hook)) }))
    .filter((group) => group.hooks.length > 0);
}

function run(argv) {
  const [action, path, command] = argv;
  const file = ObjC.unwrap($(path).stringByResolvingSymlinksInPath);
  const text = readText(file);
  const settings = text === null ? {} : JSON.parse(text);
  if (action === 'check') return;
  if (action !== 'add' && action !== 'remove') throw new Error('unknown action ' + action);
  const hooks = settings.hooks || {};
  if (action === 'remove' && !hasOurHook(hooks.UserPromptSubmit)) return;
  const groups = withoutOurHook(hooks.UserPromptSubmit);
  if (action === 'add') groups.push({ hooks: [{ type: 'command', command: command, timeout: 10 }] });
  if (groups.length > 0) hooks.UserPromptSubmit = groups;
  else delete hooks.UserPromptSubmit;
  if (Object.keys(hooks).length > 0) settings.hooks = hooks;
  else delete settings.hooks;
  writeText(file, JSON.stringify(settings, null, 2) + '\n');
}
