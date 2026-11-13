---
name: asd-ste100
description: >
  Write or rewrite technical text in ASD-STE100 Simplified Technical English (STE): short
  sentences, one meaning for each word, active voice, imperative instructions, and clear
  warnings. Use when asked for STE, ASD-STE100, Simplified Technical English, or controlled
  language, or when non-native readers and translators must understand the text the first
  time: procedures, runbooks, READMEs, manuals, release notes, error messages, and safety
  instructions. Includes scripts/ste_check.py, a checker for the mechanical rules (sentence
  length, paragraph length, contractions, tenses, modal verbs, frequent unapproved words).
---

# ASD-STE100 Simplified Technical English

STE is a controlled language. It has a set of writing rules and a dictionary of approved
words. Each approved word has one meaning and one part of speech. The result is text that
a reader with basic English understands the first time, and that a translator cannot read
in two ways.

STE changes the words. It does not change the facts. If a rewrite loses a condition, a
value, or a risk, the rewrite is wrong.

## The authority is the standard, not this file

This skill gives the writing rules in short form and a small table of frequent words. It
does not contain the dictionary. The dictionary has a copyright, and ASD supplies the
standard free of charge on request at <https://www.asd-ste100.org>.

- If the user has a copy of the standard, use it. Read the dictionary entry for each
  word that you are not sure about. Ask for the path one time.
- If there is no copy, write with the rules and the word table below. Then tell the user
  that you did not do a check of the words against the dictionary.
- Do not say that a text "complies with ASD-STE100". Only a person with the standard can
  say that. Say "written to the STE rules".

## Scope

Rewrite: instructions, descriptions, warnings, notes, comments, and messages for the user.

Do not rewrite:

- Code, commands, paths, identifiers, and log output.
- Quoted text, and text that the interface shows (button labels, menu names). Copy it
  exactly, in quotation marks or as code.
- Legal text and license text.
- Text outside the scope that the user gave. Do not convert a full file when the user
  asked for one section.

## Workflow

1. Read the full text. Find the type of each part: procedure, description, or safety
   instruction. The rules are different for each type.
2. Make a list of the technical names and technical verbs of the subject (see "Software
   text"). Use each one with one meaning, and always the same spelling.
3. Rewrite. Keep each fact, condition, value, and sequence.
4. Run the checker and correct each error. Read each warning and make a decision.
5. Compare the result with the source, sentence by sentence. Make sure that no fact
   changed.
6. Report (see "Report").

## The rules

### Words

- Use an approved word only in its approved meaning and part of speech. Example: "check"
  is a noun ("do a check"), and "close" is a verb ("close the valve").
- One word has one meaning. One thing has one name. If you call it "the router" in
  step 1, do not call it "the server" in step 4.
- Use the approved forms of a word only. Do not make new forms.
- Write technical names and technical verbs as the subject uses them. They are not in the
  dictionary, but you can use them.
- Use American English spelling.
- Do not use contractions, Latin abbreviations, slang, or idioms.

### Noun clusters

- A noun cluster has three words at most ("engine oil pressure").
- If a technical name is longer, use hyphens to show the related words. As an
  alternative, explain the name one time and then use a shorter name.
- Put an article or a word such as "this" before a noun where English
  grammar asks for one. Do not remove articles to make a sentence shorter.

### Verbs

- Approved forms: the infinitive, the imperative, the simple present, the simple past,
  and the simple future.
- Use a past participle only as an adjective ("the valve is closed"). Do not use it to
  make a perfect tense ("has closed").
- Do not use the -ing form of a verb, unless the word is a technical name.
- Use the active voice. In a procedure, always. In a description, use the passive voice
  only when the agent is not known or not important.
- If a verb can show the action, use the verb, not a noun. Write "measure the gap", not
  "do the measurement of the gap". An approved noun is the exception: "do a check",
  "do a test".

### Sentences

- One topic for each sentence.
- Do not remove words to make a sentence shorter. Keep "that", the articles, and the
  subject.
- Use a vertical list when a sentence has three or more parallel items.
- Use words such as "and", "but", "thus", "then", and "because" to connect sentences.

### Procedures

- A sentence has 20 words at most.
- Write one instruction in each sentence. Write two only when the two actions occur at
  the same time.
- Use the imperative: "Stop the service."
- If an instruction has a condition, put the condition first: "If the test fails, stop
  the deployment."
- Give the steps in the sequence in which the reader does them.

### Descriptive text

- A sentence has 25 words at most.
- A paragraph has one topic and six sentences at most. The first sentence gives the topic.
- Give the information in a logical sequence, and go from known information to new
  information.
- Use sentences of different lengths. Do not use many one-sentence paragraphs.

### Safety instructions

- A warning is for a risk to persons. A caution is for a risk of damage to equipment or
  data. A note gives information only.
- Start a warning or a caution with a clear command. If a condition must come first, start
  with the condition.
- Then give the risk: tell the reader what can occur if they do not obey.
- Put the warning or the caution before the step that it applies to.
- Do not put an instruction in a note.

### Punctuation and word counts

- A number, an abbreviation, a hyphenated word, a quoted label, and an identifier each
  count as one word.
- Text in parentheses counts as a different sentence.
- A colon or a dash ends the count, as a full stop does.
- Use a hyphen to connect words that make one unit ("high-pressure pump").

## Software text

The standard comes from aerospace maintenance, but its rules for technical names and
technical verbs apply to each subject. For software:

- **Technical names**: identifiers, commands, file names, product names, protocol names,
  units, and the nouns of the domain ("branch", "container", "endpoint", "cache"). Put
  literal names in code format.
- **Technical verbs**: verbs that the domain uses and that have no approved equivalent
  ("commit", "merge", "deploy", "compile", "boot", "mount", "encrypt"). Use them as verbs
  only. Do not use them when an approved verb says the same thing: "run the script" is
  correct, and "execute the script" is not necessary.
- A verb that is also a command name is a technical name when it is in code format:
  "Do a `git pull`."
- Give the list of technical names and verbs to the checker with `--allow`.

## Frequent words

A memory aid for the frequent faults. The dictionary is the authority.

| Do not write | Write |
| --- | --- |
| utilize, leverage | use |
| perform, carry out, accomplish | do |
| ensure, verify | make sure, do a check |
| check (verb), test (verb) | do a check, do a test |
| begin, commence, initiate | start |
| terminate | stop |
| indicate, demonstrate | show |
| inform | tell |
| obtain | get |
| provide | give, supply |
| require, need to, have to | must, it is necessary |
| allow, permit, enable | let, make possible |
| should, shall | must, or the imperative |
| may, might, could | can, it is possible that |
| follow (an instruction) | obey |
| modify, alter | change |
| locate | find |
| attempt | try |
| rotate | turn |
| place (verb) | put |
| additional | more |
| proper, appropriate | correct, applicable |
| about (a quantity) | approximately |
| prior to | before |
| in order to | to |
| due to | because of |
| via | through, with |
| e.g. | for example |

## The checker

`scripts/ste_check.py` is in the directory of this file. It needs Python 3 only.

```bash
python3 scripts/ste_check.py docs/runbook.md
python3 scripts/ste_check.py --mode procedure --allow caching,logging steps.md
git show HEAD:README.md | python3 scripts/ste_check.py -
```

- It reads Markdown. It ignores code blocks, tables, headings, and front matter. Inline
  code and a URL each count as one word.
- In `auto` mode, a list item is a procedure (20 words) and a paragraph is a description
  (25 words). Use `--mode` when that is not correct for the file.
- An **E** line is an error: sentence length, paragraph length, a contraction, a perfect
  tense, a modal verb, or a word from the table. Correct each one, or add the word to
  `--allow` if it is a technical name.
- A **W** line is a warning: a possible passive, or an -ing word. Read it. A participle
  that is an adjective and an -ing word that is a technical name are correct.
- A clean result means that the checker found no mechanical fault. It cannot find a wrong
  meaning, a wrong part of speech, a long noun cluster, or a lost fact. Step 5 of the
  workflow is still necessary.

## Examples

Procedure:

> Before: Prior to restarting the service, you should ensure that all pending jobs have
> been drained, otherwise data may be lost.
>
> After:
>
> CAUTION: Make sure that the queue is empty before you start the service again. If jobs
> are in the queue, you can lose data.
>
> 1. Do a check of the queue: `jobs --pending`.
> 2. If the queue is not empty, wait until the jobs are complete.
> 3. Start the service again: `systemctl restart worker`.

Description:

> Before: The router, which is utilized for model serving, will be automatically started
> at login by launchd, allowing clients to connect without any additional setup being
> required.
>
> After: The router supplies the models to the clients. `launchd` starts the router when
> you log in. No more setup is necessary for the clients.

Error message:

> Before: Couldn't establish connection – the server might be down or you've been rate
> limited.
>
> After: The client cannot connect to the server. Make sure that the server is on. If the
> server is on, wait 60 seconds and try again.

## Report

When the rewrite is complete, tell the user:

- The result of the checker: errors, and the warnings that you kept and why.
- The technical names and technical verbs that you used.
- Each place where the source was not clear and you made a decision about the meaning.
- That you did, or did not, do a check of the words against the dictionary.
