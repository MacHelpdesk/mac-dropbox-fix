// hint.js — decides whether a hook input calls for a hint. Called by skill-hint.sh.
//
// Runs under the JavaScript engine that ships with macOS:
//   osascript -l JavaScript hint.js MODE HOME      (hook input JSON on stdin)
//
// Prints one line: VERDICT SESSION
//   VERDICT  none        nothing to say
//            hint-fix    a prompt reports Dropbox stuck or not syncing
//            hint-use    a Bash command copies, moves or archives in a Dropbox folder
//            using-fix   the session is already using the dropbox-fix skill
//            using-use   the session is already using the dropbox-use skill
//   SESSION  the session id when it is safe as a file name, otherwise "-"
//
// Only decoded fields are matched: `prompt` in prompt mode; `tool_input.command` and
// `cwd` in bash mode. The input also carries transcript_path and a command description,
// which can contain the word Dropbox and must not count.
// Nothing here writes a file or sends an Apple event. Syntax stays ES5.

ObjC.import('Foundation');

// The closed lists. Adding an entry changes when the plugin interrupts a session; update
// the spec (skill-trigger-hooks), the tests and the README section in the same change.
var STUCK_TERMS = [
  /卡住/, /卡在/, /卡了/,
  /不同步/, /沒同步/, /沒有同步/, /沒在同步/, /無法同步/, /不能同步/, /同步不了/, /同步失敗/, /同步中/,
  /不動/, /怪怪的/,
  /吃.{0,6}cpu/i, /high\s+cpu/i,
  /not\s+sync/i, /n['’]t\s+sync/i, /stopped\s+syncing/i, /out\s+of\s+sync/i,
  /sync(ing)?\s+(issue|problem|error)/i, /stuck/i
];
var VERBS = ['cp', 'mv', 'rsync', 'ditto', 'tar', 'zip'];
var USE_SUBCOMMANDS = ['local-status', 'download'];
var SESSION_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

function out(text) {
  $.NSFileHandle.fileHandleWithStandardOutput.writeData($(text + '\n').dataUsingEncoding($.NSUTF8StringEncoding));
}

function readStdin() {
  var data = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
  var text = ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding));
  return typeof text === 'string' ? text : '';
}

function escapeRegExp(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function promptVerdict(prompt) {
  var slash = /^\s*\/(mac-dropbox-fix:)?dropbox-(fix|use)(\s|$)/.exec(prompt);
  var i;
  if (slash) { return 'using-' + slash[2]; }
  if (!/dropbox/i.test(prompt)) { return 'none'; }
  for (i = 0; i < STUCK_TERMS.length; i++) {
    if (STUCK_TERMS[i].test(prompt)) { return 'hint-fix'; }
  }
  return 'none';
}

// A verb counts at a command position: at the start, or after whitespace, a separator,
// an opening parenthesis, a backquote or a quote. An absolute path may stand in front of it
// there, so /bin/cp counts; scp does not, and neither does the last segment of ~/Dropbox/tar.
function hasVerb(command) {
  var pattern = new RegExp('(^|[\\s;&|(`"\'])(/[^\\s;&|()`"\']*/)?(' + VERBS.join('|') + ')(\\s|$)');
  return pattern.test(command);
}

// A Dropbox path form ends at a slash, whitespace, a quote, a shell separator, or the end.
function namesDropbox(command, home) {
  var after = '(/|\\s|["\']|[;)|&<>`]|$)';
  var forms = ['~/Dropbox', '\\$HOME/Dropbox', '\\$\\{HOME\\}/Dropbox'];
  var i;
  if (command.indexOf('Library/CloudStorage/Dropbox') !== -1) { return true; }
  if (home) { forms.push(escapeRegExp(home) + '/Dropbox'); }
  for (i = 0; i < forms.length; i++) {
    if (new RegExp(forms[i] + after).test(command)) { return true; }
  }
  return false;
}

function insideDropbox(cwd, home) {
  if (!cwd || !home) { return false; }
  if (cwd.indexOf(home + '/Library/CloudStorage/Dropbox') === 0) { return true; }
  return cwd === home + '/Dropbox' || cwd.indexOf(home + '/Dropbox/') === 0;
}

// Whether the command runs the plugin's own script, and for which skill. Running means the
// script is the program at the start of the command or after ; & | ( or a backquote,
// optionally after environment assignments and a shell name. Assigning its path to a
// variable at those positions counts too. The name as an argument of another program
// (a file being archived, say) does not.
function ownScript(command) {
  var position = '(?:^|[;&|(`])\\s*';
  var token = '["\']?[^\\s"\';&|()`]*dropbox-fix\\.sh["\']?';
  var end = '(?=\\s|$|[;&|)])';
  var env = '(?:[A-Za-z_][A-Za-z0-9_]*=[^\\s;&|]*\\s+)*';
  var shell = '(?:(?:/bin/)?(?:ba|z)?sh\\s+)?';
  var ran = new RegExp(position + env + shell + token + '(?:\\s+([a-z-]+))?' + end).exec(command);
  if (ran) { return USE_SUBCOMMANDS.indexOf(ran[1]) !== -1 ? 'using-use' : 'using-fix'; }
  if (new RegExp(position + '[A-Za-z_][A-Za-z0-9_]*=' + token + end).test(command)) { return 'using-fix'; }
  return '';
}

function bashVerdict(command, cwd, home) {
  var own = ownScript(command);
  if (own) { return own; }
  if (!hasVerb(command)) { return 'none'; }
  if (namesDropbox(command, home) || insideDropbox(cwd, home)) { return 'hint-use'; }
  return 'none';
}

function run(argv) {
  var mode = argv[0];
  var home = argv[1] || '';
  var verdict = 'none';
  var session = '-';
  var input;
  try {
    input = JSON.parse(readStdin());
  } catch (e) {
    out('none -');
    return;
  }
  if (input === null || typeof input !== 'object') { out('none -'); return; }
  if (typeof input.session_id === 'string' && SESSION_PATTERN.test(input.session_id)) {
    session = input.session_id;
  }
  if (mode === 'prompt') {
    if (typeof input.prompt === 'string') { verdict = promptVerdict(input.prompt); }
  } else if (mode === 'bash') {
    if (input.tool_input && typeof input.tool_input.command === 'string') {
      verdict = bashVerdict(input.tool_input.command, typeof input.cwd === 'string' ? input.cwd : '', home);
    }
  }
  out(verdict + ' ' + session);
}
