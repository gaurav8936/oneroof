# One Roof help: Learn

**Status:** LIVE · **Date:** 2026-10-31

> **One line:** Learn (⇧⌘E) is the narrated Agentic Engineering deck inside One Roof, in three views (Radio, Writing and All cards), with "How do I…?" answers and a player that keeps going while you work.

## Goal

Learning how to work with agents should not mean leaving the place where the work happens. Learn shows the deck that ships with One Roof but never copies or rewrites it: every card, skill, band and track name comes from the Agentic Engineering deck's own repository, packaged when the app is built.

## The shared page

Learn is the same Agentic Engineering page every site shows, from one copy. Each One Roof release saves that page inside the app, so it works offline and changes with the next release. Inside One Roof the page does One Roof things:

- **Play in One Roof** uses One Roof's player (it keeps playing while you work). Radio's display, dial and keys follow that player: ON AIR, the time into the card, the part and its chapter, ▶ / pause, the speed (0.75× to 2×) and ⏭. The card that plays shows a pause button wherever it is listed, and a card's header says **Pause** / **Resume**.
- **Listen** shows the scene One Roof is playing; **Transcript** marks it, and a scene's number plays from there.
- **Use in a session ▾** lists your live agent sessions; **Show in Finder** opens the card's folder.
- **Writing** reads posts inside Learn, and lists your own Learn folders' posts next to the blog's, which refresh while Learn is open.
- **All cards › By folder** is the deck folder as it ships in this build: open a file to read it, or **Open in Terminal** there.
- **How do I…?** ranks the cards the way One Roof does (below).

Links to sources and other sites open in your browser. The earlier native screens and their Settings switch were removed in 1.9.35; everything they did is on this page.

## Open it

- **⇧⌘E** (View › Learn), **Learn** in the places rail, or "Learn" in Search (⌘K).
- **From a skill:** the Learn button on any skill in Foundations › Skills, or a skill in Search, opens that skill's card.
- **From a session:** the Plan panel's **Related in Learn** lists the three cards that best match the session's name and objective.

## The three views

The control at the top right switches between them.

- **Radio:** the deck as a radio. Four bands (Context · Loops · Evidence · Procedure) sit on a dial, one line per card. Click a band key or an "On this band" chip to open the band, then pick what to hear. ▶, a line on the dial, ⏭, Play the band and a card's ▶ play. Programmes below play a set of cards in order.
- **Writing:** posts from the blog, with a broadcast schedule; open one to read it in Learn (its sections, the next and previous part of the series, and the cards to hear on its band). Posts in your own Learn folders (Settings › Learn, one folder per post with an `index.md`) join them.
- **All cards:** every card at a glance, **By band**, **By kind** or **By folder** (the deck's folder as it ships: click a folder to list it, a file to read it, double-click a skill to open its card).

A card's page (its **station**) has Listen (the card's own narrated page), Transcript and Skill file tabs, and **Play in One Roof**, **Use in a session ▾** (sends `/skill-name` to a live agent session), **Show in Finder** and **Open in browser** at the top.

Everything ships inside One Roof, audio included, and works offline. Narration: AI-generated voice (OpenAI text-to-speech); every player and the foot of the Learn page say so. One Roof leaves out pages that belong to another product: the **Career Agent** playbook is not listed or searched (`LearnExclusions`).

## How do I…? (⌥⌘/)

Ask a question in your own words and Learn opens the card that answers it best.

- **Ask:** Help › **How Do I…?** (**⌥⌘/**) puts the cursor in Learn's "How do I…? or search N cards" box. Type a question or a few words: the matching cards light up in All cards, with matching posts beside them.
- **From Search (⌘K):** the best cards come first; One Roof Help pages that match open on the Help page.
- **From a session:** the Plan panel's **More: how do I…** asks with the session's objective and opens the best card.
- **How it ranks:** by the words your question shares with each card's title, subtitle, description, triggers and track. A title word counts more, a word on nearly every card counts for little, small words like "how" and "the" are ignored, and "deploying" matches "deploy". No AI model, nothing leaves the Mac.

One Roof's own help is on the **Help** page (Help › One Roof Help), not in Learn.

## Listen while you work (the player)

- **Play:** ▶ on a card, a band or a programme. Each card plays its parts in order, one per narrated scene.
- **Player bar** (bottom of Learn): the card and the part you are on, previous / play-pause / next, a scrubber, the **speed** (0.75× to 2×, remembered), the **queue** (what plays next), and × to stop. Click the title to open the card.
- **Keep working:** the audio carries on in any other view. A **mini player** in the toolbar shows what is playing; its title opens the card.
- **Continue where you left off:** One Roof remembers the part and second for each card.

## The classic window

In the classic window (the older layout, if you switched back to it), Learn is the older list of pages: the deck's pages and cards, One Roof Help and your Learn folders' Markdown pages and narration folders, with a search box over all of them.
