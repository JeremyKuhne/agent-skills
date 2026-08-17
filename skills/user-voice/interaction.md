# Ask clear questions

Keep exact technical terms in private records and validators when they prevent
mistakes. Do not make the user learn those terms to make a decision. Use the
simplest accurate words, and add detail only when it helps the user judge the
choice.

## Translate internal terms

| Internal term | Say this to the user |
| --- | --- |
| candidate | draft profile that is not active |
| scope or context | kinds of writing where the profile may be used |
| artifact | kind of writing or document |
| source-derived | based on confirmed writing samples |
| provisional | not ready for use; general writing will be used instead |
| promotion | make this approved for the stated use |
| disposition | what to do with the result |
| elicitation | optional preference checks |
| genericity control | check whether the draft profile adds useful value beyond clear general writing |
| epistemic behavior | how the writing separates facts, expectations, judgments, and unknowns |
| no-churn | both outputs are exactly the same, so there is nothing to rate |
| read-back | review and confirm the summary |
| de-identified | privacy-protected summary with names and recognizable details removed |
| retention | what private evidence will be kept and for how long |
| invocation | how to use the profile in the editor or client |
| portability | moving the profile to another machine |
| canonical profile | reviewed main copy of the profile |
| context matrix | private map of where each writing rule may be used |
| counterevidence | examples that do not fit the proposed rule |
| confidence | how strongly the available evidence supports the rule |
| source-capable agent | another agent that can access those sources |

Do not replace a precise term inside a file format, command, field name, or
validator message when the exact term is needed. Translate it in the question
and explanation around that internal value.

Do not ask the user to repeat state that tools or files already establish. State
verified facts directly. Ask only for a choice, missing information, or a
clarification that can change the result.

## Build each decision prompt

Every question must stand on its own. Include the practical task and all text
needed to answer that specific question. Do this even when several questions
appear in one dialog; a shared message on another question does not count. Never
ask `How much editing would A need?` without repeating the task and complete A
text in that question.

For blind comparisons, use separate steps:

1. show all options and ask which version the user would rather edit;
2. ask how much editing each option needs, with the task and complete option
   repeated in each rating question; and
3. repeat the task and complete preferred option before asking for its first
   meaningful edit.

The preference already identifies the starting point. Ask another starting-point
question only after a tie, `None`, or a manual replacement.

Before showing choices:

1. Ask a plain-English question about the practical decision.
2. Say what the decision changes.
3. Summarize the evidence in ordinary language.
4. Say what accepting the result does not do, especially when it does not
   activate, install, publish, send, commit, or push anything.
5. Offer four paths whose labels describe the action:
   - accept the specific result;
   - change the summary or boundary;
   - explain the result in more detail; and
   - leave it undecided or discard the test.

Avoid labels such as `Approve candidate scope`, `Accept disposition`, or
`Reject genericity interpretation`. They require the user to translate the
system before judging the underlying choice. `Skip` is also unclear; say what
will remain undecided or inactive.

## Explain an action before asking for approval

For a build, install, commit, push, transfer, or retirement decision, lead with
the practical change rather than the command or audit record. State:

1. what behavior or user-visible state changes;
2. why the change is proposed and what evidence supports it;
3. what remains unsupported, unresolved, or unchanged;
4. what the requested action will do; and
5. which later actions it does not authorize.

Only then provide exact paths, manifests, hashes, author, destination, and
commands needed to bind the approval. Put long audit detail in a linked local
review document. A technically exact prompt is still inadequate when the user
cannot tell why the change matters.

For a commit, summarize what will enter history and its effect on the profile.
For a push, summarize where that exact commit will be copied and whether the
privacy or access boundary changes. Ask for those approvals separately.

## Explain before asking again

When the user selects the explanation path, change no file, score, confidence,
approval, or runtime state. Explain:

- what was compared or reviewed;
- what the result means in practical terms;
- which observed differences likely affected the result;
- one short synthetic example when it makes the distinction clearer;
- what would change if the user accepts the result; and
- what would remain unchanged.

Then ask the same decision again with the accept, change, explain, and not-now
choices. Do not treat a request for explanation as hesitation, rejection, or
approval.

If a later answer conflicts with an earlier one, the clarification prompt must
repeat the practical task, the complete option the user selected, and the two
answers that conflict. Do not ask the user to remember text from a collapsed or
previous prompt. The clarification changes no state until the user answers it.

Use the same rule for every follow-up about a selected option. Do not place a
context-free option rating or edit question beside the original blind choice
and expect the user to look the text up again.

## Example: where the profile may be used

Ask:

> Where should this profile be allowed to shape your writing?

Explain the initial decision before offering choices:

> This decides which kinds of writing may use the profile. Anything not ready
> will continue using general technical writing. This does not install or
> activate the draft profile.

Offer:

- `These uses look right`
- `Change the list`
- `Explain what each category means`
- `Leave these uses undecided`

## Example: value beyond general writing

Ask:

> Did the draft profile add useful value beyond clear general writing in this
> kind of work?

Explain the result before the choices:

> The draft profile was preferred in three cases, tied in one, and lost one.
> That passes the agreed test. Accepting this result records that the draft
> profile helped in this kind of writing. It does not approve the full profile,
> activate it, or install it.

Offer:

- `Use this test result`
- `Change the summary`
- `Explain this result in more detail`
- `Discard this test result`

If the test fails, say that it stays off for this kind of writing until a
revised draft passes a new test. Do not hide a failed threshold behind a general
statement that the results were mixed.

## Example: compare the new draft with the old profile

Ask:

> Which version would you rather edit?

Explain the initial decision before offering choices:

> You will see three versions built from the same facts: the new draft, the old
> private profile, and clear general writing. Their labels are hidden and change
> from case to case. This checks whether the new draft keeps the useful parts of
> the old profile without losing safety or clarity. It does not approve,
> activate, or install the new draft.

After each choice, ask separately how much editing each version would need.
Then repeat the task and complete chosen starting version before asking which
edit matters first. Do not reveal which version is which until all seven cases
are answered.

After the batch, offer:

- `Use this comparison result`
- `Change the summary`
- `Explain this comparison in more detail`
- `Discard this comparison`

If the user asks for more detail, explain which kinds of tasks favored each
version, what the edit ratings mean, the pass rule, and what accepting the
result would and would not change. Then ask again.
