# Callouts

Open this with **Settings ▸ General ▸ Reading ▸ Markdown flavor** set to each
choice in turn. Open documents re-render when you change it. Each section says
what to expect in **Extended** (the default) and in **GitHub**.

## GitHub's five alerts, tag alone on its line

*Extended and GitHub:* five callouts, each with its own icon and colour,
titled Note, Tip, Important, Warning and Caution.

> [!NOTE]
> Useful information that users should know, even when skimming content.

> [!TIP]
> Helpful advice for doing things better or more easily.

> [!IMPORTANT]
> Key information users need to know to achieve their goal.

> [!WARNING]
> Urgent info that needs immediate user attention to avoid problems.

> [!CAUTION]
> Advises about risks or negative outcomes of certain actions.

## A title on the tag line

*Extended:* a tip titled "Faster builds".
*GitHub:* a plain quotation that starts with the text "[!TIP] Faster builds", as GitHub shows it.

> [!TIP] Faster builds
> Run the tests for the package you changed first.

## Obsidian's kinds and aliases

*Extended:* each is a callout with its own icon, titled with its type: Abstract,
Info, Todo, Success, Faq (an alias, with the Question icon and colour), Failure,
Danger, Bug, Example and Quote.
*GitHub:* every one is a plain quotation.

> [!abstract]
> A summary of what follows.

> [!info]
> Something worth knowing.

> [!todo]
> Something still to do.

> [!success]
> It worked.

> [!faq]
> Why is this a question? Because `faq` is an alias of `question`.

> [!failure]
> It did not work.

> [!danger]
> Do not do this.

> [!bug]
> Here is what goes wrong.

> [!example]
> An example of it in use.

> [!quote]
> Words someone else said.

## GitHub's other rules

*Extended:* both are callouts.
*GitHub:* both are plain quotations: GitHub needs something after the tag,
and takes an alert only at the top level, not inside a list.

> [!NOTE]

- > [!TIP]
  > Inside a list item.

## A type nobody defined

*Extended:* a callout that looks like a note, titled "Recipe".
*GitHub:* a plain quotation.

> [!recipe]
> Flour, water, salt and time.

## Folding

*Extended:* the first is closed, with a chevron after its title; click the
title to open it. The second starts open. Opening or closing one survives an
edit to another part of the file in another app (the document reloads in
place); changing `-` to `+` in the file opens it. Printed, or exported to PDF, both
show their body.
*GitHub:* both are plain quotations that start with the tag.

> [!faq]- Closed until you open it
> The answer, hidden at first.

> [!faq]+ Open until you close it
> The answer, shown at first.
