# Brainstorming

> Ported from obra/superpowers. Refines a rough idea into a shared design
> *before* any plan or code exists.

**Announce:** "I'm using the brainstorming skill to refine this idea."

## When to use

The user has a goal but the design is fuzzy: "I want X", "we should add Y",
"can we make Z faster". Don't plan or code yet — converge on *what* and *why*
first. Skip only when the user hands you an already-precise spec.

## The method

1. **Ask, don't assume.** Pull out the real requirement with questions, one
   thread at a time. Cover: the problem behind the request, who/what consumes
   it, constraints (perf, security, deadlines, existing code), what "done"
   looks like, and what is explicitly *out* of scope.
2. **Reflect back.** Restate the problem in your own words and confirm before
   proposing solutions. Catch misunderstandings early.
3. **Explore the space.** Offer 2–3 distinct approaches with honest
   trade-offs. Name the one you'd pick and why. Don't bury the recommendation.
4. **Present the design in digestible sections.** Architecture, data flow,
   interfaces, failure modes — one section at a time, checking alignment as
   you go rather than dumping a wall of text.
5. **Surface the risky parts.** Call out the unknowns, the parts most likely
   to be wrong, and what would have to be true for the design to hold.

## kiro adaptations

- Investigate the codebase with `fs_read` / `execute_bash` (`rg`, `git log`)
  before proposing — ground the design in what's actually there.
- If the work spans multiple independent systems, note it now: each system
  should become its own plan (see `writing-plans.md`).
- Honor the catalog's steering files (security, secrets, stack conventions)
  as hard constraints while exploring options.

## Output

A short shared design the user has agreed to — enough to hand to
`writing-plans.md`. Not code. Not a full plan. Just aligned intent +
approach + the known risks.

## Red flags

- Proposing a solution before you understand the problem.
- One giant design dump with no checkpoints.
- Hiding the trade-offs or your recommendation.
- Drifting into implementation detail the user hasn't agreed to.
