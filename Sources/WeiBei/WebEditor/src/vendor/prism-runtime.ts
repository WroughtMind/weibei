// @ts-expect-error prismjs has no bundled declarations
import Prism from 'prismjs';
import 'prismjs/components/prism-bash';
import 'prismjs/components/prism-css';
import 'prismjs/components/prism-java';
import 'prismjs/components/prism-json';
import 'prismjs/components/prism-jsx';
import 'prismjs/components/prism-markdown';
import 'prismjs/components/prism-python';
import 'prismjs/components/prism-r';
import 'prismjs/components/prism-ruby';
import 'prismjs/components/prism-rust';
import 'prismjs/components/prism-sql';
import 'prismjs/components/prism-swift';
import 'prismjs/components/prism-tsx';
import 'prismjs/components/prism-typescript';
import 'prismjs/components/prism-yaml';

Prism.languages.stata = {
  comment: [
    { pattern: /(^|\n)\s*\*.*/, lookbehind: true },
    { pattern: /\/\/.*/ },
    { pattern: /\/\*[\s\S]*?\*\//, greedy: true },
  ],
  string: { pattern: /"[^"\n]*"/, greedy: true },
  macro: { pattern: /`[^'\n]*'|\$\{?\w+\}?/, alias: 'variable' },
  keyword: /\b(?:use|clear|gen(?:erate)?|egen|replace|drop|keep|merge|append|save|import|export|reg(?:ress)?|ivregress|areg|xtreg|logit|probit|tobit|test|testparm|lincom|nlcom|margins|display|di|summarize|sum|tabulate|tab|describe|predict|estat|esttab|estimates|vce|robust|cluster|if|in|foreach|forvalues|while|else|local|global|scalar|matrix|by|bysort|sort|gsort|label|rename|recode|encode|decode|reshape|collapse|preserve|restore|set|version|capture|quietly|noisily)\b/,
  function: /\b[a-zA-Z_]\w*(?=\()/,
  number: /\b\d+(?:\.\d+)?(?:e[+-]?\d+)?\b/i,
  operator: /[-+*/^=<>!&|~#]+/,
  punctuation: /[(){}[\],;:]/,
};
Prism.languages.do = Prism.languages.stata;
window.WeiBeiPrism = Prism;
